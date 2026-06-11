import Foundation
import RepoPromptContextCore

extension FrozenFileRecord {
    /// Internal convenience initializer from a FileViewModel.
    init(from vm: FileViewModel) {
        self.init(
            name: vm.name,
            relativePath: vm.relativePath,
            fullPath: vm.standardizedFullPath,
            rootFolderPath: vm.standardizedRootFolderPath
        )
    }
}

extension FrozenFolderRecord {
    /// Internal convenience initializer from a FolderViewModel.
    init(from vm: FolderViewModel) {
        self.init(
            name: vm.name,
            relativePath: vm.relativePath,
            fullPath: vm.standardizedFullPath,
            rootPath: vm.rootPath,
            displayName: vm.name
        )
    }
}
