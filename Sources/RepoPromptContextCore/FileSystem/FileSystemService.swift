import Dispatch
import Foundation
#if canImport(Combine)
    import Combine
#endif
#if canImport(CoreServices)
    import CoreServices
#endif
#if (DEBUG || EDIT_FLOW_PERF) && canImport(os)
    import os
#endif
import CoreFoundation
import Cuchardet
import UniversalCharsetDetection
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    import Darwin
#else
    import Glibc
#endif

public actor FileSystemService {
    // Internal for FileSystemService same-target extensions only.
    // These are not public API; preserve actor isolation when accessing them.
    public let fileManager = FileManager.default
    nonisolated let diagnosticRootToken = UUID()
    nonisolated let watcherIngressMailbox: FileSystemWatcherIngressMailbox
    public static let maxPendingRawEvents = 50000
    public static let overflowRescanEventFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
    )

    #if DEBUG
        /// Static flag to enable verbose debug logging (default: false)
        static var enableDebugLogging = false
    #endif

    public func fileSystemDebugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
            guard Self.enableDebugLogging else { return }
            print(message())
        #endif
    }

    @discardableResult
    public func publishFileSystemDeltas(
        _ deltas: [FileSystemDelta],
        source: FileSystemDeltaPublicationSource,
        watcherAcceptedWatermark: FileSystemWatcherIngressMailbox.Watermark? = nil
    ) -> UInt64 {
        guard !deltas.isEmpty || watcherAcceptedWatermark != nil || source == .watcherBarrierNoop else {
            return lastServicePublicationSequence
        }
        nextServicePublicationSequence &+= 1
        let servicePublicationSequence = nextServicePublicationSequence
        lastServicePublicationSequence = servicePublicationSequence
        if let watcherAcceptedWatermark {
            lastPublishedWatcherAcceptedWatermark = max(lastPublishedWatcherAcceptedWatermark, watcherAcceptedWatermark)
        }
        let publication = FileSystemDeltaPublication(
            servicePublicationSequence: servicePublicationSequence,
            source: source,
            watcherAcceptedWatermark: watcherAcceptedWatermark,
            deltas: deltas
        )
        #if DEBUG || EDIT_FLOW_PERF
            let publicationCorrelation = EditFlowPerf.makeLifecycleCorrelationIfActive()
            EditFlowPerf.lifecycleEvent(
                EditFlowPerf.Lifecycle.FileSystem.servicePublish,
                correlation: publicationCorrelation,
                EditFlowPerf.Dimensions(
                    status: source.rawValue,
                    changeCount: deltas.count,
                    rootToken: diagnosticRootToken.uuidString,
                    ingressSequence: watcherAcceptedWatermark?.rawValue,
                    barrierSequence: servicePublicationSequence
                )
            )
            guard let publicationCorrelation else {
                changePublisher.send(publication)
                return servicePublicationSequence
            }
            EditFlowPerf.$currentFileSystemPublicationCorrelation.withValue(publicationCorrelation) {
                changePublisher.send(publication)
            }
        #else
            changePublisher.send(publication)
        #endif
        return servicePublicationSequence
    }

    #if DEBUG
        /// Debug override for filesystem operations
        var fileManagerOverride: (any FileSystemProviding)?

        /// Returns the appropriate filesystem provider (debug override or default)
        var fm: any FileSystemProviding {
            fileManagerOverride ?? fileManager
        }
    #else
        /// In release builds, always use FileManager.default
        var fm: FileManager {
            fileManager
        }
    #endif

    #if DEBUG
        /// Flag to enable test mode
        var isTestMode = false

        /// Test-only tracking of processed events
        var processedFolders: Set<String> = []

        /// Test-only method to mock directory contents
        var mockDirectoryContents: ((String) -> [String])?

        /// Test-only gate after a watcher batch leaves the pending buffer but before processing.
        var watcherBatchWillProcessHandler: (@Sendable () async -> Void)?

        /// Test-only hook invoked inside the real-filesystem off-actor content worker before each read.
        var contentReadChunkHandler: (@Sendable (String) async -> Void)?
    #endif

    /// Tracks paths we know about, to detect additions/removals
    public var visitedPaths = Set<String>()

    /// True => directory, False => file
    public var visitedItems = [String: Bool]()

    /// The FSEvent stream reference
    public var fseventStreamRef: FSEventStreamRef?

    /// Publishes ordered delta envelopes whenever changes or watcher progress occur.
    public var changePublisher = PassthroughSubject<FileSystemDeltaPublication, Never>()
    public var nextServicePublicationSequence: UInt64 = 0
    public var lastServicePublicationSequence: UInt64 = 0
    public var lastPublishedWatcherAcceptedWatermark = FileSystemWatcherIngressMailbox.Watermark.zero
    #if DEBUG
        var lastPublishedDeltaCoalescingDiagnostics: PublishedDeltaCoalescingDiagnostics?
    #endif

    /// Retained pointer to self (to avoid deallocation while FSEvent stream is active)
    public var selfPointer: UnsafeMutableRawPointer?

    /// The in-memory IgnoreRules instance for our path
    public var ignoreRules: IgnoreRules

    public var ignoreCacheStore = IgnoreCacheStore()

    /// Caches the detected encoding for every file we have successfully opened
    public var encodingMap = [String: String.Encoding]()

    /// Path we are managing
    public let path: String
    public let rootURL: URL
    public let canonicalRootURL: URL
    public var canonicalRootPath: String {
        canonicalRootURL.path
    }

    public var standardizedRootPath: String {
        rootURL.path
    }

    public var respectGitignore: Bool
    public var respectRepoIgnore: Bool
    public var respectCursorignore: Bool
    public var skipSymlinks: Bool
    public var enableHierarchicalIgnores: Bool

    // MARK: - Ignore rules change tracking (revision-based for durability)

    /// Monotonic revision incremented each time ignore files change
    public var ignoreRulesRevision: UInt64 = 0
    /// Directories affected by ignore file changes since last consumption
    public var pendingIgnoreChangeDirs: Set<String> = []

    // A buffer for raw FSEvents + coalescing logic
    public var pendingFSEvents: [PendingFSEvent] = []
    public var pendingWatcherAcceptedHighWatermark: FileSystemWatcherIngressMailbox.Watermark?
    public var pendingWatcherPublicationSource: FileSystemDeltaPublicationSource = .watcher
    public var hasPendingOverflowRescan = false
    public var overflowChangedIgnoreDirs: Set<String> = []
    public var coalescingTask: Task<Void, Never>?
    public var watcherBatchProcessingTask: Task<Void, Never>?
    public var watcherBatchProcessingToken: UInt64?
    public var nextWatcherBatchProcessingToken: UInt64 = 0
    public var watcherIngressGeneration: UInt64 = 0
    public let coalescingDelay: TimeInterval = 0.2

    // MARK: - Event ID-based scan coalescing (prevents dropped events while deduping bursts)

    /// Maps folder relative path → highest FSEvent ID that requires scanning
    public var pendingScanTargets: [String: FSEventStreamEventId] = [:]
    /// Maps folder relative path → highest FSEvent ID that has already been scanned
    public var lastScannedEventIdByFolder: [String: FSEventStreamEventId] = [:]

    /// Short-lived cache
    /// results during a directory walk to avoid repeated allocations.
    public var pathCompsCache = PathComponentsCache()

    /// Maximum number of cached ignore rules (default: 4000)
    public static let ignoreCacheCapacity = 4000

    /// Cache for per-folder ignore rules (key = directory's relative path, "" for root)
    public var perFolderIgnoreCache = LRUCache<String, IgnoreRules>(
        capacity: FileSystemService.ignoreCacheCapacity
    )

    /// Bounded marker cache for directories that have no ignore files.
    /// Eviction is safe: it only causes an extra filesystem recheck.
    public var noIgnoreFileCache = LRUCache<String, Bool>(
        capacity: FileSystemService.ignoreCacheCapacity
    )

    // MARK: - Parallelism Throttling

    /// Maximum concurrent directory scans per actor (prevents CPU saturation)
    public let maxParallelScansPerActor: Int

    /// Maximum folders to scan in a single batch (bounds per-tick work)
    public let maxFoldersPerBatch: Int

    // MARK: - Safety-Net Verification

    /// Minimum interval between safety-net scans for the same folder (seconds)
    public let safetyNetMinInterval: TimeInterval = 300 // 5 minutes

    /// Number of file events before triggering a safety-net parent scan
    public let safetyNetEventThreshold: Int = 200

    /// Tracks when each folder was last verified via directory scan
    public var lastVerifiedAtByFolder: [String: TimeInterval] = [:]

    /// Tracks file event count per folder since last verification
    public var fileEventCountSinceLastScan: [String: Int] = [:]

    // MARK: - Init

    /// Initializes the FileSystemService for a given path, applying ignore rules, optionally skipping symlinks,
    /// and immediately starting an FSEvents watcher to track changes in that path.
    public init(
        path: String,
        respectGitignore: Bool = true,
        respectRepoIgnore: Bool = true,
        respectCursorignore: Bool = true,
        skipSymlinks: Bool = true,
        enableHierarchicalIgnores: Bool = true
    ) async throws {
        self.path = path
        rootURL = URL(fileURLWithPath: path).standardizedFileURL
        canonicalRootURL = rootURL.resolvingSymlinksInPath()
        self.respectGitignore = respectGitignore
        self.respectRepoIgnore = respectRepoIgnore
        self.respectCursorignore = respectCursorignore
        self.skipSymlinks = skipSymlinks
        self.enableHierarchicalIgnores = enableHierarchicalIgnores

        watcherIngressMailbox = FileSystemWatcherIngressMailbox(maxQueuedRawEntries: Self.maxPendingRawEvents)

        // Configure parallelism caps based on available cores
        let cores = ProcessInfo.processInfo.activeProcessorCount
        maxParallelScansPerActor = max(2, min(4, cores / 2))
        maxFoldersPerBatch = 256

        // Load fresh ignore rules from manager, no caching done by manager
        ignoreRules = try await IgnoreRulesManager.shared.getIgnoreRules(
            for: path,
            respectGitignore: respectGitignore,
            respectRepoIgnore: respectRepoIgnore,
            respectCursorignore: respectCursorignore
        )

        // Initialize root-level ignore rules in per-folder cache
        cacheIgnoreRules(ignoreRules, for: "")
    }

    #if DEBUG
        /// Test-only initializer that allows injecting initial state
        init(
            path: String,
            respectGitignore: Bool = true,
            respectRepoIgnore: Bool = true,
            respectCursorignore: Bool = true,
            skipSymlinks: Bool = true,
            enableHierarchicalIgnores: Bool = true,
            testVisitedPaths: Set<String>? = nil,
            testVisitedItems: [String: Bool]? = nil,
            testIgnoreRules: IgnoreRules? = nil,
            isTestMode: Bool = false,
            fileManagerOverride: (any FileSystemProviding)? = nil,
            maxParallelScansOverride: Int? = nil,
            maxFoldersPerBatchOverride: Int? = nil,
            maxPendingWatcherIngressEntriesOverride: Int? = nil
        ) async throws {
            self.path = path
            rootURL = URL(fileURLWithPath: path).standardizedFileURL
            canonicalRootURL = rootURL.resolvingSymlinksInPath()
            self.respectGitignore = respectGitignore
            self.respectRepoIgnore = respectRepoIgnore
            self.respectCursorignore = respectCursorignore
            self.skipSymlinks = skipSymlinks
            self.enableHierarchicalIgnores = enableHierarchicalIgnores
            self.isTestMode = isTestMode
            self.fileManagerOverride = fileManagerOverride

            watcherIngressMailbox = FileSystemWatcherIngressMailbox(
                maxQueuedRawEntries: maxPendingWatcherIngressEntriesOverride ?? Self.maxPendingRawEvents
            )

            // Configure parallelism caps (allow test overrides)
            let cores = ProcessInfo.processInfo.activeProcessorCount
            maxParallelScansPerActor = maxParallelScansOverride ?? max(2, min(4, cores / 2))
            maxFoldersPerBatch = maxFoldersPerBatchOverride ?? 256

            // Use test data if provided
            if let paths = testVisitedPaths {
                visitedPaths = paths
            }
            if let items = testVisitedItems {
                visitedItems = items
            }

            // Use test ignore rules or load fresh ones
            if let rules = testIgnoreRules {
                ignoreRules = rules
            } else {
                #if DEBUG
                    // Pass the fileManagerOverride to IgnoreRulesManager if we have one
                    if let override = fileManagerOverride {
                        await IgnoreRulesManager.shared.setFileManagerOverride(override)
                    }
                #endif
                ignoreRules = try await IgnoreRulesManager.shared.getIgnoreRules(
                    for: path,
                    respectGitignore: respectGitignore,
                    respectRepoIgnore: respectRepoIgnore,
                    respectCursorignore: respectCursorignore
                )
            }

            // Initialize root-level ignore rules in per-folder cache
            cacheIgnoreRules(ignoreRules, for: "")
        }

    #endif
}
