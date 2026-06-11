import Foundation

#if canImport(CoreServices)
    import CoreServices
#endif

public struct FSEventCallbackEntry {
    public let path: String
    public let flags: FSEventStreamEventFlags
    public let id: FSEventStreamEventId
}
