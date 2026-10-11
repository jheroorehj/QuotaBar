import AppKit
import QuartzCore
import Observation
import QuotaBarCore
import SwiftUI

/// 메뉴바 아이콘과 그 아래에 뜨는 투명 패널.
///
/// `MenuBarExtra(.window)` 는 시스템이 불투명에 가까운 배경을 깔아 유리 뒤로 바탕화면이 비치지 않는다.
/// 그래서 배경 없는 패널을 직접 띄우고, 내용(SwiftUI)의 유리 조각만 보이게 한다.
///
/// Liquid Glass 는 **앱이 활성 상태일 때만** 뒤가 비치게 그려진다 (비활성이면 뿌연 불투명 판).
/// 그래서 패널을 열 때 앱을 활성화하고, 닫을 때 직전에 쓰던 앱으로 돌려보낸다.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let controller: QuotaBarController
    private let updater: AppUpdater
    private let settings: SettingsWindowController
    private let statusItem: NSStatusItem
    private var panel: FloatingPanel?
    private var lastCloseAt = Date.distantPast
    private var previousApp: NSRunningApplication?
    private let presentation = PanelPresentation()
    /// 닫히는 애니메이션 도중에 다시 열면 예약해 둔 "창 내리기"를 무효로 만든다.
    private var closeGeneration = 0

    var isPanelVisible: Bool { (panel?.isVisible ?? false) && presentation.isShown }

    /// 끊김 측정용: 사람이 누른 것처럼 패널을 닫는다.
    func closePanelForTesting() {
        closePanel()
    }

    func showSettings() {
        settings.show()
    }

    init(controller: QuotaBarController, updater: AppUpdater) {
        self.controller = controller
        self.updater = updater
        settings = SettingsWindowController(controller: controller, updater: updater)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("QuotaBar")
        }
        updateLabel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWillOpen),
            name: SettingsWindowController.willOpenNotification,
            object: nil
        )
    }

    // MARK: - 메뉴바 아이콘

    /// QuotaBar 아이콘만 보여준다 (퍼센트 숫자는 사용자 요청으로 뺌). 사용률은 손쉬운 사용 값으로만 알린다.
    /// 번들에 아이콘이 없으면(`swift run`) 사용률에 따라 바뀌는 게이지 심볼로 대체한다.
    private func updateLabel() {
        let percent = withObservationTracking {
            controller.store.highestUsedPercent
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateLabel() }
        }
        guard let button = statusItem.button else { return }
        button.image = AppIcons.menuBar
            ?? NSImage(systemSymbolName: MenuBarLabel.symbolName(for: percent), accessibilityDescription: nil)
        button.setAccessibilityValue(percent.map { "최대 사용률 \(UsageFormatting.percent($0))" } ?? "사용량 정보 없음")
    }

    // MARK: - 패널

    @objc func cancelPanel() {
        closePanel()
    }

    @objc private func togglePanel() {
        if let panel, panel.isVisible, presentation.isShown {
            closePanel()
            return
        }
        // 아이콘을 눌러 닫은 직후(포커스를 잃어 닫힘) 같은 클릭으로 다시 열리지 않게 한다.
        guard Date().timeIntervalSince(lastCloseAt) > 0.25 else { return }
        showPanel()
    }

    func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let view = panel.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            if size.width > 0, size.height > 0 {
                panel.setContentSize(size)
            }
        }
        positionPanel()
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        NSApp.activate(ignoringOtherApps: true)
        closeGeneration += 1
        // 나타나고 사라지는 페이드는 창의 투명도로 한다. 화면 서버가 처리하므로 SwiftUI 가 화면을 다시 계산하지 않는다.
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        presentation.isShown = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelMotion.openFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // 창이 뜬 다음 프레임에 타일을 펼친다. 닫히던 중이었다면 이미 펼쳐져 있어 그대로 다시 나타난다.
        let generation = closeGeneration
        DispatchQueue.main.async { [presentation] in
            presentation.isUnfolded = true
        }
        // 움직임이 멈춘 뒤에 무거운 장식(글자 둘레 번짐)을 켠다.
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelMotion.openSettleDuration) { [weak self] in
            guard let self, self.closeGeneration == generation else { return }
            self.presentation.isSettled = true
        }
        HitchProbe.startIfRequested("open")
        // 터미널에서 로그인하고 돌아왔을 때 새로고침을 누르지 않아도 반영되게 한다.
        if controller.store.rows.contains(where: { $0.state.error?.requiresUserAction == true }) {
            Task { await controller.refreshNow() }
        }
    }

    /// 패널을 닫는다. 우리가 아직 활성 앱이면(Esc·아이콘 재클릭) 직전 앱으로 포커스를 돌려준다.
    private func closePanel(restoreFocus: Bool = true) {
        guard let panel, panel.isVisible, presentation.isShown else { return }
        lastCloseAt = Date()
        presentation.isShown = false
        HitchProbe.startIfRequested("close")
        closeGeneration += 1
        // 닫을 때는 애니메이션 없이 바로 내린다. 투명 유리 여섯 장을 흐리게 지우는 짧은 페이드조차
        // 프레임이 밀려 끊겨 보였다 (측정: 0.12초 페이드 중 메인 스레드 멈춤 30~50ms 가 한두 번).
        // 시스템 메뉴처럼 즉시 사라지는 쪽이 가장 가볍고, 끊길 틈이 없다.
        panel.orderOut(nil)
        let appToRestore = restoreFocus ? previousApp : nil
        previousApp = nil
        if NSApp.isActive {
            appToRestore?.activate()
        }
        // 다음에 열 때를 위한 상태(접힘, 번짐 꺼짐)는 창이 내려간 뒤에 되돌린다. 보이지 않을 때 바꾸면 끊김이 없다.
        DispatchQueue.main.async { [presentation] in
            presentation.isSettled = false
            presentation.isUnfolded = false
        }
    }

    /// 설정 창이 열릴 때는 패널만 닫고 포커스는 우리 앱에 둔다.
    @objc private func settingsWillOpen() {
        closePanel(restoreFocus: false)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 검은 색유리 위에 흰 글자: 시스템이 라이트 모드여도 패널 안은 항상 어두운 모양으로 그린다.
        panel.appearance = NSAppearance(named: .darkAqua)
        // 그림자는 유리 조각이 직접 그린다. 창 그림자를 켜면 투명 여백까지 윤곽이 생긴다.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.delegate = self

        let hosting = NSHostingController(rootView: PopoverView(controller: controller, updater: updater, presentation: presentation, openSettings: { [settings] in settings.show() }))
        // 내용 높이가 바뀌면(서비스 추가, 오류 문구) 창 크기가 따라간다.
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        return panel
    }

    /// 아이콘 바로 아래, 화면 밖으로 나가지 않게 놓는다.
    private func positionPanel() {
        guard let panel, let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let margin = Metrics.windowMargin
        var x = anchor.midX - size.width / 2
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            // 창의 투명 여백은 화면 밖으로 나가도 된다.
            let inset = Spacing.sm - margin
            x = min(max(x, visible.minX + inset), visible.maxX - size.width - inset)
        }
        let top = anchor.minY - Spacing.xs + margin
        panel.setFrameOrigin(NSPoint(x: x, y: top - size.height))
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        positionPanel()
    }

    func windowDidResignKey(_ notification: Notification) {
        // 설정 메뉴처럼 앱 안의 다른 창으로 포커스가 옮겨 간 경우에는 닫지 않는다.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            guard NSApp.keyWindow == nil else { return }
            self.closePanel()
        }
    }

    /// 다른 앱을 누르면 닫는다.
    @objc private func applicationDidResignActive() {
        closePanel()
    }
}

/// 테두리 없는 창은 기본적으로 키 입력을 받지 못한다. ⌘R·Esc 를 받도록 허용한다.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        // 닫기 처리(포커스 되돌리기)는 컨트롤러가 한다.
        NSApp.sendAction(#selector(StatusItemController.cancelPanel), to: delegate, from: self)
    }
}
