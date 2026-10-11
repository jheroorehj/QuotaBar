import Foundation

/// 한도 하나(예: 5시간 세션, 주간 전체)의 사용률.
public struct UsageWindow: Identifiable, Codable, Equatable, Sendable {
    /// 같은 스냅샷 안에서 고유한 값 (예: "session", "weekly", "weekly.opus").
    public var id: String
    /// 화면에 표시할 이름 (예: "5시간", "주간", "주간 · Opus").
    public var label: String
    /// 사용률 0...100.
    public var usedPercent: Double
    /// 한도가 초기화되는 시각.
    public var resetsAt: Date?
    /// 부가 정보 (예: "$12.50 / $50.00").
    public var detail: String?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date? = nil, detail: String? = nil) {
        self.id = id
        self.label = label
        self.usedPercent = UsageWindow.clamp(usedPercent)
        self.resetsAt = resetsAt
        self.detail = detail
    }

    /// 남은 비율(0...1)로 표현되는 한도를 사용률로 바꾼다.
    public static func fromRemainingFraction(
        id: String,
        label: String,
        remainingFraction: Double,
        resetsAt: Date? = nil,
        detail: String? = nil
    ) -> UsageWindow {
        UsageWindow(id: id, label: label, usedPercent: (1 - remainingFraction) * 100, resetsAt: resetsAt, detail: detail)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }
}

/// API 과금 사용량 (향후 API 프로바이더용).
public struct SpendSummary: Codable, Equatable, Sendable {
    public var label: String
    public var amount: Double
    public var currency: String
    public var limit: Double?

    public init(label: String, amount: Double, currency: String = "USD", limit: Double? = nil) {
        self.label = label
        self.amount = amount
        self.currency = currency
        self.limit = limit
    }
}

/// 프로바이더 한 번 조회 결과.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var providerID: ProviderID
    /// 구독 플랜 이름 (예: "Max 5x", "Plus", "SuperGrok").
    public var plan: String?
    /// 계정 식별 정보 (이메일 등). 화면 표시용.
    public var account: String?
    public var windows: [UsageWindow]
    public var spend: [SpendSummary]
    /// 데이터를 가져온 경로 (예: "OAuth API", "codex app-server"). 문제 진단용.
    public var source: String
    public var fetchedAt: Date

    public init(
        providerID: ProviderID,
        plan: String? = nil,
        account: String? = nil,
        windows: [UsageWindow],
        spend: [SpendSummary] = [],
        source: String,
        fetchedAt: Date = Date()
    ) {
        self.providerID = providerID
        self.plan = plan
        self.account = account
        // 서비스가 주는 순서는 믿을 수 없다 (Claude 는 5시간 한도가 초기화되면 주간을 먼저 준다).
        self.windows = UsageSnapshot.displayOrdered(windows)
        self.spend = spend
        self.source = source
        self.fetchedAt = fetchedAt
    }

    /// 화면에 놓을 순서로 정렬한다: 짧은 기간이 먼저, 주간이 그 뒤.
    ///
    /// 타일은 한 줄에 두 칸이라 이 순서면 5시간이 왼쪽, **주간이 항상 오른쪽**에 온다.
    /// 라벨에 묶음 이름이 있으면(`"주간 · Opus"`) 같은 묶음끼리 모은 뒤 그 안에서 기간 순으로 놓는다.
    static func displayOrdered(_ windows: [UsageWindow]) -> [UsageWindow] {
        var groupOrder: [String: Int] = [:]
        for window in windows {
            let group = groupName(of: window)
            if groupOrder[group] == nil { groupOrder[group] = groupOrder.count }
        }
        return windows.enumerated().sorted { lhs, rhs in
            let left = (groupOrder[groupName(of: lhs.element)] ?? 0, cadenceRank(lhs.element), lhs.offset)
            let right = (groupOrder[groupName(of: rhs.element)] ?? 0, cadenceRank(rhs.element), rhs.offset)
            return left < right
        }.map(\.element)
    }

    private static func groupName(of window: UsageWindow) -> String {
        guard let range = window.label.range(of: " · ") else { return "" }
        return String(window.label[range.upperBound...])
    }

    private static func cadenceRank(_ window: UsageWindow) -> Int {
        let text = "\(window.id) \(window.label)".lowercased()
        if text.contains("5시간") || text.contains("5h") || text.contains("session") || text.contains("five") { return 0 }
        if text.contains("일간") || text.contains("daily") { return 1 }
        if text.contains("주간") || text.contains("week") { return 2 }
        if text.contains("월간") || text.contains("month") { return 3 }
        return 4
    }

    /// 가장 높은 사용률. 메뉴바 아이콘 옆 숫자로 쓴다.
    public var highestUsedPercent: Double? {
        windows.map(\.usedPercent).max()
    }
}
