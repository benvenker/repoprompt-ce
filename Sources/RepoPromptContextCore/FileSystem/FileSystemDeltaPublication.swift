import Foundation

public enum FileSystemDeltaPublicationSource: String {
    case watcher
    case syntheticMutation
    case watcherBarrierNoop
    case overflowRootRescan
}

public struct FileSystemDeltaPublication {
    public let servicePublicationSequence: UInt64
    public let source: FileSystemDeltaPublicationSource
    public let watcherAcceptedWatermark: FileSystemWatcherIngressMailbox.Watermark?
    public let deltas: [FileSystemDelta]

    public init(
        servicePublicationSequence: UInt64,
        source: FileSystemDeltaPublicationSource,
        watcherAcceptedWatermark: FileSystemWatcherIngressMailbox.Watermark?,
        deltas: [FileSystemDelta]
    ) {
        self.servicePublicationSequence = servicePublicationSequence
        self.source = source
        self.watcherAcceptedWatermark = watcherAcceptedWatermark
        self.deltas = deltas
    }
}
