import Foundation
import RepoPromptContextCore

enum CLIOutputFormat: String {
    case text
    case json
    case streamJson = "stream-json"

    var tokens: [String] {
        ["--output-format", rawValue]
    }
}
