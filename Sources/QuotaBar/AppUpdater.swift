import AppKit
import Observation

/// 실행 중인 앱 번들이 새로 빌드되면(`scripts/build-app.sh`) 알아채고 다시 시작한다.
///
/// 배포 서버에서 내려받는 업데이트가 아니라, **디스크의 앱이 지금 실행 중인 것보다 새것인지**만 본다.
/// 자동(새 빌드가 생기면 바로 다시 시작)과 수동(설정 메뉴의 "다시 시작") 둘 다 지원한다.
@MainActor
@Observable
final class AppUpdater {
    private static let automaticKey = "relaunchAutomaticallyOnNewBuild"

    /// 디스크의 앱이 실행 중인 것과 달라졌다. 자동이 꺼져 있으면 메뉴에 표시만 한다.
    private(set) var hasNewBuild = false

    /// 새 빌드가 생기면 자동으로 다시 시작할지 여부. 기본은 켬.
    var isAutomatic: Bool {
        didSet {
            UserDefaults.standard.set(isAutomatic, forKey: Self.automaticKey)
            if isAutomatic, hasNewBuild { relaunch() }
        }
    }

    /// 다시 시작한 뒤에도 패널을 열어 둘지 판단하는 데 쓴다.
    @ObservationIgnored var isPanelVisible: () -> Bool = { false }

    @ObservationIgnored private let bundleURL = Bundle.main.bundleURL
    @ObservationIgnored private let executableURL = Bundle.main.executableURL
    @ObservationIgnored private var launchedStamp: Date?
    @ObservationIgnored private var candidateStamp: Date?
    @ObservationIgnored private var timer: Timer?

    /// `.app` 번들로 실행했을 때만 동작한다. (`swift run` 은 다시 열 번들이 없다)
    var isAvailable: Bool { bundleURL.pathExtension == "app" && executableURL != nil }

    init() {
        isAutomatic = UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    func start() {
        guard isAvailable, timer == nil else { return }
        launchedStamp = executableStamp()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        // 정확한 시각이 필요 없다. 허용 오차를 주면 시스템이 다른 타이머와 묶어 깨워 전력을 덜 쓴다.
        timer.tolerance = 1
        self.timer = timer
    }

    private func check() {
        // 빌드 중에는 번들이 지워졌다가 다시 만들어진다. 실행 파일이 없으면 기다린다.
        guard let stamp = executableStamp(), stamp != launchedStamp else {
            candidateStamp = nil
            return
        }
        // 두 번 연속 같은 시각이고 서명까지 끝난 뒤에만 새 빌드로 본다 (복사·서명 도중에 다시 열지 않도록).
        guard stamp == candidateStamp, isSigned(after: stamp) else {
            candidateStamp = stamp
            return
        }
        hasNewBuild = true
        if isAutomatic { relaunch() }
    }

    /// 지금 앱을 끄고 디스크의 앱을 다시 연다.
    func relaunch() {
        guard isAvailable else { return }
        timer?.invalidate()
        // 이 프로세스가 끝나기를 기다렸다가 번들을 다시 연다. 패널이 열려 있었으면 열린 채로 시작한다.
        let openPanel = isPanelVisible() ? "--env QUOTABAR_OPEN_PANEL=1 " : ""
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done
        exec /usr/bin/open \(openPanel)\(bundleURL.path.shellQuoted)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            NSSound.beep()
            return
        }
        NSApp.terminate(nil)
    }

    private func executableStamp() -> Date? {
        guard let path = executableURL?.path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func isSigned(after stamp: Date) -> Bool {
        let seal = bundleURL.appendingPathComponent("Contents/_CodeSignature/CodeResources").path
        guard let signed = (try? FileManager.default.attributesOfItem(atPath: seal))?[.modificationDate] as? Date else {
            return false
        }
        // codesign 은 서명 목록을 쓴 뒤 실행 파일에 서명을 넣으므로 실행 파일 시각이 조금 더 늦다.
        return signed >= stamp.addingTimeInterval(-30)
    }
}
