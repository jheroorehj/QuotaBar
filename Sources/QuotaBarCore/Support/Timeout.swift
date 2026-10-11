import Foundation

/// 작업이 `seconds` 안에 끝나지 않으면 취소하고 `ProviderError.timeout` 을 던진다.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            throw ProviderError.timeout(seconds)
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw ProviderError.timeout(seconds) }
        return result
    }
}
