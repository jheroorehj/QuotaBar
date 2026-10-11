import AppKit

/// 앱이 한 번에 하나만 떠 있도록 한다.
enum SingleInstance {
    static let showPanelNotification = Notification.Name("local.quotabar.QuotaBar.showPanel")

    /// 같은 번들 ID 의 앱이 이미 켜져 있으면 그쪽에 패널을 열라고 알리고 true 를 돌려준다 (호출한 쪽은 바로 끝낸다).
    /// `swift run` 처럼 번들 ID 가 없을 때는 검사하지 않는다.
    static func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            showPanelNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
        return true
    }
}
