import Foundation
import Observation

/// 일정 간격으로 작업을 실행한다. 수동 새로고침 시 `reschedule()` 로 타이머를 처음부터 다시 센다.
@MainActor
@Observable
public final class RefreshScheduler {
    public private(set) var interval: TimeInterval
    /// 다음 자동 실행 예정 시각.
    public private(set) var nextFireDate: Date?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let action: @MainActor () async -> Void

    public init(interval: TimeInterval, action: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.action = action
    }

    public var isRunning: Bool { loop != nil }

    public func start() {
        reschedule()
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        nextFireDate = nil
    }

    public func updateInterval(_ newInterval: TimeInterval) {
        interval = newInterval
        if isRunning { reschedule() }
    }

    /// 지금부터 `interval` 뒤로 다음 실행을 다시 잡는다.
    public func reschedule() {
        loop?.cancel()
        let interval = self.interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.nextFireDate = Date().addingTimeInterval(interval)
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.action()
            }
        }
    }
}
