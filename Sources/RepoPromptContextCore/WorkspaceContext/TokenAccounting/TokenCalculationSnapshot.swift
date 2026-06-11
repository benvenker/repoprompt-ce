import Foundation

public struct PromptFileEntrySnapshot {
    public let fileID: UUID
    public let relativePath: String
    public let isCodemapRequested: Bool
    public let ranges: [LineRange]?
    public let cachedFullTokenCount: Int?
    public let loadedContent: String?
    public let codeMapContent: String?
    public let availableCodeMapTokenCount: Int

    public init(
        fileID: UUID,
        relativePath: String,
        isCodemapRequested: Bool,
        ranges: [LineRange]?,
        cachedFullTokenCount: Int?,
        loadedContent: String?,
        codeMapContent: String?,
        availableCodeMapTokenCount: Int
    ) {
        self.fileID = fileID
        self.relativePath = relativePath
        self.isCodemapRequested = isCodemapRequested
        self.ranges = ranges
        self.cachedFullTokenCount = cachedFullTokenCount
        self.loadedContent = loadedContent
        self.codeMapContent = codeMapContent
        self.availableCodeMapTokenCount = availableCodeMapTokenCount
    }
}

public enum TokenCalculationFileTreeInput {
    case none
    case rendered(String)
    case snapshot(FileTreeSelectionSnapshot)
}

public struct TokenCalculationSnapshot {
    public let promptText: String
    public let selectedInstructionsText: String
    public let duplicateUserInstructionsAtTop: Bool
    public let promptEntries: [PromptFileEntrySnapshot]
    public let fileTree: TokenCalculationFileTreeInput

    public init(
        promptText: String,
        selectedInstructionsText: String,
        duplicateUserInstructionsAtTop: Bool,
        promptEntries: [PromptFileEntrySnapshot],
        fileTree: TokenCalculationFileTreeInput
    ) {
        self.promptText = promptText
        self.selectedInstructionsText = selectedInstructionsText
        self.duplicateUserInstructionsAtTop = duplicateUserInstructionsAtTop
        self.promptEntries = promptEntries
        self.fileTree = fileTree
    }
}
