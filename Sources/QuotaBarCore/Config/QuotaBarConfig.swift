import Foundation

/// Gemini 사용량을 가져올 경로.
public enum GeminiSource: String, CaseIterable, Sendable {
    /// `agy` 가 있으면 Antigravity, 없으면 Gemini CLI.
    case auto
    /// Antigravity CLI(`agy`). 개인 Google AI Pro/Ultra 구독용.
    case antigravity
    /// Gemini CLI OAuth 쿼터 API. Workspace/교육/Code Assist Standard 계정용.
    case geminiCLI = "gemini-cli"
}

/// API(종량제) 사용량 조회에 쓸 키. 값이 있는 서비스만 API 카드가 생긴다.
public struct APICredentials: Equatable, Sendable {
    public var anthropicAdminKey: String?
    public var openAIAdminKey: String?
    public var xaiManagementKey: String?
    public var xaiTeamID: String?

    public init(
        anthropicAdminKey: String? = nil,
        openAIAdminKey: String? = nil,
        xaiManagementKey: String? = nil,
        xaiTeamID: String? = nil
    ) {
        self.anthropicAdminKey = anthropicAdminKey
        self.openAIAdminKey = openAIAdminKey
        self.xaiManagementKey = xaiManagementKey
        self.xaiTeamID = xaiTeamID
    }

    /// 키가 설정된 서비스 목록.
    public var configuredServices: [ServiceID] {
        var services: [ServiceID] = []
        if anthropicAdminKey != nil { services.append(.claude) }
        if openAIAdminKey != nil { services.append(.codex) }
        if xaiManagementKey != nil { services.append(.grok) }
        return services
    }
}

/// `.env` 와 프로세스 환경 변수를 합쳐 만든 설정.
public struct QuotaBarConfig: Sendable {
    public static let defaultRefreshMinutes = 10

    public enum Key {
        public static let envFile = "QUOTABAR_ENV_FILE"
        public static let refreshMinutes = "QUOTABAR_REFRESH_MINUTES"
        public static let geminiSource = "QUOTABAR_GEMINI_SOURCE"
        public static let geminiPlan = "QUOTABAR_GEMINI_PLAN"
        public static let geminiThirdParty = "QUOTABAR_GEMINI_THIRD_PARTY"

        public static func enabled(_ service: ServiceID) -> String {
            "QUOTABAR_\(service.rawValue.uppercased())_ENABLED"
        }

        public static let claudeCLIPath = "CLAUDE_CLI_PATH"
        public static let codexCLIPath = "CODEX_CLI_PATH"
        public static let antigravityCLIPath = "ANTIGRAVITY_CLI_PATH"
        public static let geminiCLIPath = "GEMINI_CLI_PATH"
        public static let grokCLIPath = "GROK_CLI_PATH"

        public static let claudeConfigDir = "CLAUDE_CONFIG_DIR"
        public static let codexHome = "CODEX_HOME"
        public static let grokHome = "GROK_HOME"

        public static let geminiOAuthClientID = "GEMINI_OAUTH_CLIENT_ID"
        public static let geminiOAuthClientSecret = "GEMINI_OAUTH_CLIENT_SECRET"

        public static let anthropicAdminKey = "ANTHROPIC_ADMIN_API_KEY"
        public static let openAIAdminKey = "OPENAI_ADMIN_API_KEY"
        public static let xaiManagementKey = "XAI_MANAGEMENT_API_KEY"
        public static let xaiTeamID = "XAI_TEAM_ID"
    }

    /// 프로세스 환경 변수 위에 `.env` 값을 덮어쓰지 않고 합친 값. (프로세스 환경 변수가 우선)
    public let values: [String: String]
    /// 설정을 읽어 온 `.env` 파일. 없으면 nil.
    public let envFileURL: URL?
    /// 자식 프로세스(CLI)에 넘길 기본 환경 변수. `.env` 의 API 키 등은 포함하지 않는다.
    public let processEnvironment: [String: String]

    public init(values: [String: String], envFileURL: URL? = nil, processEnvironment: [String: String] = [:]) {
        self.values = values
        self.envFileURL = envFileURL
        self.processEnvironment = processEnvironment
    }

    public func string(_ key: String) -> String? {
        guard let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// 경로 값. `~` 를 홈 디렉터리로 펼친다.
    public func path(_ key: String) -> String? {
        string(key).map { ($0 as NSString).expandingTildeInPath }
    }

    public func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = string(key)?.lowercased() else { return defaultValue }
        switch raw {
        case "1", "true", "yes", "on", "y": return true
        case "0", "false", "no", "off", "n": return false
        default: return defaultValue
        }
    }

    public var refreshInterval: TimeInterval {
        let minutes = string(Key.refreshMinutes).flatMap(Double.init) ?? Double(Self.defaultRefreshMinutes)
        // 너무 잦은 조회는 비공식 API 차단 위험이 있으므로 최소 1분.
        return max(1, minutes) * 60
    }

    public func isEnabled(_ service: ServiceID) -> Bool {
        bool(Key.enabled(service), default: true)
    }

    public var geminiSource: GeminiSource {
        string(Key.geminiSource).flatMap { GeminiSource(rawValue: $0.lowercased()) } ?? .auto
    }

    public var apiCredentials: APICredentials {
        APICredentials(
            anthropicAdminKey: string(Key.anthropicAdminKey),
            openAIAdminKey: string(Key.openAIAdminKey),
            xaiManagementKey: string(Key.xaiManagementKey),
            xaiTeamID: string(Key.xaiTeamID)
        )
    }

    /// 자식 프로세스용 환경 변수. 각 CLI 의 홈 디렉터리 설정만 `.env` 에서 전달한다.
    public var childProcessEnvironment: [String: String] {
        var environment = processEnvironment
        for key in [Key.claudeConfigDir, Key.codexHome, Key.grokHome] {
            if let value = path(key) { environment[key] = value }
        }
        return environment
    }
}

/// 설정 파일 위치 결정과 로딩.
public enum ConfigLoader {
    /// 기본 설정 파일: `~/.config/quotabar/.env`
    public static func defaultEnvFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("quotabar", isDirectory: true)
            .appendingPathComponent(".env", isDirectory: false)
    }

    /// 사용할 `.env` 파일을 찾는다.
    /// 우선순위: `QUOTABAR_ENV_FILE` → `~/.config/quotabar/.env` → (개발용) 현재 디렉터리의 `.env`
    public static func resolveEnvFileURL(
        processEnvironment: [String: String],
        homeDirectory: URL,
        currentDirectory: URL?,
        fileExists: (String) -> Bool
    ) -> URL? {
        if let explicit = processEnvironment[QuotaBarConfig.Key.envFile], !explicit.isEmpty {
            let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
            return fileExists(url.path) ? url : nil
        }
        let defaultURL = defaultEnvFileURL(homeDirectory: homeDirectory)
        if fileExists(defaultURL.path) { return defaultURL }
        if let currentDirectory {
            let local = currentDirectory.appendingPathComponent(".env")
            if fileExists(local.path) { return local }
        }
        return nil
    }

    public static func load(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        currentDirectory: URL? = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) -> QuotaBarConfig {
        let envURL = resolveEnvFileURL(
            processEnvironment: processEnvironment,
            homeDirectory: homeDirectory,
            currentDirectory: currentDirectory,
            fileExists: { fileManager.fileExists(atPath: $0) }
        )
        let fileValues = envURL.flatMap { try? EnvFile.load(from: $0) } ?? [:]
        // 셸에서 export 한 값이 `.env` 보다 우선한다. (빈 값은 무시)
        var merged = fileValues
        for (key, value) in processEnvironment where !value.isEmpty {
            merged[key] = value
        }
        return QuotaBarConfig(values: merged, envFileURL: envURL, processEnvironment: processEnvironment)
    }

    /// 설정 파일의 값 몇 개를 바꾼다 (설정 창용). 파일이 없으면 템플릿으로 만든 뒤 바꾼다.
    /// nil 값은 그 설정을 지운다. 다른 줄과 주석은 건드리지 않는다.
    public static func update(
        _ changes: [String: String?],
        at url: URL = defaultEnvFileURL(),
        fileManager: FileManager = .default
    ) throws {
        try createDefaultEnvFileIfNeeded(at: url, fileManager: fileManager)
        var contents = try String(contentsOf: url, encoding: .utf8)
        for key in changes.keys.sorted() {
            contents = EnvFile.updating(contents, key: key, value: changes[key] ?? nil)
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// 설정 파일이 없으면 템플릿으로 만든다. 권한은 600 (본인만 읽기/쓰기).
    @discardableResult
    public static func createDefaultEnvFileIfNeeded(
        at url: URL = defaultEnvFileURL(),
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard !fileManager.fileExists(atPath: url.path) else { return false }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (EnvTemplate.contents + "\n").write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }
}
