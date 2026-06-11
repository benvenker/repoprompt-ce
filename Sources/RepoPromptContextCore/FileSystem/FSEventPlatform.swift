import Foundation

#if canImport(CoreServices)
    import CoreServices
#else
    public typealias FSEventStreamEventFlags = UInt32
    public typealias FSEventStreamEventId = UInt64
    public typealias FSEventStreamRef = OpaquePointer

    public let kFSEventStreamEventFlagMustScanSubDirs = 0x0000_0001
    public let kFSEventStreamEventFlagUserDropped = 0x0000_0002
    public let kFSEventStreamEventFlagKernelDropped = 0x0000_0004
    public let kFSEventStreamEventFlagRootChanged = 0x0000_0020
    public let kFSEventStreamEventFlagItemCreated = 0x0000_0100
    public let kFSEventStreamEventFlagItemRemoved = 0x0000_0200
    public let kFSEventStreamEventFlagItemInodeMetaMod = 0x0000_0400
    public let kFSEventStreamEventFlagItemRenamed = 0x0000_0800
    public let kFSEventStreamEventFlagItemModified = 0x0000_1000
    public let kFSEventStreamEventFlagItemFinderInfoMod = 0x0000_2000
    public let kFSEventStreamEventFlagItemChangeOwner = 0x0000_4000
    public let kFSEventStreamEventFlagItemXattrMod = 0x0000_8000
    public let kFSEventStreamEventFlagItemIsFile = 0x0001_0000
    public let kFSEventStreamEventFlagItemIsDir = 0x0002_0000
    public let kFSEventStreamEventFlagItemIsSymlink = 0x0004_0000
#endif
