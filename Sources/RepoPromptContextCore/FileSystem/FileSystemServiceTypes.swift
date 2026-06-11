import Foundation
#if canImport(CoreServices)
    import CoreServices
#endif
#if (DEBUG || EDIT_FLOW_PERF) && canImport(os)
    import os
#endif

public enum FileSystemPublishPerf {
    #if (DEBUG || EDIT_FLOW_PERF) && canImport(os)
        typealias State = OSSignpostIntervalState
        static let signposter = OSSignposter(subsystem: "com.repoprompt.workspace", category: "fs-publish")
        static var isEnabled: Bool {
            UserDefaults.standard.bool(forKey: "enableRepoFileReplaySignposts")
        }

        static func begin(_ name: StaticString) -> State? {
            guard isEnabled else { return nil }
            return signposter.beginInterval(name)
        }

        static func end(_ name: StaticString, _ state: State?) {
            guard isEnabled, let state else { return }
            signposter.endInterval(name, state)
        }
    #else
        struct State {}
        static var isEnabled: Bool {
            false
        }

        static func begin(_ name: StaticString) -> State? {
            nil
        }

        static func end(_ name: StaticString, _ state: State?) {}
    #endif
}

public typealias PendingFSEvent = (path: String, flags: FSEventStreamEventFlags, id: FSEventStreamEventId)

public struct PendingFSEventBatch {
    public var events: [PendingFSEvent] = []
    public var watcherAcceptedHighWatermark: FileSystemWatcherIngressMailbox.Watermark?
    public var publicationSource: FileSystemDeltaPublicationSource = .watcher
    public var watcherIngressGeneration: UInt64?

    public var isEmpty: Bool {
        events.isEmpty
    }
}

public struct FSPreparedChunk {
    public let folders: [FSItemDTO]
    public let files: [FSItemDTO]
}

#if DEBUG
    public struct PublishedDeltaCoalescingDiagnostics: Equatable {
        let rawDeltaCount: Int
        let publishedDeltaCount: Int
    }
#endif

public enum LoadContentsEvent {
    case totalFileCount(Int) // emitted at least once, first emission precedes item payloads
    case items([(any FileSystemItem, [String])]) // legacy compatibility
    case preparedItems(FSPreparedChunk) // preferred streaming payload
}

// MARK: - Encoding support -----------------------------------------------------

/// Bundles the decoded text with the encoding that produced it.
public struct DetectedText {
    public let string: String
    public let encoding: String.Encoding
}
