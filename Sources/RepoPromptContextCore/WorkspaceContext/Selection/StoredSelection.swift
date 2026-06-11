import Foundation

public struct StoredSelection: Codable, Equatable {
    public let selectedPaths: [String]
    public let autoCodemapPaths: [String]
    public let slices: [String: [LineRange]]
    public let codemapAutoEnabled: Bool

    public init(
        selectedPaths: [String] = [],
        autoCodemapPaths: [String] = [],
        slices: [String: [LineRange]] = [:],
        codemapAutoEnabled: Bool = true
    ) {
        self.selectedPaths = selectedPaths
        self.autoCodemapPaths = autoCodemapPaths
        self.slices = slices
        self.codemapAutoEnabled = codemapAutoEnabled
    }
}
