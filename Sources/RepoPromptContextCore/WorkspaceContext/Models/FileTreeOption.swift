import Foundation

public enum FileTreeOption: String, CaseIterable, Identifiable, Codable {
    case none
    case selected
    case files
    case auto

    public var id: String { rawValue }
}
