import AppKit
import QuotaBarCore
import ServiceManagement

enum AppActions {
    /// 설정 파일(.env)을 텍스트 편집기로 연다. 없으면 템플릿으로 만든다.
    @MainActor
    static func openConfigFile(current: URL?) {
        let url = current ?? ConfigLoader.defaultEnvFileURL()
        do {
            try ConfigLoader.createDefaultEnvFileIfNeeded(at: url)
        } catch {
            NSSound.beep()
            return
        }
        // 숨김 파일(.env)은 기본 연결 앱이 없는 경우가 많아 텍스트 편집기로 직접 연다.
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 설치·로그인 명령을 터미널에서 실행한다.
    ///
    /// 임시 `.command` 파일을 만들어 여는 방식이라 자동화(AppleScript) 권한이 필요 없고,
    /// 터미널이 새로 띄우는 셸이라 앱의 환경 변수(.env 의 API 키 포함)가 넘어가지 않는다.
    @MainActor
    static func runInTerminal(_ action: SetupAction, serviceName: String) {
        let quoted = action.command.shellQuoted
        var lines = [
            "#!/bin/zsh",
            "# QuotaBar 가 만든 임시 스크립트 (\(serviceName) \(action.title))",
            "clear",
            "print -r -- \"QuotaBar · \(serviceName) \(action.title)\"",
            "print -r -- \"  $ \"\(quoted)",
            "print",
        ]
        if let prerequisite = action.prerequisite {
            // 필요한 도구가 없으면 알 수 없는 "command not found" 대신 설치할 곳을 알려 주고 멈춘다.
            lines += [
                "if ! /bin/zsh -lic \("command -v \(prerequisite.tool)".shellQuoted) >/dev/null 2>&1; then",
                "  print -r -- \("`\(prerequisite.tool)` 명령을 찾을 수 없습니다. 먼저 설치하세요:".shellQuoted)",
                "  print -r -- \("  \(prerequisite.installURL)".shellQuoted)",
                "  print -r -- \("설치한 뒤 QuotaBar 에서 다시 \"\(action.title)\" 을 누르세요.".shellQuoted)",
                "  print",
                "  read \"?Enter 를 누르면 끝납니다. \"",
                "  exit 1",
                "fi",
            ]
        }
        if action.kind != .login {
            // 내려받아 설치하는 명령은 한 번 더 확인한다.
            lines.append("read \"?위 명령을 실행하려면 Enter, 취소하려면 Ctrl+C 를 누르세요. \"")
        }
        // 로그인 셸(-l) + 대화형(-i)으로 실행해 사용자의 PATH 설정을 그대로 쓴다.
        lines.append("exec /bin/zsh -lic \(quoted)")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaBar-\(serviceName)-\(action.title.replacingOccurrences(of: " ", with: "-")).command")
        do {
            try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 설정 파일(.env)의 값을 바꾸고 다시 불러온다. 저장하지 못하면 false.
    @MainActor
    @discardableResult
    static func saveSettings(_ changes: [String: String?], controller: QuotaBarController) -> Bool {
        do {
            try ConfigLoader.update(changes, at: controller.config.envFileURL ?? ConfigLoader.defaultEnvFileURL())
        } catch {
            return false
        }
        Task { await controller.reloadConfiguration() }
        return true
    }

    /// 쓰지 않는 서비스를 패널에서 숨긴다. 설정 창의 "표시할 서비스"에서 다시 켤 수 있다.
    @MainActor
    static func hideService(_ service: ServiceID, controller: QuotaBarController) {
        if !saveSettings([QuotaBarConfig.Key.enabled(service): "false"], controller: controller) {
            NSSound.beep()
        }
    }

    @MainActor
    static func quit() {
        NSApp.terminate(nil)
    }
}

extension String {
    /// 셸 명령줄에 한 낱말로 넣을 수 있게 작은따옴표로 감싼다.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// 로그인 시 자동 실행. 앱 번들(QuotaBar.app)로 실행했을 때만 동작한다.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
    }
}
