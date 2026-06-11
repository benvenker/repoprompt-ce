//
//  PromptAssemblyBuilder.swift
//  RepoPrompt
//
//  Created by Eric Provencher on 2025-04-16.
//

import Foundation

/// All blocks that can appear in the final prompt, in *logical* order.
/// The raw value is persisted in UserDefaults, so never rename casually.
public enum PromptSection: String, CaseIterable, Identifiable, Codable {
    case fileMap, fileContents, metaPrompts, userInstructions, gitDiff

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .fileMap: "File Tree"
        case .fileContents: "File Contents"
        case .gitDiff: "Git Diff"
        case .metaPrompts: "Meta Prompts"
        case .userInstructions: "User Instructions"
        }
    }
}

/// Combines independently‑produced snippets in a caller‑supplied order.
public struct PromptAssemblyBuilder {
    public static let defaultSectionOrder: [PromptSection] = [.fileMap, .fileContents, .gitDiff, .metaPrompts, .userInstructions]

    public let order: [PromptSection]
    public let disabled: Set<PromptSection> // existing switches → pass in
    public let duplicateUserInstructionsAtTop: Bool // new toggle
    public let snippets: [PromptSection: String] // empty / missing → ignored

    public init(order: [PromptSection], disabled: Set<PromptSection>, duplicateUserInstructionsAtTop: Bool, snippets: [PromptSection: String]) {
        self.order = order
        self.disabled = disabled
        self.duplicateUserInstructionsAtTop = duplicateUserInstructionsAtTop
        self.snippets = snippets
    }

    public func build() -> String {
        var out = ""
        // optional first User Instructions block
        if duplicateUserInstructionsAtTop,
           let user = snippets[.userInstructions],
           user.isEmpty == false
        {
            out += user.hasSuffix("\n") ? user : (user + "\n")
        }

        for section in order where !disabled.contains(section) {
            guard let snip = snippets[section], snip.isEmpty == false else { continue }
            out += snip
            if !snip.hasSuffix("\n") { out += "\n" }
        }
        return out
    }

    /// Convenience static wrapper.
    public static func build(
        order: [PromptSection],
        disabled: Set<PromptSection>,
        duplicateUserInstructionsAtTop: Bool,
        snippets: [PromptSection: String]
    ) -> String {
        PromptAssemblyBuilder(
            order: order,
            disabled: disabled,
            duplicateUserInstructionsAtTop: duplicateUserInstructionsAtTop,
            snippets: snippets
        ).build()
    }
}
