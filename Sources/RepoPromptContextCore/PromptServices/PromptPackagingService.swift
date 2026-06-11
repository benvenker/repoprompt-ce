import Foundation

public struct MetaInstruction {
    public let title: String
    public let content: String

    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}

public enum PromptPackagingService {
    /// Returns the opening ``` fence, suffixed with the file extension (\"swift\", \"js\", …).
    @inline(__always)
    public static func codeFenceStart(for fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension // "swift", "m", ""
        return ext.isEmpty ? "```" : "```\(ext)"
    }

    // NEW: Helpers for title snippet
    private static func isGenericTabTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^T\d+$"#, options: .regularExpression) != nil
    }

    private static func escapeXML(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }

    private static func titleSnippet(for tabTitle: String?) -> String? {
        guard let raw = tabTitle?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }
        guard isGenericTabTitle(raw) == false else { return nil }
        let escaped = escapeXML(raw)
        return """
        <title>
        \(escaped)
        </title>

        """
    }

    private enum GitDiffArtifact {
        static let rootFolderName = "_git_data"

        static func isDiffArtifactPath(_ fullPath: String) -> Bool {
            guard fullPath.contains("/\(rootFolderName)/") else { return false }
            let lower = fullPath.lowercased()
            guard lower.hasSuffix(".diff") || lower.hasSuffix(".patch") else { return false }
            return lower.contains("/diff/") || lower.contains("/diffs/")
        }
    }

    /// Produce file contents as an array of strings, each with the file path + raw content
    public static func partitionPromptEntriesForGitDiff(
        _ entries: [ResolvedPromptFileEntry]
    ) -> (diffEntries: [ResolvedPromptFileEntry], codeEntries: [ResolvedPromptFileEntry]) {
        guard !entries.isEmpty else { return ([], []) }
        var diffEntries: [ResolvedPromptFileEntry] = []
        var codeEntries: [ResolvedPromptFileEntry] = []
        diffEntries.reserveCapacity(entries.count)
        codeEntries.reserveCapacity(entries.count)

        for entry in entries {
            if GitDiffArtifact.isDiffArtifactPath(entry.file.fullPath) {
                diffEntries.append(entry)
            } else {
                codeEntries.append(entry)
            }
        }
        return (diffEntries, codeEntries)
    }

    public static func selectedGitDiffText(
        fromDiffEntries diffEntries: [ResolvedPromptFileEntry]
    ) -> String? {
        let rawParts = generateRawFileTexts(diffEntries)
        return rawParts.isEmpty ? nil : rawParts.joined(separator: "\n\n")
    }

    public static func selectedGitDiffText(
        from entries: [ResolvedPromptFileEntry]
    ) -> String? {
        let (diffEntries, _) = partitionPromptEntriesForGitDiff(entries)
        return selectedGitDiffText(fromDiffEntries: diffEntries)
    }

    public static func resolveGitDiff(
        fromDiffEntries diffEntries: [ResolvedPromptFileEntry],
        fallback: @Sendable () async -> String?
    ) async -> String? {
        if let selected = selectedGitDiffText(fromDiffEntries: diffEntries) {
            return selected
        }
        return await fallback()
    }

    public static func resolveGitDiff(
        from entries: [ResolvedPromptFileEntry],
        fallback: @Sendable () async -> String?
    ) async -> String? {
        if let selected = selectedGitDiffText(from: entries) {
            return selected
        }
        return await fallback()
    }

    public static func generateRawFileTexts(
        _ entries: [ResolvedPromptFileEntry]
    ) -> [String] {
        guard !entries.isEmpty else { return [] }
        var blocks: [String] = []
        blocks.reserveCapacity(entries.count)

        for entry in entries {
            guard let content = entry.loadedContent, !content.isEmpty else { continue }
            if let ranges = entry.lineRanges, !ranges.isEmpty {
                let assembly = SliceAssemblyBuilder.build(from: content, ranges: ranges)
                if assembly.isFullFile {
                    blocks.append(assembly.combinedText)
                } else {
                    let text = assembly.segments.map(\.text).joined(separator: "\n")
                    if !text.isEmpty {
                        blocks.append(text)
                    }
                }
            } else {
                blocks.append(content)
            }
        }

        return blocks
    }

    public static func generateFileContents(
        _ files: [ResolvedPromptFileEntry],
        filePathDisplay: FilePathDisplay = .full,
        codemapSnapshots: [UUID: WorkspaceCodemapSnapshot] = [:],
        displayPathResolver: ((ResolvedPromptFileEntry) -> String?)? = nil
    ) -> [String] {
        let (_, contentBlocks) = generatePartitionedFileBlocks(files, filePathDisplay: filePathDisplay, codemapSnapshots: codemapSnapshots, displayPathResolver: displayPathResolver)
        return contentBlocks
    }

    public static func generatePartitionedFileBlocks(
        _ files: [ResolvedPromptFileEntry],
        filePathDisplay: FilePathDisplay,
        codemapSnapshots: [UUID: WorkspaceCodemapSnapshot] = [:],
        displayPathResolver: ((ResolvedPromptFileEntry) -> String?)? = nil
    ) -> (codemapBlocks: [String], contentBlocks: [String]) {
        let (_, codeEntries) = partitionPromptEntriesForGitDiff(files)
        let detailed = generateFileBlocksDetailed(files: codeEntries, filePathDisplay: filePathDisplay, codemapSnapshots: codemapSnapshots, displayPathResolver: displayPathResolver)
        var codemapBlocks: [String] = []
        var contentBlocks: [String] = []

        for record in detailed {
            if record.text.isEmpty { continue }
            if record.isCodemap {
                codemapBlocks.append(record.text)
            } else {
                contentBlocks.append(record.text)
            }
        }

        return (codemapBlocks, contentBlocks)
    }

    public static func generateFileBlocksDetailed(
        files: [ResolvedPromptFileEntry],
        filePathDisplay: FilePathDisplay,
        codemapSnapshots: [UUID: WorkspaceCodemapSnapshot] = [:],
        displayPathResolver: ((ResolvedPromptFileEntry) -> String?)? = nil
    ) -> [ResolvedPromptFileBlockRecord] {
        var blocks: [ResolvedPromptFileBlockRecord] = []
        guard !files.isEmpty else { return blocks }

        let hasMultipleRoots = Set(files.map(\.file.rootID)).count > 1

        for entry in files {
            let file = entry.file
            let selectedPath = displayPathResolver?(entry)
                ?? selectedPath(for: entry, filePathDisplay: filePathDisplay, hasMultipleRoots: hasMultipleRoots)

            if entry.isCodemap {
                if let api = codemapSnapshots[file.id]?.fileAPI {
                    let description = api.getFullAPIDescription(displayPath: selectedPath)
                    blocks.append(ResolvedPromptFileBlockRecord(entry: entry, file: file, text: description, isCodemap: true))
                    continue
                }
            }

            guard let content = entry.loadedContent else { continue }
            let startFence = codeFenceStart(for: file.name)
            let text: String
            if let ranges = entry.lineRanges, !ranges.isEmpty {
                let assembly = SliceAssemblyBuilder.build(from: content, ranges: ranges)
                text = renderFileBlock(selectedPath: selectedPath, startFence: startFence, content: content, assembly: assembly)
            } else {
                text = renderFullFileBlock(selectedPath: selectedPath, startFence: startFence, content: content)
            }
            blocks.append(ResolvedPromptFileBlockRecord(entry: entry, file: file, text: text, isCodemap: false))
        }

        return blocks
    }

    public static func generateClipboardContent(
        metaInstructions: [MetaInstruction],
        userInstructions: String,
        files: [ResolvedPromptFileEntry],
        fileTreeContent: String?,
        gitDiff: String? = nil,
        includeSavedPrompts: Bool,
        includeFiles: Bool,
        includeUserPrompt: Bool,
        filePathDisplay: FilePathDisplay,
        codemapSnapshots: [UUID: WorkspaceCodemapSnapshot] = [:],
        includeDatetimeInUserInstructions: Bool = false,
        promptSectionsOrder: [PromptSection],
        disabledPromptSections: Set<PromptSection>,
        duplicateUserInstructionsAtTop: Bool,
        tabTitle: String? = nil,
        displayPathResolver: ((ResolvedPromptFileEntry) -> String?)? = nil
    ) async -> String {
        var snippets: [PromptSection: String] = [:]

        let (diffEntries, codeEntries) = partitionPromptEntriesForGitDiff(files)
        let (codemapBlocks, contentBlocks) = generatePartitionedFileBlocks(codeEntries, filePathDisplay: filePathDisplay, codemapSnapshots: codemapSnapshots, displayPathResolver: displayPathResolver)

        let codemapJoined = codemapBlocks.joined(separator: "\n\n")
        let hasTree = fileTreeContent != nil && !fileTreeContent!.isEmpty
        let hasCodemaps = !codemapJoined.isEmpty

        if hasTree || hasCodemaps {
            let combinedMap = [fileTreeContent ?? "", codemapJoined]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            snippets[.fileMap] = """
            <file_map>
            \(combinedMap)
            </file_map>

            """
        }

        if includeFiles, !contentBlocks.isEmpty {
            let snippet = """
            <file_contents>
            \(contentBlocks.joined(separator: "\n\n"))
            </file_contents>

            """
            snippets[.fileContents] = snippet
        }

        if includeSavedPrompts, let metaSnippet = buildMetaPromptsSnippet(metaInstructions) {
            snippets[.metaPrompts] = metaSnippet
        }

        let effectiveGitDiff = await resolveGitDiff(
            fromDiffEntries: diffEntries
        ) {
            gitDiff
        }

        if let diff = effectiveGitDiff, !diff.isEmpty {
            let snippet = """
            <git_diff>
            \(diff)
            </git_diff>

            """
            snippets[.gitDiff] = snippet
        }

        if includeUserPrompt, !userInstructions.isEmpty {
            var snippet = ""
            if includeDatetimeInUserInstructions {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                let dateString = dateFormatter.string(from: Date())
                snippet += """
                <user_instructions date="\(dateString)">
                \(userInstructions)
                </user_instructions>

                """
            } else {
                snippet += """
                <user_instructions>
                \(userInstructions)
                </user_instructions>

                """
            }
            snippets[.userInstructions] = snippet
        }

        let clipboardContent = PromptAssemblyBuilder.build(
            order: promptSectionsOrder,
            disabled: disabledPromptSections,
            duplicateUserInstructionsAtTop: duplicateUserInstructionsAtTop,
            snippets: snippets
        )

        let prefix = Self.titleSnippet(for: tabTitle) ?? ""
        return prefix + clipboardContent
    }

    private static func selectedPath(
        for entry: ResolvedPromptFileEntry,
        filePathDisplay: FilePathDisplay,
        hasMultipleRoots: Bool
    ) -> String {
        if filePathDisplay == .relative {
            if hasMultipleRoots,
               let rootFolderPath = entry.rootFolderPath,
               !rootFolderPath.isEmpty
            {
                let rootFolderName = (StandardizedPath.absolute(rootFolderPath) as NSString).lastPathComponent
                return rootFolderName.isEmpty ? entry.file.relativePath : "\(rootFolderName)/\(entry.file.relativePath)"
            }
            return entry.file.relativePath
        }
        return entry.file.fullPath
    }

    private static func renderFullFileBlock(selectedPath: String, startFence: String, content: String) -> String {
        let endFence = "```"
        return """
        File: \(selectedPath)
        \(startFence)
        \(content)
        \(endFence)
        """
    }

    private static func renderSliceFileBlock(selectedPath: String, startFence: String, segments: [WorkspaceSliceSegment]) -> String {
        let endFence = "```"
        var sliceLines = ["File: \(selectedPath)"]
        for (index, segment) in segments.enumerated() {
            let label = formatRange(segment.range)
            if let desc = segment.range.description, !desc.isEmpty {
                sliceLines.append("(lines \(label): \(desc))")
            } else {
                sliceLines.append("(lines \(label))")
            }
            sliceLines.append(startFence)
            sliceLines.append(segment.text)
            sliceLines.append(endFence)
            if index != segments.count - 1 {
                sliceLines.append("")
            }
        }
        return sliceLines.joined(separator: "\n")
    }

    private static func renderFileBlock(
        selectedPath: String,
        startFence: String,
        content: String,
        assembly: WorkspaceSliceAssembly
    ) -> String {
        if assembly.isFullFile {
            return renderFullFileBlock(selectedPath: selectedPath, startFence: startFence, content: assembly.combinedText)
        }
        return renderSliceFileBlock(selectedPath: selectedPath, startFence: startFence, segments: assembly.segments)
    }

    private static func escapeString(_ input: String) -> String {
        input
    }

    private static func formatRange(_ range: LineRange) -> String {
        range.start == range.end ? "\(range.start)" : "\(range.start)-\(range.end)"
    }

    // MARK: - Shared builder for <meta prompt> blocks

    /// Builds a formatted string containing all meta prompts in XML format
    /// Returns nil if the meta instructions array is empty
    public static func buildMetaPromptsSnippet(_ metas: [MetaInstruction]) -> String? {
        guard !metas.isEmpty else { return nil }
        var snippet = ""
        for (index, meta) in metas.enumerated() {
            snippet += """
            <meta prompt \(index + 1) = "\(meta.title)">
            \(meta.content)
            </meta prompt \(index + 1)>

            """
        }
        return snippet
    }
}
