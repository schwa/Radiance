import Foundation

@MainActor
final class ClassificationTaskCoordinator {
    private var task: Task<Void, Never>?

    func replace(with operation: @escaping @MainActor @Sendable () async -> Void) {
        cancel()
        task = Task { await operation() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
