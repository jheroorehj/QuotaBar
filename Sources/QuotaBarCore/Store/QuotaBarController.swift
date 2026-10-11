import Foundation
import Observation

/// 앱 전체 흐름: 설정 로딩 → 프로바이더 생성 → 시작 시 새로고침 → 10분 자동 갱신.
@MainActor
@Observable
public final class QuotaBarController {
    public let store: UsageStore
    public let scheduler: RefreshScheduler
    public private(set) var config: QuotaBarConfig
    public private(set) var isStarted = false

    @ObservationIgnored private let configLoader: @Sendable () -> QuotaBarConfig
    @ObservationIgnored private let providerFactory: @Sendable (QuotaBarConfig, String?) -> [any UsageProvider]
    @ObservationIgnored private var loginShellPATH: String?
    @ObservationIgnored private let loginShellPATHLoader: @Sendable ([String: String]) async -> String?

    public init(
        configLoader: @escaping @Sendable () -> QuotaBarConfig = { ConfigLoader.load() },
        providerFactory: (@Sendable (QuotaBarConfig, String?) -> [any UsageProvider])? = nil,
        loginShellPATHLoader: @escaping @Sendable ([String: String]) async -> String? = { environment in
            await ExecutableLocator.loginShellPATH(environment: environment)
        }
    ) {
        self.configLoader = configLoader
        self.providerFactory = providerFactory ?? QuotaBarController.defaultProviders
        self.loginShellPATHLoader = loginShellPATHLoader
        let config = configLoader()
        self.config = config
        let store = UsageStore(backoffBase: config.refreshInterval)
        self.store = store
        self.scheduler = RefreshScheduler(interval: config.refreshInterval) {
            await store.refreshAll(trigger: .automatic)
        }
    }

    public nonisolated static func defaultProviders(config: QuotaBarConfig, loginShellPATH: String?) -> [any UsageProvider] {
        let locator = ExecutableLocator.make(config: config, loginShellPATH: loginShellPATH)
        return ProviderRegistry.makeProviders(context: ProviderContext(config: config, locator: locator))
    }

    /// 앱 시작 시 한 번 호출한다.
    public func start() async {
        guard !isStarted else { return }
        isStarted = true
        loginShellPATH = await loginShellPATHLoader(config.processEnvironment)
        store.replaceProviders(providerFactory(config, loginShellPATH))
        scheduler.start()
        await store.refreshAll(trigger: .system)
    }

    /// 새로고침 버튼: 모두 동시에 갱신하고 자동 갱신 타이머를 다시 센다.
    public func refreshNow() async {
        scheduler.reschedule()
        await store.refreshAll(trigger: .manual)
    }

    /// 잠자기 복귀·네트워크 복구 시: 마지막 갱신이 주기보다 오래되었으면 바로 갱신한다.
    public func refreshIfStale() async {
        guard isStarted else { return }
        let last = store.lastRefreshAt ?? .distantPast
        guard Date().timeIntervalSince(last) >= config.refreshInterval else { return }
        scheduler.reschedule()
        await store.refreshAll(trigger: .system)
    }

    /// `.env` 를 다시 읽고 프로바이더를 다시 만든다.
    public func reloadConfiguration() async {
        config = configLoader()
        store.backoffBase = config.refreshInterval
        store.replaceProviders(providerFactory(config, loginShellPATH))
        scheduler.updateInterval(config.refreshInterval)
        await store.refreshAll(trigger: .manual)
    }
}
