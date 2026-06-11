import Foundation
import RepoPromptContextCore

public enum GitDiffPublishMode: String, Codable, Sendable {
    case quick
    case standard
    case deep
}
