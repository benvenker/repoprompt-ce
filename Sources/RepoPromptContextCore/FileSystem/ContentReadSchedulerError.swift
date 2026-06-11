import Foundation

public enum ContentReadSchedulerError: LocalizedError, Equatable {
    case queueFull(retryAfterMilliseconds: Int)

    public var retryAfterMilliseconds: Int {
        switch self {
        case let .queueFull(retryAfterMilliseconds):
            retryAfterMilliseconds
        }
    }

    public var errorDescription: String? {
        switch self {
        case .queueFull:
            "Content-read capacity is temporarily busy and the bounded wait queue is full."
        }
    }
}
