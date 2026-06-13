import Foundation
import RepoPromptC

public extension String {
    @inline(__always)
    func fnv1a64() -> UInt64 {
        withCString { ptr in
            repo_fnv1a64(ptr)
        }
    }
}
