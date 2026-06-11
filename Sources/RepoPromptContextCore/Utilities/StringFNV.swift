import Foundation
import RepoPromptC

extension String {
    @inline(__always)
    public func fnv1a64() -> UInt64 {
        withCString { ptr in
            repo_fnv1a64(ptr)
        }
    }
}
