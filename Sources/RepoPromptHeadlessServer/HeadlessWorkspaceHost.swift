import Foundation
import MCP
import RepoPromptContextCore

actor HeadlessWorkspaceHost {
    let tabID = UUID()
    let store: WorkspaceFileContextStore
    private let mutationService: WorkspaceSelectionMutationService
    private var selection = StoredSelection()
    private var promptText = ""

    init(rootPaths: [String]) async throws {
        store = WorkspaceFileContextStore()
        mutationService = WorkspaceSelectionMutationService(store: store)
        for root in rootPaths {
            _ = try await store.loadRoot(path: root)
        }
        _ = await store.awaitAppliedIngressForAllRoots()
        _ = await store.warmPathLookupIndexes(rootScope: .allLoaded)
    }

    func dumpSummary() async -> String {
        let diagnostics = await store.catalogDiagnostics(rootScope: .allLoaded)
        let roots = await store.rootRefs(scope: .allLoaded)
        return "roots=\(roots.count) folders=\(diagnostics.folderCount) files=\(diagnostics.fileCount) generation=\(diagnostics.generation)"
    }

    func rootsText() async -> String {
        let roots = await store.rootRefs(scope: .allLoaded)
        return roots.map(\.fullPath).joined(separator: "\n")
    }

    func readFile(path: String, startLine: Int?, limit: Int?) async throws -> String {
        await WorkspaceReadableFileService(store: store).awaitFreshnessForExplicitRequest(path, fallbackScope: .allLoaded)
        guard let handle = await WorkspaceReadableFileService(store: store).resolveReadableFile(path, profile: .mcpRead, rootScope: .allLoaded) else {
            throw HeadlessToolFailure(message: "Unknown or unreadable path: \(path)")
        }
        let fullText: String
        switch handle {
        case let .workspace(file):
            fullText = try await store.readContent(rootID: file.rootID, relativePath: file.standardizedRelativePath, workloadClass: .interactiveRead) ?? ""
        case let .external(file):
            fullText = try await WorkspaceReadableFileService(store: store).readAlwaysReadableExternalFile(file)
        }
        return lineWindow(fullText, startLine: startLine, limit: limit)
    }

    func fileTree(type: String, mode: String, path: String?, maxDepth: Int?) async throws -> String {
        _ = await store.awaitAppliedIngress(rootScope: .allLoaded)
        if type == "roots" { return await rootsText() }
        guard type == "files" else { throw HeadlessToolFailure(message: "invalid type: \(type)") }
        let snapshotMode: WorkspaceFileTreeSnapshotMode = switch mode.lowercased() {
        case "full": .full
        case "folders": .folders
        case "selected": .selected
        case "auto": .auto
        default: throw HeadlessToolFailure(message: "invalid mode: \(mode)")
        }
        let snapshot = await store.makeFileTreeSelectionSnapshot(
            selection: selection,
            request: WorkspaceFileTreeSnapshotRequest(
                mode: snapshotMode,
                filePathDisplay: .relative,
                onlyIncludeRootsWithSelectedFiles: snapshotMode == .selected,
                includeLegend: true,
                rootScope: .allLoaded,
                startPath: path,
                maxDepth: maxDepth
            ),
            profile: .mcpRead
        )
        let tree = CodeMapExtractor.generateFileTree(using: snapshot)
        if tree.isEmpty, path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            throw HeadlessToolFailure(message: "path did not resolve to a loaded folder: \(path ?? "")")
        }
        return tree
    }

    func fileSearch(args: [String: MCP.Value]) async throws -> String {
        guard let pattern = args["pattern"]?.stringValue else { throw HeadlessToolFailure(message: "missing pattern") }
        let mode = SearchMode(rawValue: args["mode"]?.stringValue?.lowercased() ?? "auto") ?? .auto
        let maxResults = max(1, args["max_results"]?.intCoerced() ?? 50)
        let filter = args["filter"]?.objectValue ?? [:]
        let extensions = filter["extensions"]?.stringArray ?? []
        let paths = filter["paths"]?.stringArray
        let exclude = filter["exclude"]?.stringArray ?? []
        let results = try await StoreBackedWorkspaceSearch.search(
            pattern: pattern,
            mode: mode,
            isRegex: args["regex"]?.boolCoerced() ?? false,
            caseInsensitive: args["case_insensitive"]?.boolCoerced() ?? false,
            maxPaths: maxResults,
            maxMatches: maxResults,
            paths: paths,
            includeExtensions: extensions,
            excludePatterns: exclude,
            contextLines: max(0, args["context_lines"]?.intCoerced() ?? 0),
            wholeWord: args["whole_word"]?.boolCoerced() ?? false,
            countOnly: args["count_only"]?.boolCoerced() ?? false,
            rootScope: .allLoaded,
            store: store
        )
        return renderSearchResults(results)
    }

    func codeStructure(paths: [String]?, scope: String, maxResults: Int) async throws -> String {
        _ = await store.awaitAppliedIngress(rootScope: .allLoaded)
        let files: [WorkspaceFileRecord]
        if scope == "selected" {
            let combined = selection.selectedPaths + selection.autoCodemapPaths
            files = await mutationService.resolveSelectionCandidates(paths: combined, rawPaths: combined, expandFolders: true, rootScope: .allLoaded).candidates
        } else {
            guard let paths, !paths.isEmpty else { throw HeadlessToolFailure(message: "missing paths (required when scope='paths')") }
            files = await mutationService.resolveSelectionCandidates(paths: paths, rawPaths: paths, expandFolders: true, rootScope: .allLoaded).candidates
        }
        let limited = Array(files.prefix(max(0, maxResults)))
        let snapshots = await store.codemapSnapshotDictionary()
        let blocks = limited.compactMap { file -> String? in
            guard let api = snapshots[file.id]?.fileAPI else { return nil }
            return api.getFullAPIDescription(displayPath: file.standardizedRelativePath)
        }
        if blocks.isEmpty { return "No code structure available for requested files." }
        return blocks.joined(separator: "\n\n")
    }

    func manageSelection(args: [String: MCP.Value]) async throws -> HeadlessSelectionReply {
        let op = args["op"]?.stringValue?.lowercased() ?? "get"
        let mode = args["mode"]?.stringValue?.lowercased() ?? "full"
        let paths = (args["paths"]?.stringArray ?? []).nonEmptyTrimmed()
        if args["slices"] != nil || mode == "slices" {
            throw HeadlessToolFailure(message: "manage_selection slices are unsupported in rpce-headless v1")
        }
        switch op {
        case "get":
            break
        case "clear":
            selection = StoredSelection()
        case "set":
            let result = await mutationService.buildManageSelectionSet(paths: paths, mode: mode, existing: selection, rootScope: .allLoaded)
            if !result.invalidPaths.isEmpty { throw HeadlessToolFailure(message: "Invalid selection inputs: \(result.invalidPaths.joined(separator: ", "))") }
            selection = result.selection
        case "add":
            guard !paths.isEmpty else { throw HeadlessToolFailure(message: "paths required for add") }
            let result = await mutationService.addPaths(existing: selection, paths: paths, rawPaths: paths, mode: mode, rootScope: .allLoaded)
            if !result.invalidPaths.isEmpty { throw HeadlessToolFailure(message: "Invalid selection inputs: \(result.invalidPaths.joined(separator: ", "))") }
            selection = result.selection
        case "remove":
            guard !paths.isEmpty else { throw HeadlessToolFailure(message: "paths required for remove") }
            let result = await mutationService.removePaths(existing: selection, paths: paths, rawPaths: paths, mode: mode, rootScope: .allLoaded)
            if !result.invalidPaths.isEmpty { throw HeadlessToolFailure(message: "Invalid selection inputs: \(result.invalidPaths.joined(separator: ", "))") }
            selection = result.selection
        case "preview", "promote", "demote":
            throw HeadlessToolFailure(message: "manage_selection op '\(op)' is unsupported in rpce-headless v1")
        default:
            throw HeadlessToolFailure(message: "invalid op: \(op)")
        }
        return selectionReply(mutated: op == "get" ? nil : true)
    }

    func prompt(op: String, text: String?) throws -> String {
        switch op {
        case "get": return promptText
        case "set":
            promptText = text ?? ""
            return promptText
        case "append":
            promptText += text ?? ""
            return promptText
        case "clear":
            promptText = ""
            return promptText
        case "list_presets", "select_preset", "export":
            throw HeadlessToolFailure(message: "prompt op '\(op)' is unsupported in rpce-headless v1")
        default:
            throw HeadlessToolFailure(message: "invalid prompt op: \(op)")
        }
    }

    func workspaceContext(args: [String: MCP.Value]) async throws -> HeadlessWorkspaceContextReply {
        _ = await store.awaitAppliedIngress(rootScope: .allLoaded)
        let include = Set((args["include"]?.stringArray ?? ["prompt", "selection", "tree", "files", "tokens"]).map { $0.lowercased() })
        let cfg = PromptContextResolved(
            includeFiles: include.contains("files"),
            includeUserPrompt: include.contains("prompt"),
            includeMetaPrompts: false,
            includeFileTree: include.contains("tree") || include.contains("selection"),
            fileTreeMode: .auto,
            codeMapUsage: .auto,
            gitInclusion: .none,
            storedPromptIds: nil
        )
        let lookup = WorkspaceLookupContext(rootScope: .allLoaded, bindingProjection: nil)
        let preassembled = await PromptContextPreAssemblyService.resolve(
            PromptContextPreAssemblyRequest(
                cfg: cfg,
                selection: selection,
                store: store,
                lookupContext: lookup,
                filePathDisplay: .relative,
                onlyIncludeRootsWithSelectedFiles: false,
                showCodeMapMarkers: true,
                entryResolutionProfile: .mcpRead,
                selectedGitDiffFolderPolicy: .filesOnly,
                selectedGitDiffProvider: { _ in nil },
                completeGitDiffProvider: { nil }
            )
        )
        let context = await PromptPackagingService.generateClipboardContent(
            metaInstructions: [],
            userInstructions: promptText,
            files: preassembled.entries,
            fileTreeContent: preassembled.fileTreeContent,
            gitDiff: nil,
            includeSavedPrompts: false,
            includeFiles: cfg.includeFiles,
            includeUserPrompt: cfg.includeUserPrompt,
            filePathDisplay: preassembled.filePathDisplay,
            codemapSnapshots: preassembled.codemapSnapshots,
            includeDatetimeInUserInstructions: false,
            promptSectionsOrder: [.fileMap, .fileContents, .userInstructions],
            disabledPromptSections: [],
            duplicateUserInstructionsAtTop: false,
            tabTitle: nil,
            displayPathResolver: { preassembled.displayPath(for: $0) }
        )
        let accounting = await PromptContextAccountingService().calculatePromptStats(
            request: PromptContextAccountingRequest(selection: selection, promptText: promptText, fileTree: preassembled.fileTreeContent.map { .rendered($0) } ?? .none, codeMapUsage: .auto, filePathDisplay: .relative, rootScope: .allLoaded, pathLocateProfile: .mcpRead),
            store: store
        )
        return HeadlessWorkspaceContextReply(
            context: context,
            prompt: promptText,
            selectedFiles: selection.selectedPaths,
            codemapFiles: selection.autoCodemapPaths,
            totalTokens: accounting.tokenResult.totalTokenCount,
            fileTokens: accounting.tokenResult.totalTokenCountFilesOnly,
            fileTreeTokens: accounting.tokenResult.fileTreeTokenCountRaw,
            missingPaths: preassembled.missingPaths,
            invalidPaths: preassembled.invalidPaths
        )
    }

    func contextBuildHarvest() async throws -> HeadlessContextBuildHarvest {
        let reply = try await workspaceContext(args: [:])
        var files: [HeadlessContextBuildHarvest.File] = []
        for path in selection.selectedPaths {
            let tokens: Int
            do {
                tokens = TokenCalculationService.estimateTokens(for: try await readFile(path: path, startLine: nil, limit: nil))
            } catch {
                tokens = 0
            }
            files.append(.init(path: path, tokens: tokens))
        }
        return HeadlessContextBuildHarvest(
            selectedFiles: files,
            codemapFiles: selection.autoCodemapPaths,
            prompt: reply.prompt,
            totalTokens: reply.totalTokens,
            context: reply.context
        )
    }

    private func selectionReply(mutated: Bool?) -> HeadlessSelectionReply {
        HeadlessSelectionReply(
            selectedFiles: selection.selectedPaths,
            codemapFiles: selection.autoCodemapPaths,
            slices: selection.slices.mapValues { ranges in ranges.map { $0.start == $0.end ? "\($0.start)" : "\($0.start)-\($0.end)" } },
            invalidPaths: [],
            mutated: mutated,
            summary: "selected=\(selection.selectedPaths.count) codemap=\(selection.autoCodemapPaths.count) slices=\(selection.slices.count)"
        )
    }

    private func lineWindow(_ text: String, startLine: Int?, limit: Int?) -> String {
        guard let startLine else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if startLine < 0 {
            return lines.suffix(max(0, -startLine)).joined(separator: "\n")
        }
        let start = max(0, startLine - 1)
        guard start < lines.count else { return "" }
        let end = limit.map { min(lines.count, start + max(0, $0)) } ?? lines.count
        return lines[start..<end].joined(separator: "\n")
    }

    private func renderSearchResults(_ results: SearchResults) -> String {
        var lines: [String] = []
        if let warning = results.warningMessage { lines.append("Warning: \(warning)") }
        if let total = results.totalCount { lines.append("Total matches: \(total)") }
        if let searched = results.searchedFileCount { lines.append("Searched files: \(searched)") }
        if let paths = results.paths, !paths.isEmpty {
            lines.append("Path matches:")
            lines.append(contentsOf: paths)
        }
        if let matches = results.matches, !matches.isEmpty {
            lines.append("Content matches:")
            for match in matches {
                if let before = match.contextBefore {
                    for (offset, context) in before.enumerated() {
                        lines.append("\(match.filePath):\(max(1, match.lineNumber - before.count + offset + 1))-\(context)")
                    }
                }
                lines.append("\(match.filePath):\(match.lineNumber + 1):\(match.lineText)")
                if let after = match.contextAfter {
                    for (offset, context) in after.enumerated() {
                        lines.append("\(match.filePath):\(match.lineNumber + offset + 2)-\(context)")
                    }
                }
            }
        }
        if lines.isEmpty { lines.append("No matches") }
        return lines.joined(separator: "\n")
    }
}
