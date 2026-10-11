import QuotaBarCore
import SwiftUI

/// 설정 창의 내용. 값은 설정 파일(`.env`)에 바로 저장하고 곧바로 다시 불러온다.
///
/// 표준 `Form` 과 시스템 컨트롤만 쓴다 (DESIGN.md: 설정·입력은 읽기 쉬운 표준 표면에).
struct SettingsView: View {
    let controller: QuotaBarController
    let updater: AppUpdater

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var saveFailed = false
    @AppStorage(Preferences.textHaloKey) private var textHaloEnabled = true

    private static let refreshChoices = [1, 5, 10, 15, 30, 60]

    private var config: QuotaBarConfig { controller.config }

    var body: some View {
        Form {
            Section("표시할 서비스") {
                ForEach(ServiceID.allCases, id: \.self) { service in
                    Toggle(service.displayName, isOn: binding(
                        get: { config.isEnabled(service) },
                        key: QuotaBarConfig.Key.enabled(service),
                        value: { $0 ? "true" : "false" }
                    ))
                }
            }

            Section {
                Picker("자동 새로고침 간격", selection: binding(
                    get: { Int(config.refreshInterval / 60) },
                    key: QuotaBarConfig.Key.refreshMinutes,
                    value: { String($0) }
                )) {
                    ForEach(refreshChoices, id: \.self) { minutes in
                        Text(minutes == 60 ? "1시간" : "\(minutes)분").tag(minutes)
                    }
                }
            } header: {
                Text("새로고침")
            } footer: {
                Text("너무 자주 조회하면 서비스 쪽에서 요청을 제한할 수 있습니다.")
            }

            Section {
                Picker("가져오는 곳", selection: binding(
                    get: { config.geminiSource },
                    key: QuotaBarConfig.Key.geminiSource,
                    value: { $0.rawValue }
                )) {
                    Text("자동").tag(GeminiSource.auto)
                    Text("Antigravity (개인 구독)").tag(GeminiSource.antigravity)
                    Text("Gemini CLI (Workspace·교육)").tag(GeminiSource.geminiCLI)
                }
                Toggle("Claude·GPT 모델 한도도 표시", isOn: binding(
                    get: { config.bool(QuotaBarConfig.Key.geminiThirdParty, default: false) },
                    key: QuotaBarConfig.Key.geminiThirdParty,
                    value: { $0 ? "true" : "false" }
                ))
            } header: {
                Text("Gemini")
            } footer: {
                Text("Claude·GPT 모델 한도는 Antigravity 안에서 타사 모델을 쓸 때의 한도입니다.")
            }

            Section("일반") {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                .disabled(!LaunchAtLogin.isAvailable)
                Toggle("글자 또렷하게", isOn: $textHaloEnabled)
                Toggle("새 빌드가 생기면 자동으로 다시 시작", isOn: Binding(
                    get: { updater.isAutomatic },
                    set: { updater.isAutomatic = $0 }
                ))
                .disabled(!updater.isAvailable)
            }

            Section {
                ForEach(Self.executableSettings, id: \.key) { setting in
                    PathSettingRow(setting: setting, value: config.string(setting.key) ?? "", save: save)
                }
            } header: {
                Text("CLI 실행 파일")
            } footer: {
                Text("비워 두면 자동으로 찾습니다. 자동 탐색이 실패할 때만 지정하세요.")
            }

            Section {
                ForEach(Self.directorySettings, id: \.key) { setting in
                    PathSettingRow(setting: setting, value: config.string(setting.key) ?? "", save: save)
                }
            } header: {
                Text("CLI 설정 폴더")
            } footer: {
                Text("각 CLI 가 로그인 정보를 기본 위치가 아닌 곳에 둘 때만 지정하세요. API 키 같은 비밀 값은 이 창에 표시하지 않습니다.")
            }
        }
        .formStyle(.grouped)
        // 내용이 창보다 길 때 스크롤할 수 있다는 것이 보이도록 스크롤 막대를 항상 표시한다.
        .scrollIndicators(.visible)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 320, idealHeight: 640)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .alert("설정을 저장하지 못했습니다", isPresented: $saveFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("설정 파일에 쓸 수 없습니다. 파일 권한을 확인하세요.")
        }
    }

    private var refreshChoices: [Int] {
        // 설정 파일에 목록에 없는 값이 적혀 있어도 선택 표시가 사라지지 않게 한다.
        let current = Int(config.refreshInterval / 60)
        return Self.refreshChoices.contains(current) ? Self.refreshChoices : (Self.refreshChoices + [current]).sorted()
    }

    /// 설정 파일의 값 하나에 연결된 바인딩. 바꾸면 저장하고 다시 불러온다.
    private func binding<Value>(
        get: @escaping () -> Value,
        key: String,
        value: @escaping (Value) -> String
    ) -> Binding<Value> {
        Binding(get: get, set: { save([key: value($0)]) })
    }

    private static let executableSettings: [PathSetting] = [
        PathSetting(title: "Claude", key: QuotaBarConfig.Key.claudeCLIPath, isDirectory: false),
        PathSetting(title: "Codex", key: QuotaBarConfig.Key.codexCLIPath, isDirectory: false),
        PathSetting(title: "Antigravity (agy)", key: QuotaBarConfig.Key.antigravityCLIPath, isDirectory: false),
        PathSetting(title: "Gemini CLI", key: QuotaBarConfig.Key.geminiCLIPath, isDirectory: false),
        PathSetting(title: "Grok", key: QuotaBarConfig.Key.grokCLIPath, isDirectory: false),
    ]

    private static let directorySettings: [PathSetting] = [
        PathSetting(title: "Claude", key: QuotaBarConfig.Key.claudeConfigDir, isDirectory: true),
        PathSetting(title: "Codex", key: QuotaBarConfig.Key.codexHome, isDirectory: true),
        PathSetting(title: "Grok", key: QuotaBarConfig.Key.grokHome, isDirectory: true),
    ]

    private func save(_ changes: [String: String?]) {
        if !AppActions.saveSettings(changes, controller: controller) {
            saveFailed = true
        }
    }
}

/// 경로를 받는 설정 하나 (CLI 실행 파일 또는 설정 폴더).
struct PathSetting {
    let title: String
    let key: String
    let isDirectory: Bool
}

/// 경로 입력 줄: 직접 입력하거나 "선택…"으로 고른다. 입력을 마치면(Return, 다른 칸으로 이동) 저장한다.
private struct PathSettingRow: View {
    let setting: PathSetting
    /// 설정 파일에 저장된 현재 값.
    let value: String
    let save: ([String: String?]) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(setting.title) {
            HStack(spacing: Spacing.sm) {
                TextField(setting.title, text: $text, prompt: Text("자동"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(commit)
                Button("선택…", action: choose)
            }
        }
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != value else { return }
        save([setting.key: trimmed.isEmpty ? nil : trimmed])
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !setting.isDirectory
        panel.canChooseDirectories = setting.isDirectory
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "선택"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text = url.path
        commit()
    }
}
