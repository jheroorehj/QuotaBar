import QuotaBarCore
import SwiftUI

/// 패널이 화면에 나와 있는지. 열고 닫는 애니메이션을 StatusItemController 가 이 값으로 움직인다.
@MainActor
@Observable
final class PanelPresentation {
    var isShown = false
    /// 타일이 제자리로 펼쳐져 있는지. 열 때만 움직이고, 닫을 때는 그대로 둔 채 패널 전체를 흐리게 지운다.
    var isUnfolded = false
    /// 펼치는 움직임이 끝나 가만히 있는 상태. 이때만 글자 둘레 번짐처럼 무거운 장식을 그린다.
    var isSettled = false
}

/// 메뉴바 아이콘을 누르면 열리는 패널. 배경 없이 유리 조각(머리글·버튼·서비스 타일)만 띄운다.
struct PopoverView: View {
    let controller: QuotaBarController
    let updater: AppUpdater
    var presentation = PanelPresentation()
    /// 설정 창을 연다.
    var openSettings: () -> Void = {}
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(Preferences.textHaloKey) private var textHaloEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: UsageStore { controller.store }

    // 이 본문은 `presentation` 의 값을 직접 읽지 않는다. 읽으면 열고 닫을 때마다 패널 전체가 다시 계산되어 끊긴다.
    // 필요한 곳(PanelUnfold, HaloGate)만 따로 읽는다. 나타나고 사라지는 페이드는 창의 투명도로 한다(StatusItemController).
    var body: some View {
        // 타일은 위에서 아래로 한 장씩 차례로 나타나며 살짝 내려앉는다 (PanelUnfold).
        GlassGroup(spacing: Metrics.glassMergeDistance) {
            VStack(spacing: Spacing.sm) {
                header
                    .zIndex(1)
                // 30초마다 "n분 후 초기화" 같은 상대 시간을 다시 계산한다.
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    VStack(spacing: Spacing.sm) {
                        ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                            ProviderCardView(row: row, now: timeline.date, hide: hideAction(for: row))
                                .modifier(unfolding(order: index + 1))
                        }
                        if store.rows.isEmpty {
                            emptyState
                                .modifier(unfolding(order: 1))
                        }
                    }
                }
            }
        }
        .modifier(HaloGate(presentation: presentation))
        .frame(width: Metrics.panelWidth)
        .padding(Metrics.windowMargin)
    }

    /// 구독 서비스 타일만 숨길 수 있다 (설정의 "표시할 서비스"와 같은 값을 바꾼다).
    private func hideAction(for row: ProviderRow) -> (() -> Void)? {
        guard row.id.kind == .subscription else { return nil }
        return { AppActions.hideService(row.id.service, controller: controller) }
    }

    private func unfolding(order: Int) -> PanelUnfold {
        PanelUnfold(presentation: presentation, order: order, reduceMotion: reduceMotion)
    }

    // MARK: - 머리글

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            refreshCapsule
            settingsMenu
        }
    }

    /// 제목 상자 전체가 새로고침 버튼이다. 오른쪽 끝에 새로고침 아이콘(진행 중에는 진행 표시)을 둔다.
    private var refreshCapsule: some View {
        Button {
            Task { await controller.refreshNow() }
        } label: {
            HStack(spacing: Spacing.sm) {
                Text("QuotaBar")
                    .font(.headline)
                Spacer(minLength: Spacing.sm)
                Group {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.medium))
                    }
                }
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            }
            .textHalo()
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonSize)
            // 새로고침하는 동안 이 상자에 액체가 차오른다 (조회가 끝난 서비스의 비율만큼).
            .background {
                LiquidFill(isActive: store.isRefreshing, progress: refreshProgress)
                    .clipShape(Capsule())
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Capsule(), interactive: true)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(store.isRefreshing)
        .help("모두 새로고침 (⌘R)")
        .accessibilityLabel("QuotaBar, 모두 새로고침")
        .accessibilityValue(store.isRefreshing ? "새로고침 중" : "")
    }

    private var settingsMenu: some View {
        Menu {
            Button("설정…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Button("설정 다시 불러오기") {
                Task { await controller.reloadConfiguration() }
            }
            Divider()
            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))
            .disabled(!LaunchAtLogin.isAvailable)
            Toggle("글자 또렷하게", isOn: $textHaloEnabled)
            Divider()
            Button(updater.hasNewBuild ? "새 빌드로 다시 시작" : "다시 시작") {
                updater.relaunch()
            }
            .disabled(!updater.isAvailable)
            Toggle("새 빌드가 생기면 자동으로 다시 시작", isOn: Binding(
                get: { updater.isAutomatic },
                set: { updater.isAutomatic = $0 }
            ))
            .disabled(!updater.isAvailable)
            Divider()
            Button("QuotaBar 종료") {
                AppActions.quit()
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .glassIconButtonLabel()
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .glassIconButtonStyle()
        .fixedSize()
        .help("설정")
        .accessibilityLabel("설정")
    }

    /// 조회가 끝난 서비스의 비율 (0...1).
    private var refreshProgress: Double {
        let rows = store.rows
        guard !rows.isEmpty else { return 1 }
        return Double(rows.filter { !$0.state.isLoading }.count) / Double(rows.count)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("켜진 서비스가 없습니다", systemImage: "switch.2")
        } description: {
            Text("설정에서 표시할 서비스를 켜면 여기에 나타납니다.")
        } actions: {
            Button("설정 열기…") {
                openSettings()
            }
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
        .glassSurface(in: RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
    }
}

/// 패널 열고 닫기의 속도.
enum PanelMotion {
    /// 화면 확인용: `QUOTABAR_SLOW_MOTION=4` 처럼 주면 모든 움직임이 그만큼 느려진다.
    static let slowFactor: Double = {
        ProcessInfo.processInfo.environment["QUOTABAR_SLOW_MOTION"].flatMap(Double.init).map { max(1, $0) } ?? 1
    }()

    /// 펼치는 움직임이 사실상 멈출 때까지의 시간. 이 뒤에 글자 둘레 번짐을 켠다.
    static var openSettleDuration: TimeInterval { 0.9 * slowFactor }

    /// 타일이 내려앉는 거리. 길게 움직일수록 다시 그릴 면적이 커져 끊긴다.
    static let travel: CGFloat = 14

    /// 창이 뜨는 순간(가장 무거운 프레임)과 겹치지 않도록 첫 타일이 출발을 미루는 시간.
    static var firstPieceDelay: TimeInterval { 0.07 * slowFactor }

    /// 타일 사이의 출발 간격. 이만큼씩 늦게 나타나 위에서 아래로 차례로 펼쳐진다.
    static var pieceInterval: TimeInterval { 0.085 * slowFactor }

    /// 패널(창)이 나타나는 페이드 시간. 사라질 때는 애니메이션 없이 바로 내린다.
    static var openFadeDuration: TimeInterval { 0.14 * slowFactor }

    /// 유리 조각 하나가 나타나는 움직임. 위에서 아래로 한 장씩 차례로 나타나며 살짝 내려앉는다.
    /// 한 번에 움직이는 유리가 한두 장뿐이라 프레임 부담이 작다.
    /// 접힐 때(창이 내려간 뒤 다음 열기를 위해 되돌릴 때)는 움직임 없이 바로 바뀐다.
    static func piece(opening: Bool, order: Int) -> Animation? {
        opening
            ? .spring(response: 0.3 * slowFactor, dampingFraction: 1)
                .delay(firstPieceDelay + Double(order - 1) * pieceInterval)
            : nil
    }
}

/// 타일 하나가 차례가 되면 나타나 제자리에 내려앉는 움직임.
private struct PanelUnfold: ViewModifier {
    let presentation: PanelPresentation
    let order: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let isShown = presentation.isUnfolded
        if reduceMotion {
            // 동작 줄이기: 이동·크기 변화 없이 패널 전체의 짧은 페이드만 쓴다.
            content
        } else {
            content
                // 투명도와 짧은 이동만 쓴다. 유리를 눌렀다 펴는 변형은 매 프레임 유리를 다시 계산하게 해서 뺐다.
                .opacity(isShown ? 1 : 0)
                .offset(y: isShown ? 0 : -PanelMotion.travel)
                .animation(PanelMotion.piece(opening: isShown, order: order), value: isShown)
        }
    }
}

/// 패널이 멈춰 있을 때만 글자 둘레 번짐을 허용한다. `presentation` 을 읽는 범위를 이 작은 조각으로 좁힌다.
private struct HaloGate: ViewModifier {
    let presentation: PanelPresentation

    func body(content: Content) -> some View {
        content.environment(\.haloAllowed, presentation.isSettled)
    }
}
