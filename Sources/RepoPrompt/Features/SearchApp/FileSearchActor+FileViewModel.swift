import Foundation
import RepoPromptContextCore

extension SearchFileDescriptor {
    init(file: FileViewModel) {
        self.init(
            id: file.id,
            name: file.name,
            relativePath: file.relativePath,
            standardizedRelativePath: file.standardizedRelativePath,
            fullPath: file.fullPath,
            standardizedFullPath: file.standardizedFullPath,
            standardizedRootFolderPath: file.standardizedRootFolderPath,
            fileExtension: file.fileExtension,
            contentSnapshot: { policy in
                await file.searchContentSnapshot(freshnessPolicy: policy)
            }
        )
    }
}

extension FileSearchActor {
    func search(
        pattern: String,
        isRegex: Bool = false,
        wasAutoCorrected: inout Bool?,
        options: SearchOptions = SearchOptions(),
        in files: [FileViewModel]
    ) async throws -> [SearchMatch] {
        try await search(
            pattern: pattern,
            isRegex: isRegex,
            wasAutoCorrected: &wasAutoCorrected,
            options: options,
            in: files.map(SearchFileDescriptor.init(file:))
        )
    }

    func search(
        pattern: String,
        isRegex: Bool = false,
        options: SearchOptions = SearchOptions(),
        in files: [FileViewModel]
    ) async throws -> [SearchMatch] {
        var autoCorrected: Bool? = nil
        return try await search(
            pattern: pattern,
            isRegex: isRegex,
            wasAutoCorrected: &autoCorrected,
            options: options,
            in: files
        )
    }

    func searchPaths(
        pattern: String,
        limit: Int = 100,
        in files: [FileViewModel],
        caseInsensitive: Bool = true,
        isRegex: Bool = false,
        aliasByRootPath: [String: String]? = nil
    ) async throws -> [String] {
        try await searchPaths(
            pattern: pattern,
            limit: limit,
            in: files.map(SearchFileDescriptor.init(file:)),
            caseInsensitive: caseInsensitive,
            isRegex: isRegex,
            aliasByRootPath: aliasByRootPath
        )
    }

    func searchUnified(
        pattern: String,
        isRegex: Bool = false,
        wasAutoCorrected: inout Bool?,
        options: SearchOptions = SearchOptions(),
        in files: [FileViewModel],
        aliasByRootPath: [String: String]? = nil
    ) async throws -> SearchResults {
        try await searchUnified(
            pattern: pattern,
            isRegex: isRegex,
            wasAutoCorrected: &wasAutoCorrected,
            options: options,
            in: files.map(SearchFileDescriptor.init(file:)),
            aliasByRootPath: aliasByRootPath
        )
    }

    func searchUnified(
        pattern: String,
        isRegex: Bool = false,
        options: SearchOptions = SearchOptions(),
        in files: [FileViewModel],
        aliasByRootPath: [String: String]? = nil
    ) async throws -> SearchResults {
        var autoCorrected: Bool? = nil
        return try await searchUnified(
            pattern: pattern,
            isRegex: isRegex,
            wasAutoCorrected: &autoCorrected,
            options: options,
            in: files,
            aliasByRootPath: aliasByRootPath
        )
    }
}
