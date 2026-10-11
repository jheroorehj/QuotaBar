import AppKit
import QuotaBarCore
import SwiftUI

/// SwiftUI `App` 장면을 쓰지 않는다. 장면(예: `Settings`)이 있으면 앱을 활성화할 때
/// 시스템이 그 창을 열어 유리 패널 뒤를 가린다. 메뉴바 아이콘과 패널은 StatusItemController 가 만든다.
@main
enum QuotaBarApp {
    @MainActor
    static func main() {
        // 이미 켜져 있으면 하나 더 띄우지 않는다. 번들 사본이 여러 곳(빌드 폴더·응용 프로그램·DMG)에 있으면
        // 시스템이 서로 다른 앱으로 보고 열 때마다 새로 띄우기 때문에 직접 막는다.
        if SingleInstance.handOffToRunningInstance() { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = QuotaBarController()
    private let systemEvents = SystemEventMonitor()
    private var statusItemController: StatusItemController?
    private let updater = AppUpdater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 없이 메뉴바에만 표시한다. (번들 Info.plist 의 LSUIElement 와 같은 효과)
        NSApp.setActivationPolicy(.accessory)
        let statusItemController = StatusItemController(controller: controller, updater: updater)
        self.statusItemController = statusItemController
        updater.isPanelVisible = { [weak statusItemController] in statusItemController?.isPanelVisible ?? false }
        updater.start()
        // 앱을 한 번 더 열면(다른 사본 포함) 새로 띄우는 대신 이미 켜진 쪽이 패널을 연다.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showPanelRequested), name: SingleInstance.showPanelNotification, object: nil
        )
        // 실행하자마자 설정 창을 연다. (화면 확인용)
        if ProcessInfo.processInfo.environment["QUOTABAR_OPEN_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                statusItemController.showSettings()
            }
        }
        // 실행하자마자 패널을 연다. (화면 확인용, 패널을 연 채로 다시 시작했을 때)
        if let value = ProcessInfo.processInfo.environment["QUOTABAR_OPEN_PANEL"] {
            // 값이 숫자면 그만큼(초) 기다렸다가 연다. 첫 조회가 끝난 뒤의 평소 상태를 재현할 때 쓴다.
            let delay = max(1, Double(value) ?? 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                statusItemController.showPanel()
            }
            // 끊김 측정 중이면 닫기와 다시 열기까지 한 번씩 해 본다.
            if HitchProbe.isRequested {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.5) {
                    statusItemController.closePanelForTesting()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 4) {
                    statusItemController.showPanel()
                }
            }
        }

        let controller = self.controller
        systemEvents.start(
            onWake: {
                Task {
                    // 잠자기 복귀 직후에는 네트워크가 아직 연결되지 않았을 수 있다.
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await controller.refreshIfStale()
                }
            },
            onNetworkRestored: {
                Task { await controller.refreshIfStale() }
            }
        )
        Task { await controller.start() }
    }

    /// 같은 사본을 다시 열었을 때 (Finder·Spotlight·Launchpad). 메뉴바 앱이라 창이 없으므로 패널을 보여 준다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanelRequested()
        return false
    }

    @objc private func showPanelRequested() {
        guard let statusItemController, !statusItemController.isPanelVisible else { return }
        statusItemController.showPanel()
    }
}
