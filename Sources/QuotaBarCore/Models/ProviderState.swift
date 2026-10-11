import Foundation

/// 화면에 보여줄 프로바이더 한 개의 현재 상태.
public struct ProviderState: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(ProviderError)
    }

    public var status: Status
    /// 마지막으로 성공한 조회 결과. 실패해도 지우지 않고 유지한다.
    public var snapshot: UsageSnapshot?
    public var lastAttemptAt: Date?
    public var consecutiveFailures: Int

    public init(
        status: Status = .idle,
        snapshot: UsageSnapshot? = nil,
        lastAttemptAt: Date? = nil,
        consecutiveFailures: Int = 0
    ) {
        self.status = status
        self.snapshot = snapshot
        self.lastAttemptAt = lastAttemptAt
        self.consecutiveFailures = consecutiveFailures
    }

    public var isLoading: Bool { status == .loading }

    public var error: ProviderError? {
        if case let .failed(error) = status { return error }
        return nil
    }

    /// 최근 조회는 실패했지만 이전 값을 보여주고 있는 상태.
    public var isShowingStaleData: Bool { error != nil && snapshot != nil }
}

/// UI 목록 한 줄.
public struct ProviderRow: Identifiable, Equatable, Sendable {
    public let id: ProviderID
    public let displayName: String
    public let state: ProviderState

    public init(id: ProviderID, displayName: String, state: ProviderState) {
        self.id = id
        self.displayName = displayName
        self.state = state
    }
}
