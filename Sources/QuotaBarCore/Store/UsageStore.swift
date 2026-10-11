import Foundation
import Observation

/// 새로고침이 시작된 이유.
public enum RefreshTrigger: Sendable {
    /// 사용자가 새로고침 버튼을 눌렀다. 실패 백오프를 무시한다.
    case manual
    /// 자동 갱신 주기.
    case automatic
    /// 앱 시작, 잠자기 복귀, 네트워크 복구.
    case system
}

/// 모든 프로바이더의 사용량 상태를 보관하고 일괄 새로고침한다.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var providers: [any UsageProvider]
    public private(set) var states: [ProviderID: ProviderState] = [:]
    public private(set) var isRefreshing = false
    public private(set) var lastRefreshAt: Date?

    /// 자동 갱신에서 연속 실패 시 다음 시도까지 기다리는 기본 간격.
    public var backoffBase: TimeInterval
    public var maximumBackoff: TimeInterval = 30 * 60

    @ObservationIgnored private var inFlight: Task<Void, Never>?
    /// 프로바이더 목록이 바뀔 때마다 증가한다. 이전 목록으로 시작한 새로고침 결과는 버린다.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        providers: [any UsageProvider] = [],
        backoffBase: TimeInterval = 10 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.providers = providers
        self.backoffBase = backoffBase
        self.now = now
        for provider in providers {
            states[provider.id] = ProviderState()
        }
    }

    /// 화면에 보여줄 순서대로 정렬된 목록.
    public var rows: [ProviderRow] {
        providers.map { provider in
            ProviderRow(id: provider.id, displayName: provider.displayName, state: states[provider.id] ?? ProviderState())
        }
    }

    /// 모든 프로바이더 중 가장 높은 사용률.
    public var highestUsedPercent: Double? {
        states.values.compactMap { $0.snapshot?.highestUsedPercent }.max()
    }

    public var hasErrors: Bool {
        states.values.contains { $0.error != nil }
    }

    /// 설정이 바뀌었을 때 프로바이더 목록을 교체한다. 같은 프로바이더의 이전 값은 유지한다.
    public func replaceProviders(_ newProviders: [any UsageProvider]) {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        isRefreshing = false
        var newStates: [ProviderID: ProviderState] = [:]
        for provider in newProviders {
            var state = states[provider.id] ?? ProviderState()
            if state.isLoading { state.status = state.snapshot == nil ? .idle : .loaded }
            newStates[provider.id] = state
        }
        providers = newProviders
        states = newStates
    }

    /// 모든 프로바이더를 동시에 새로고침한다.
    /// 이미 진행 중이면 새로 시작하지 않고 진행 중인 작업이 끝나기를 기다린다.
    public func refreshAll(trigger: RefreshTrigger) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.performRefresh(trigger: trigger) }
        inFlight = task
        await task.value
        if inFlight == task { inFlight = nil }
    }

    private func performRefresh(trigger: RefreshTrigger) async {
        let generation = self.generation
        let targets = providers.filter { shouldRefresh($0.id, trigger: trigger) }
        guard !targets.isEmpty else {
            lastRefreshAt = now()
            return
        }
        isRefreshing = true
        for provider in targets {
            states[provider.id, default: ProviderState()].status = .loading
        }

        await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, ProviderError>).self) { group in
            for provider in targets {
                group.addTask {
                    (provider.id, await UsageStore.fetch(provider))
                }
            }
            // 빨리 끝난 프로바이더부터 바로 화면에 반영한다.
            for await (id, result) in group {
                guard generation == self.generation else { continue }
                apply(result, to: id)
            }
        }

        guard generation == self.generation else { return }
        isRefreshing = false
        lastRefreshAt = now()
    }

    nonisolated static func fetch(_ provider: any UsageProvider) async -> Result<UsageSnapshot, ProviderError> {
        do {
            let snapshot = try await withTimeout(seconds: provider.timeout) {
                try await provider.fetchUsage()
            }
            return .success(snapshot)
        } catch {
            return .failure(ProviderError.wrap(error))
        }
    }

    private func apply(_ result: Result<UsageSnapshot, ProviderError>, to id: ProviderID) {
        // 새로고침 도중 설정이 바뀌어 사라진 프로바이더의 결과는 버린다.
        guard providers.contains(where: { $0.id == id }) else { return }
        var state = states[id] ?? ProviderState()
        state.lastAttemptAt = now()
        switch result {
        case let .success(snapshot):
            state.snapshot = snapshot
            state.status = .loaded
            state.consecutiveFailures = 0
        case let .failure(error):
            // 실패해도 직전 값은 유지한다.
            state.status = .failed(error)
            state.consecutiveFailures += 1
        }
        states[id] = state
    }

    /// 자동 갱신에서는 연속 실패한 프로바이더를 지수적으로 덜 자주 조회한다. (최대 30분)
    func shouldRefresh(_ id: ProviderID, trigger: RefreshTrigger) -> Bool {
        // 서비스가 "조회를 잠시 멈추라"고 한 동안에는 수동 새로고침으로도 요청하지 않는다.
        // 계속 두드리면 제한이 길어질 뿐이다. 재시도 시각을 주지 않았으면 1분은 쉰다.
        if let state = states[id], case .rateLimited(let retryAfter) = state.error, let lastAttempt = state.lastAttemptAt {
            let resumeAt = retryAfter ?? lastAttempt.addingTimeInterval(60)
            if now() < resumeAt { return false }
        }
        guard trigger == .automatic,
              let state = states[id],
              state.consecutiveFailures > 0,
              let lastAttempt = state.lastAttemptAt
        else { return true }
        let multiplier = pow(2, Double(min(state.consecutiveFailures, 6) - 1))
        let wait = min(maximumBackoff, backoffBase * multiplier)
        // 타이머 오차로 아슬아슬하게 건너뛰지 않도록 5초 여유를 둔다.
        return now().timeIntervalSince(lastAttempt) >= wait - 5
    }
}
