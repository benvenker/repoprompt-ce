import Foundation
import RepoPromptContextCore

struct PromptFileEntry {
    let file: FileViewModel
    let isCodemap: Bool
    let ranges: [LineRange]?
}
