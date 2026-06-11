import Foundation

#if !canImport(Combine)
    public final class AnyCancellable: @unchecked Sendable {
        private let lock = NSLock()
        private var onCancel: (() -> Void)?

        public init(_ onCancel: @escaping () -> Void) {
            self.onCancel = onCancel
        }

        deinit {
            cancel()
        }

        public func cancel() {
            lock.lock()
            let cancel = onCancel
            onCancel = nil
            lock.unlock()
            cancel?()
        }
    }

    public struct AnyPublisher<Output, Failure: Error>: Sendable {
        private let subscribeHandler: @Sendable (@escaping @Sendable (Output) -> Void) -> AnyCancellable

        public init(_ subscribeHandler: @escaping @Sendable (@escaping @Sendable (Output) -> Void) -> AnyCancellable) {
            self.subscribeHandler = subscribeHandler
        }

        public func sink(receiveValue: @escaping @Sendable (Output) -> Void) -> AnyCancellable {
            subscribeHandler(receiveValue)
        }
    }

    public final class PassthroughSubject<Output, Failure: Error>: @unchecked Sendable {
        private let lock = NSLock()
        private var subscribers: [UUID: @Sendable (Output) -> Void] = [:]

        public init() {}

        public func send(_ output: Output) {
            lock.lock()
            let callbacks = Array(subscribers.values)
            lock.unlock()

            for callback in callbacks {
                callback(output)
            }
        }

        public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> {
            AnyPublisher { [weak self] receiveValue in
                guard let self else { return AnyCancellable {} }
                let id = UUID()
                lock.lock()
                subscribers[id] = receiveValue
                lock.unlock()
                return AnyCancellable { [weak self] in
                    self?.removeSubscriber(id)
                }
            }
        }

        private func removeSubscriber(_ id: UUID) {
            lock.lock()
            subscribers.removeValue(forKey: id)
            lock.unlock()
        }
    }
#endif
