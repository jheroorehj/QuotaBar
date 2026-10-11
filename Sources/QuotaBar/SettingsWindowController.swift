import AppKit
import QuotaBarCore
import SwiftUI

/// 설정 창. SwiftUI `Settings` 장면은 쓰지 않는다 (앱을 활성화할 때 저절로 열려 유리 패널 뒤를 가린다).
@MainActor
final class SettingsWindowController {
    /// 설정 창을 열기 전에 유리 패널을 닫으라고 알린다. (포커스는 우리 앱에 그대로 둔다)
    static let willOpenNotification = Notification.Name("QuotaBarSettingsWillOpen")

    private let controller: QuotaBarController
    private let updater: AppUpdater
    private var window: NSWindow?

    init(controller: QuotaBarController, updater: AppUpdater) {
        self.controller = controller
        self.updater = updater
    }

    func show() {
        NotificationCenter.default.post(name: Self.willOpenNotification, object: nil)
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // SwiftUI 가 화면을 구성한 다음에 스크롤 막대 모양을 고정한다.
        DispatchQueue.main.async { [weak window] in
            guard let root = window?.contentView else { return }
            Self.showScrollBars(in: root)
        }
    }

    /// 스크롤 막대를 항상 보이는 모양으로 바꾼다.
    /// 시스템 설정이 "스크롤할 때만 표시"여도 설정 창에서는 아래에 내용이 더 있다는 것이 보여야 한다.
    private static func showScrollBars(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = false
            scrollView.scrollerStyle = .legacy
        }
        for subview in view.subviews {
            showScrollBars(in: subview)
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(controller: controller, updater: updater))
        let window = NSWindow(contentViewController: hosting)
        window.title = "QuotaBar 설정"
        // 크기를 바꿀 수 있고, 내용이 창보다 길면 Form 이 스크롤된다.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 640))
        window.contentMinSize = NSSize(width: 420, height: 320)
        window.setFrameAutosaveName("QuotaBarSettingsWindow")
        window.center()
        return window
    }
}
