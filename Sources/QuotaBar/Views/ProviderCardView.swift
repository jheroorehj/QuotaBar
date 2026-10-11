import QuotaBarCore
import SwiftUI

/// 서비스 하나의 유리 타일.
struct ProviderCardView: View {
    let row: ProviderRow
    let now: Date
    /// 이 서비스를 패널에서 숨긴다. 한 번도 연동된 적 없는 서비스의 안내에만 버튼으로 보인다.
    var hide: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: ProviderState { row.state }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            if let snapshot = state.snapshot, !snapshot.windows.isEmpty {
                gauges(snapshot.windows)
            } else if state.error == nil {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("불러오는 중…")
                        .font(.caption.weight(.medium))
                }
                .textHalo()
            }
            if let error = state.error {
                ErrorNote(
                    error: error,
                    lastSuccess: state.snapshot?.fetchedAt,
                    action: SetupAction.resolve(for: row.id, error: error),
                    serviceName: row.displayName,
                    // 연동해서 쓰던 서비스의 로그인이 풀린 경우에는 숨기기를 권하지 않는다.
                    hide: error.requiresUserAction && state.snapshot == nil ? hide : nil
                )
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ServiceBadge(service: row.id.service)
                Text(row.displayName)
                    .font(.headline)
                if let plan = state.snapshot?.plan {
                    Text(plan)
                        .font(.caption.weight(.medium))
                }
            }
            .textHalo()
            Spacer(minLength: Spacing.xs)
            // 처음 불러올 때는 본문에 진행 표시가 있으므로 겹치지 않게 한다.
            if state.isLoading, state.snapshot != nil {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    /// 한도 게이지를 두 칸씩 나란히 놓는다. 하나뿐이면 한 줄을 다 쓴다.
    private func gauges(_ windows: [UsageWindow]) -> some View {
        let pairs = stride(from: 0, to: windows.count, by: 2).map { Array(windows[$0..<min($0 + 2, windows.count)]) }
        return VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(pairs, id: \.first?.id) { pair in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(pair) { window in
                        // 최근 조회가 실패했으면 이전 값임을 회색 게이지와 문구로 알린다.
                        UsageGauge(window: window, now: now, isStale: state.isShowingStaleData, isHalfWidth: pair.count > 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// 한도 하나: 원형 게이지(사용률) + 이름 · 초기화 시각.
struct UsageGauge: View {
    let window: UsageWindow
    let now: Date
    var isStale = false
    /// 한 줄에 게이지 두 개가 나란히 놓여 글자 칸이 좁은지 여부.
    var isHalfWidth = true
    @ScaledMetric(relativeTo: .caption) private var ringSize: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: UsageLevel { UsageLevel(percent: window.usedPercent) }
    private var ringColor: Color { isStale ? .secondary : level.color }

    var body: some View {
        // 초기화 문구는 화면 글자와 손쉬운 사용 값에 같이 쓰므로 한 번만 만든다.
        let caption = caption
        return HStack(alignment: .center, spacing: Spacing.sm) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(window.label)
                    .font(.subheadline.weight(.semibold))
                if let caption {
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textHalo()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.label)
        .accessibilityValue(accessibilityValue(caption: caption))
    }

    private var ring: some View {
        ZStack {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: Metrics.ringLineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    // 유리처럼 뒤가 비치도록 채움 색을 반투명하게 쓴다.
                    .stroke(ringColor.opacity(level.ringFillOpacity), style: StrokeStyle(lineWidth: Metrics.ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: window.usedPercent)
            }
            .textHalo()
            Text(UsageFormatting.percent(window.usedPercent))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isStale ? .secondary : .primary)
                .textHalo()
        }
        .padding(Metrics.ringLineWidth / 2)
        .frame(width: ringSize, height: ringSize)
    }

    private var fraction: CGFloat {
        guard window.usedPercent > 0 else { return 0 }
        // 아주 작은 값도 보이도록 최소 길이를 둔다.
        return max(0.02, CGFloat(min(window.usedPercent, 100) / 100))
    }

    private var caption: String? {
        // 하루 넘게 남으면 "10월 13일 (화) 16:59 초기화" 처럼 길어 좁은 칸에서 어중간하게 줄이 바뀐다.
        // 날짜(요일) 뒤에서 줄을 나눠 "10월 13일 (화)" / "16:59 초기화" 로 보이게 한다.
        // 게이지가 하나뿐이면(Grok) 자리가 넉넉하므로 한 줄로 둔다.
        var reset = UsageFormatting.resetDescription(window.resetsAt, now: now)
        if isHalfWidth {
            reset = reset?.replacingOccurrences(of: ") ", with: ")\n")
        }
        switch (reset, window.detail) {
        case let (reset?, detail?): return "\(detail) · \(reset)"
        case let (reset?, nil): return reset
        case let (nil, detail?): return detail
        case (nil, nil): return nil
        }
    }

    private func accessibilityValue(caption: String?) -> String {
        [
            UsageFormatting.percent(window.usedPercent),
            level.statusText,
            caption?.replacingOccurrences(of: "\n", with: " "),
            isStale ? "이전 값" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

/// 서비스 아이콘. 번들에 아이콘이 없으면(`swift run`) 머리글자 배지로 대체한다.
struct ServiceBadge: View {
    let service: ServiceID
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 22

    var body: some View {
        if let icon = AppIcons.service(service) {
            Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            letterBadge
        }
    }

    private var letterBadge: some View {
        Text(String(service.displayName.prefix(1)))
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(service.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 오류 안내. 명령어(`codex login` 등)를 복사할 수 있도록 텍스트 선택을 허용한다.
struct ErrorNote: View {
    let error: ProviderError
    let lastSuccess: Date?
    /// 터미널에서 바로 해결할 수 있는 조치(로그인·설치). 없으면 안내 문구만 보인다.
    var action: SetupAction?
    var serviceName = ""
    /// 쓰지 않는 서비스라면 패널에서 숨길 수 있게 한다.
    var hide: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: error.requiresUserAction ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(error.localizedDescription)
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let lastSuccess {
                    Text("\(UsageFormatting.clockTime(lastSuccess)) 에 받은 이전 값을 표시 중")
                        .font(.caption2.weight(.medium))
                }
                if action != nil || hide != nil {
                    HStack(spacing: Spacing.sm) {
                        if let action {
                            Button(action.title) {
                                AppActions.runInTerminal(action, serviceName: serviceName)
                            }
                            .help("터미널에서 실행: \(action.command)")
                            .accessibilityLabel("\(serviceName) \(action.title)")
                        }
                        if let hide {
                            Button("숨기기", action: hide)
                                .help("쓰지 않는 서비스를 패널에서 숨깁니다. 설정의 \"표시할 서비스\"에서 다시 켤 수 있습니다.")
                                .accessibilityLabel("\(serviceName) 숨기기")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, Spacing.xs)
                }
            }
        }
        .textHalo()
    }
}
