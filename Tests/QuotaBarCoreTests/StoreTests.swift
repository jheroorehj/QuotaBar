import Foundation
import Testing
@testable import QuotaBarCore

/// 정해진 결과를 돌려주는 가짜 프로바이더.
final class StubProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let timeout: TimeInterval
    private let lock = NSLock()
    private var results: [Result<Double, ProviderError>]
    private var delay: TimeInterval
    private var calls = 0

    init(_ service: ServiceID, timeout: TimeInterval = 5, delay: TimeInterval = 0, results: [Result<Double, ProviderError>]) {
        id = .subscription(service)
        self.timeout = timeout
        self.delay = delay
        self.results = results
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let (result, delay): (Result<Double, ProviderError>, TimeInterval) = {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return (results.count > 1 ? results.removeFirst() : results[0], self.delay)
        }()
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let percent = try result.get()
        return UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(id: "session", label: "5시간", usedPercent: percent)],
            source: "stub"
        )
    }
}

@MainActor
@Suite("UsageStore · 갱신")
struct StoreTests {
    @Test func refreshesAllConcurrently() async {
        let providers = [
            StubProvider(.claude, delay: 0.4, results: [.success(40)]),
            StubProvider(.codex, delay: 0.4, results: [.success(80)]),
            StubProvider(.gemini, delay: 0.4, results: [.success(10)]),
            StubProvider(.grok, delay: 0.4, results: [.failure(.setupRequired("grok login"))]),
        ]
        let store = UsageStore(providers: providers)
        let start = Date()
        await store.refreshAll(trigger: .manual)
        // 순서대로 실행했다면 1.6초 이상 걸린다.
        #expect(Date().timeIntervalSince(start) < 1.2)
        #expect(store.highestUsedPercent == 80)
        #expect(store.rows.map(\.displayName) == ["Claude", "Codex", "Gemini", "Grok"])
        #expect(store.rows[3].state.error == .setupRequired("grok login"))
        #expect(store.hasErrors)
        #expect(!store.isRefreshing)
        #expect(store.lastRefreshAt != nil)
    }

    @Test func failureKeepsPreviousSnapshot() async {
        let provider = StubProvider(.claude, results: [.success(30), .failure(.network("offline"))])
        let store = UsageStore(providers: [provider])
        await store.refreshAll(trigger: .manual)
        await store.refreshAll(trigger: .manual)
        let state = store.states[provider.id]!
        #expect(state.error == .network("offline"))
        #expect(state.snapshot?.highestUsedPercent == 30)
        #expect(state.isShowingStaleData)
        #expect(state.consecutiveFailures == 1)
    }

    @Test func slowProviderTimesOutWithoutBlockingOthers() async {
        let slow = StubProvider(.gemini, timeout: 0.3, delay: 5, results: [.success(1)])
        let fast = StubProvider(.claude, results: [.success(50)])
        let store = UsageStore(providers: [fast, slow])
        let start = Date()
        await store.refreshAll(trigger: .manual)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(store.states[slow.id]?.error == .timeout(0.3))
        #expect(store.states[fast.id]?.snapshot?.highestUsedPercent == 50)
    }

    @Test func concurrentRefreshesAreCoalesced() async {
        let provider = StubProvider(.claude, delay: 0.3, results: [.success(10)])
        let store = UsageStore(providers: [provider])
        async let first: Void = store.refreshAll(trigger: .manual)
        async let second: Void = store.refreshAll(trigger: .manual)
        _ = await (first, second)
        #expect(provider.callCount == 1)
    }

    @Test func automaticRefreshBacksOffAfterFailures() async {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let now = LockedDate(clock)
        let provider = StubProvider(.grok, results: [.failure(.network("x"))])
        let store = UsageStore(providers: [provider], backoffBase: 600, now: { now.value })

        await store.refreshAll(trigger: .automatic) // 1회 실패
        clock.addTimeInterval(600); now.value = clock
        await store.refreshAll(trigger: .automatic) // 10분 경과 → 재시도, 2회 실패
        #expect(provider.callCount == 2)

        clock.addTimeInterval(600); now.value = clock
        await store.refreshAll(trigger: .automatic) // 2회 실패 후에는 20분 대기 → 건너뜀
        #expect(provider.callCount == 2)

        await store.refreshAll(trigger: .manual) // 수동 새로고침은 백오프 무시
        #expect(provider.callCount == 3)
    }

    @Test func replacingProvidersKeepsExistingState() async {
        let claude = StubProvider(.claude, results: [.success(20)])
        let store = UsageStore(providers: [claude])
        await store.refreshAll(trigger: .manual)
        store.replaceProviders([StubProvider(.claude, results: [.success(99)]), StubProvider(.codex, results: [.success(1)])])
        #expect(store.states[.subscription(.claude)]?.snapshot?.highestUsedPercent == 20)
        #expect(store.states[.subscription(.codex)]?.snapshot == nil)
        #expect(store.rows.count == 2)
    }

    @Test func schedulerFiresAndReschedules() async throws {
        let counter = LockedCounter()
        let scheduler = RefreshScheduler(interval: 0.2) { counter.increment() }
        scheduler.start()
        try await Task.sleep(nanoseconds: 700_000_000)
        scheduler.stop()
        let fired = counter.value
        // CI 러너가 느릴 수 있으므로 범위를 넉넉히 둔다.
        #expect(fired >= 1 && fired <= 4)
        #expect(scheduler.nextFireDate == nil)

        // reschedule 은 타이머를 처음부터 다시 센다.
        // 리셋하지 않았다면 1.0초에 실행됐겠지만, 0.6초에 리셋했으므로 1.6초 전에는 실행되지 않아야 한다.
        let late = LockedCounter()
        let lateScheduler = RefreshScheduler(interval: 1.0) { late.increment() }
        lateScheduler.start()
        try await Task.sleep(nanoseconds: 600_000_000)
        lateScheduler.reschedule()
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(late.value == 0)
        lateScheduler.stop()
    }

    @Test func controllerStartsAndReloads() async {
        let config = LockedConfig(QuotaBarConfig(values: ["QUOTABAR_REFRESH_MINUTES": "10"]))
        let controller = QuotaBarController(
            configLoader: { config.value },
            providerFactory: { config, _ in
                ServiceID.allCases.filter(config.isEnabled).map { StubProvider($0, results: [.success(5)]) }
            },
            loginShellPATHLoader: { _ in nil }
        )
        await controller.start()
        #expect(controller.store.rows.count == 4)
        #expect(controller.scheduler.isRunning)
        #expect(controller.scheduler.interval == 600)

        config.value = QuotaBarConfig(values: ["QUOTABAR_GROK_ENABLED": "false", "QUOTABAR_REFRESH_MINUTES": "5"])
        await controller.reloadConfiguration()
        #expect(controller.store.rows.map(\.id.service) == [.claude, .codex, .gemini])
        #expect(controller.scheduler.interval == 300)
        controller.scheduler.stop()
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var value: Date {
        get { lock.lock(); defer { lock.unlock() }; return date }
        set { lock.lock(); date = newValue; lock.unlock() }
    }
}

final class LockedConfig: @unchecked Sendable {
    private let lock = NSLock()
    private var config: QuotaBarConfig
    init(_ config: QuotaBarConfig) { self.config = config }
    var value: QuotaBarConfig {
        get { lock.lock(); defer { lock.unlock() }; return config }
        set { lock.lock(); config = newValue; lock.unlock() }
    }
}

@Suite("한도 표시 순서")
struct WindowOrderTests {
    private func snapshot(_ windows: [UsageWindow]) -> UsageSnapshot {
        UsageSnapshot(providerID: .subscription(.claude), windows: windows, source: "test")
    }

    /// Claude 는 5시간 한도가 초기화된 직후 주간을 먼저 준다 (2026-10-08 실제 응답 순서).
    @Test func weeklyAlwaysComesAfterSession() {
        let result = snapshot([
            UsageWindow(id: "weekly", label: "주간", usedPercent: 13),
            UsageWindow(id: "session", label: "5시간", usedPercent: 0),
        ])
        #expect(result.windows.map(\.label) == ["5시간", "주간"])
    }

    @Test func groupsStayTogether() {
        let result = snapshot([
            UsageWindow(id: "gemini-5h", label: "5시간 · Gemini", usedPercent: 0),
            UsageWindow(id: "3p-5h", label: "5시간 · Claude·GPT", usedPercent: 0),
            UsageWindow(id: "gemini-weekly", label: "주간 · Gemini", usedPercent: 0),
            UsageWindow(id: "3p-weekly", label: "주간 · Claude·GPT", usedPercent: 0),
        ])
        #expect(result.windows.map(\.label) == ["5시간 · Gemini", "주간 · Gemini", "5시간 · Claude·GPT", "주간 · Claude·GPT"])
    }

    @Test func extrasGoLast() {
        let result = snapshot([
            UsageWindow(id: "extra", label: "추가 사용량", usedPercent: 5),
            UsageWindow(id: "weekly", label: "주간", usedPercent: 13),
            UsageWindow(id: "session", label: "5시간", usedPercent: 0),
        ])
        #expect(result.windows.map(\.label) == ["5시간", "주간", "추가 사용량"])
    }
}

@Suite("조회 제한 중 새로고침")
struct RateLimitBackoffTests {
    /// 조회 제한(429)에 걸린 동안에는 수동 새로고침도 건너뛰고, 재시도 시각이 지나면 다시 조회한다.
    @Test @MainActor func manualRefreshWaitsForRetryAfter() async {
        let clock = LockedDate(fixedNow)
        let limited = Result<Double, ProviderError>.failure(.rateLimited(retryAfter: fixedNow.addingTimeInterval(300)))
        let provider = StubProvider(.claude, results: [limited, .success(10)])
        let store = UsageStore(providers: [provider], now: { clock.value })
        await store.refreshAll(trigger: .manual)
        #expect(provider.callCount == 1)

        clock.value = fixedNow.addingTimeInterval(120)
        await store.refreshAll(trigger: .manual)
        #expect(provider.callCount == 1)

        clock.value = fixedNow.addingTimeInterval(320)
        await store.refreshAll(trigger: .manual)
        #expect(provider.callCount == 2)
    }

    /// 재시도 시각을 주지 않으면 1분은 쉰다.
    @Test @MainActor func waitsAMinuteWithoutRetryAfter() async {
        let clock = LockedDate(fixedNow)
        let provider = StubProvider(.claude, results: [.failure(.rateLimited(retryAfter: nil)), .success(10)])
        let store = UsageStore(providers: [provider], now: { clock.value })
        await store.refreshAll(trigger: .manual)
        clock.value = fixedNow.addingTimeInterval(30)
        await store.refreshAll(trigger: .manual)
        #expect(provider.callCount == 1)
        clock.value = fixedNow.addingTimeInterval(61)
        await store.refreshAll(trigger: .manual)
        #expect(provider.callCount == 2)
    }
}
