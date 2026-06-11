import Foundation
import RepoPromptContextCore

extension PromptPackagingService {
    /// Build an AIMessage that includes system prompt, meta prompts, file tree/blocks, and conversation.
    static func buildAIMessage(
        systemPrompt: String,
        metaInstructions: [MetaInstruction],
        fileTree: String,
        fileContents: [String],
        gitDiff: String? = nil,
        conversation: [ConversationEntry],
        temperature: Double?,
        promptSectionsOrder: [PromptSection],
        disabledPromptSections: Set<PromptSection>,
        duplicateUserInstructionsAtTop: Bool = false
    ) -> AIMessage {
        let metaPrompts: [String] = metaInstructions.map { meta in
            """
            <meta prompt \"\(meta.title)\">
            \(meta.content)
            </meta prompt>
            """
        }

        var updatedConversation = conversation
        if let lastUserIndex = updatedConversation.lastIndex(where: { $0.role == .user }) {
            let lastUserEntry = updatedConversation[lastUserIndex]
            var newContent = lastUserEntry.content
            if !newContent.contains("<user_instructions>") {
                newContent = """
                <user_instructions>
                \(newContent)
                </user_instructions>
                """
            }
            updatedConversation[lastUserIndex] = ConversationEntry(role: lastUserEntry.role, content: newContent)
        }

        return AIMessage(
            systemPrompt: systemPrompt,
            metaPrompts: metaPrompts,
            fileTree: fileTree,
            fileBlocks: fileContents,
            gitDiff: gitDiff,
            conversationMessages: updatedConversation,
            temperature: temperature,
            promptSectionsOrder: promptSectionsOrder,
            disabledPromptSections: disabledPromptSections,
            duplicateUserInstructionsAtTop: duplicateUserInstructionsAtTop
        )
    }
}
