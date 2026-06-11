import Foundation

public enum CodeMapExtractor {

    public struct RootInfo: Hashable {
        public let standardizedRootFullPath: String
        public let displayName: String

        public init(standardizedRootFullPath: String, displayName: String) {
            self.standardizedRootFullPath = standardizedRootFullPath
            self.displayName = displayName
        }
    }

    public struct DefinitionBlockResult {
        public let text: String
        public let fileCount: Int

        public init(text: String, fileCount: Int) {
            self.text = text
            self.fileCount = fileCount
        }
    }

    public static func buildLocalDefinitionBlockIfNeeded(
        codeMapUsage: CodeMapUsage,
        selectedFiles: [WorkspaceFileRecord],
        allFileAPIs: [FileAPI],
        filePathDisplay: FilePathDisplay,
        roots: [RootInfo]
    ) -> DefinitionBlockResult {
        guard codeMapUsage != .none else { return DefinitionBlockResult(text: "", fileCount: 0) }
        let selectedAPIs = acceptedFileAPIs(from: selectedFiles, allFileAPIs: allFileAPIs)
        let selectedPaths = Set(selectedFiles.map(\.standardizedFullPath))
        let rootFilteredAPIs = filterAPIsToCurrentRoots(allFileAPIs, roots: roots)
        let unselectedAPIs = rootFilteredAPIs.filter { !selectedPaths.contains(standardizedAPIFilePath($0)) }

        switch codeMapUsage {
        case .none, .selected:
            return DefinitionBlockResult(text: "", fileCount: 0)
        case .complete:
            let text = unselectedAPIs
                .map { $0.getFullAPIDescription(displayPath: displayPath(for: standardizedAPIFilePath($0), filePathDisplay: filePathDisplay, roots: roots)) }
                .joined(separator: "\n\n")
            return DefinitionBlockResult(text: text, fileCount: unselectedAPIs.count)
        case .auto:
            let included = getAutoReferencedAPIs(selectedAPIs: selectedAPIs, unselectedAPIs: unselectedAPIs)
            let text = included
                .map { $0.getFullAPIDescription(displayPath: displayPath(for: standardizedAPIFilePath($0), filePathDisplay: filePathDisplay, roots: roots)) }
                .joined(separator: "\n\n")
            return DefinitionBlockResult(text: text, fileCount: included.count)
        }
    }

    private static func filterAPIsToCurrentRoots(_ apis: [FileAPI], roots: [RootInfo]) -> [FileAPI] {
        guard !apis.isEmpty, !roots.isEmpty else { return [] }
        var seen = Set<String>()
        var filtered: [FileAPI] = []
        filtered.reserveCapacity(apis.count)
        for api in apis {
            let standardized = standardizedAPIFilePath(api)
            guard roots.contains(where: { StandardizedPath.isDescendant(standardized, of: $0.standardizedRootFullPath) }),
                  seen.insert(standardized).inserted
            else { continue }
            filtered.append(api)
        }
        return filtered
    }

    private static func displayPath(for absolutePath: String, filePathDisplay: FilePathDisplay, roots: [RootInfo]) -> String {
        guard filePathDisplay == .relative else { return absolutePath }
        let standardizedAbsolutePath = StandardizedPath.absolute(absolutePath)
        let matching = roots
            .filter { root in
                standardizedAbsolutePath == root.standardizedRootFullPath
                    || standardizedAbsolutePath.hasPrefix(root.standardizedRootFullPath + "/")
            }
            .sorted { $0.standardizedRootFullPath.count > $1.standardizedRootFullPath.count }
        guard let root = matching.first else { return absolutePath }
        let suffix = standardizedAbsolutePath == root.standardizedRootFullPath
            ? ""
            : String(standardizedAbsolutePath.dropFirst(root.standardizedRootFullPath.count + 1))
        return suffix.isEmpty ? root.displayName : "\(root.displayName)/\(suffix)"
    }

    private static func standardizedAPIFilePath(_ api: FileAPI) -> String {
        StandardizedPath.absolute(api.filePath)
    }

    public static func getAutoReferencedAPIs(
        selectedAPIs: [FileAPI],
        unselectedAPIs: [FileAPI]
    ) -> [FileAPI] {
        guard !selectedAPIs.isEmpty else { return [] }

        var typeToFileAPI: [String: FileAPI] = [:]
        for api in unselectedAPIs {
            for type in api.definedTypeNames {
                typeToFileAPI[type] = api
            }
        }

        let referencedTypes = Set(selectedAPIs.flatMap(\.referencedTypes))
        let localRefs = referencedTypes.compactMap { typeToFileAPI[$0] }

        var seen = Set<String>()
        var included: [FileAPI] = []
        for api in localRefs {
            if seen.insert(standardizedAPIFilePath(api)).inserted {
                included.append(api)
            }
        }
        return included
    }

    private static func acceptedFileAPIs(from files: [WorkspaceFileRecord], allFileAPIs: [FileAPI]) -> [FileAPI] {
        guard !files.isEmpty, !allFileAPIs.isEmpty else { return [] }
        let apisByPath = Dictionary(grouping: allFileAPIs, by: { standardizedAPIFilePath($0) })
        return files.compactMap { file in
            apisByPath[file.standardizedFullPath]?.first
        }
    }

    private static func acceptedFileAPIs(
        from files: [WorkspaceFileRecord],
        firstFileAPIByStandardizedNestedPath: [String: FileAPI]
    ) -> [FileAPI] {
        guard !files.isEmpty, !firstFileAPIByStandardizedNestedPath.isEmpty else { return [] }
        return files.compactMap { file in
            firstFileAPIByStandardizedNestedPath[file.standardizedFullPath]
        }
    }

    public static func resolveReferencedFilePaths(
        from selectedFiles: [WorkspaceFileRecord],
        among allFileAPIs: [FileAPI]
    ) -> [String] {
        guard !selectedFiles.isEmpty else { return [] }
        let selectedAPIs = acceptedFileAPIs(from: selectedFiles, allFileAPIs: allFileAPIs)
        return resolveReferencedFilePaths(from: selectedFiles, selectedAPIs: selectedAPIs, among: allFileAPIs)
    }

    public static func resolveReferencedFilePaths(
        from selectedFiles: [WorkspaceFileRecord],
        among allFileAPIs: [FileAPI],
        firstFileAPIByStandardizedNestedPath: [String: FileAPI]
    ) -> [String] {
        guard !selectedFiles.isEmpty else { return [] }
        let selectedAPIs = acceptedFileAPIs(
            from: selectedFiles,
            firstFileAPIByStandardizedNestedPath: firstFileAPIByStandardizedNestedPath
        )
        return resolveReferencedFilePaths(from: selectedFiles, selectedAPIs: selectedAPIs, among: allFileAPIs)
    }

    private static func resolveReferencedFilePaths(
        from selectedFiles: [WorkspaceFileRecord],
        selectedAPIs: [FileAPI],
        among allFileAPIs: [FileAPI]
    ) -> [String] {
        guard !selectedAPIs.isEmpty else { return [] }

        let selectedPaths = Set(selectedFiles.map(\.standardizedFullPath))
        let unselectedAPIs = allFileAPIs.filter { !selectedPaths.contains(standardizedAPIFilePath($0)) }
        let referencedAPIs = getAutoReferencedAPIs(selectedAPIs: selectedAPIs, unselectedAPIs: unselectedAPIs)

        var seen = Set<String>()
        var ordered: [String] = []
        for api in referencedAPIs {
            let standardized = standardizedAPIFilePath(api)
            if seen.insert(standardized).inserted {
                ordered.append(standardized)
            }
        }
        return ordered
    }
}
