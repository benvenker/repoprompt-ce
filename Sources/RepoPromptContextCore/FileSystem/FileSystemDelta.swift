import Foundation

public enum FileSystemDelta: Sendable, Equatable {
    case fileAdded(String)
    case fileRemoved(String)
    case folderAdded(String)
    case folderRemoved(String)
    case fileModified(String, Date?)
    case folderModified(String, Date? = nil)
}
