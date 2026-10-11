import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Gemini 구독 사용 한도.
///
/// 2026-06-18 부터 개인 계정(무료, Google AI Pro/Ultra)은 Gemini CLI 로그인이 막히고
/// Antigravity CLI(`agy`)로 이전되었다. 그래서 두 경로를 지원한다.
/// - Antigravity: `agy -p /usage --output-format json` (agy 1.1.11+). 5시간/주간 한도.
/// - Gemini CLI : Workspace/교육/Code Assist Standard 계정용 쿼터 API. 모델별 일간 한도.
public struct GeminiSubscriptionProvider: UsageProvider {
    static let antigravityHint =
        "Antigravity CLI(`agy`)를 찾을 수 없습니다. 개인 Google AI Pro/Ultra 구독은 `brew install --cask antigravity-cli` 설치 후 `agy` 로 로그인하세요."
    static let geminiCLIHint = "Gemini CLI 로그인 정보를 찾을 수 없습니다. 터미널에서 `gemini` 를 실행해 Google 계정으로 로그인하세요."
    static let consumerShutdownHint =
        "개인 Google 계정은 2026년 6월부터 Gemini CLI 를 쓸 수 없습니다. Antigravity CLI(`agy`)로 로그인한 뒤 .env 의 QUOTABAR_GEMINI_SOURCE=antigravity 로 바꾸세요."
    static let minimumAgyVersion = (1, 1, 11)

    public let id = ProviderID.subscription(.gemini)
    public let timeout: TimeInterval = 150
    private let context: ProviderContext
    private let tokenCache = GeminiTokenCache()

    /// 테스트에서 키체인 대신 쓸 값. 실제 실행에서는 nil 이고 `/usr/bin/security` 로 읽는다.
    var antigravityKeychainReader: (@Sendable () async -> String?)?

    public init(context: ProviderContext) {
        self.context = context
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        switch context.config.geminiSource {
        case .antigravity:
            return try await fetchFromAntigravity()
        case .geminiCLI:
            return try await fetchFromGeminiCLI()
        case .auto:
            if context.locator.locate("agy") != nil {
                return try await fetchFromAntigravity()
            }
            if context.readFile(geminiDirectory.appendingPathComponent("oauth_creds.json")) != nil {
                return try await fetchFromGeminiCLI()
            }
            throw ProviderError.setupRequired(Self.antigravityHint)
        }
    }

    // MARK: - Antigravity CLI

    private func fetchFromAntigravity() async throws -> UsageSnapshot {
        // 먼저 사용량 API 를 직접 부른다 (1초 안팎). 토큰이 없거나 만료됐거나 거절되면 CLI 로 넘어간다.
        // CLI 는 느리고 가끔 실패하지만, 실행하면 키체인의 토큰을 갱신해 주므로 다음 조회는 다시 직접 경로를 탄다.
        if let snapshot = await fetchFromAntigravityAPI() {
            return snapshot
        }
        let agy = try context.requireExecutable("agy", setupHint: Self.antigravityHint)
        let environment = context.childEnvironment

        // 1.1.11 이전 버전은 `/usage` 를 모델 프롬프트로 보내 쿼터를 쓸 수 있으므로 버전을 먼저 확인한다.
        let versionResult = try await ProcessRunner.run(
            executable: agy, arguments: ["--version"], environment: environment, timeout: 10
        )
        guard let version = Self.parseVersion(versionResult.stdoutString + versionResult.stderrString) else {
            throw ProviderError.commandFailed("agy 버전을 확인할 수 없습니다.")
        }
        guard Self.isAtLeast(version, Self.minimumAgyVersion) else {
            throw ProviderError.setupRequired("agy \(version.0).\(version.1).\(version.2) 은 사용량 조회를 지원하지 않습니다. agy 를 1.1.11 이상으로 업데이트하세요.")
        }

        // 프로젝트 설정이 섞이지 않도록 빈 임시 디렉터리에서 실행한다.
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-agy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        // agy 는 시작할 때 Google 프로필 사진을 받지 못하면 통째로 실패한다
        // (google-antigravity/antigravity-cli#621). 일부 통신망에서 구글 서버 주소 몇 개가 간헐적으로
        // 막혀 3번에 1번꼴로 생기고, 다시 실행하면 대개 성공하므로 시간 여유 안에서 다시 시도한다.
        let deadline = Date().addingTimeInterval(130)
        var result = try await runAntigravityUsage(agy, environment: environment, workDirectory: workDirectory, timeout: 105)
        var attempt = 1
        while attempt < 3,
              Self.isTransientStartupFailure(result.stdoutString + result.stderrString),
              deadline.timeIntervalSinceNow > 20
        {
            attempt += 1
            result = try await runAntigravityUsage(
                agy, environment: environment, workDirectory: workDirectory,
                timeout: min(105, deadline.timeIntervalSinceNow)
            )
        }
        do {
            let windows = try AntigravityUsageReport.parse(
                result.stdout,
                includeThirdParty: context.config.bool(QuotaBarConfig.Key.geminiThirdParty, default: false)
            )
            return UsageSnapshot(
                providerID: id,
                // agy /usage 에는 구독 등급이 없다. 설정에 적어 둔 이름만 보여준다.
                plan: context.config.string(QuotaBarConfig.Key.geminiPlan),
                windows: windows,
                source: "Antigravity CLI",
                fetchedAt: context.now()
            )
        } catch {
            let output = (result.stderrString + " " + result.stdoutString).lowercased()
            if output.contains("login") || output.contains("sign in") || output.contains("unauthenticated") {
                throw ProviderError.setupRequired("Antigravity 로그인이 필요합니다. 터미널에서 `agy` 를 실행해 로그인하세요.")
            }
            throw error
        }
    }

    /// 키체인의 Antigravity 토큰으로 사용량 API 를 직접 호출한다. 어떤 이유로든 안 되면 nil.
    private func fetchFromAntigravityAPI() async -> UsageSnapshot? {
        guard let text = await readAntigravityKeychain(),
              let stored = AntigravityStoredToken.parse(text),
              stored.isUsable(now: context.now())
        else { return nil }

        let quotaRequest = AntigravityQuotaAPI.request(AntigravityQuotaAPI.quotaSummaryURL, token: stored.accessToken)
        guard let (data, response) = try? await context.http.send(quotaRequest),
              response.statusCode == 200,
              let windows = try? AntigravityUsageReport.parseSummary(
                  data,
                  includeThirdParty: context.config.bool(QuotaBarConfig.Key.geminiThirdParty, default: false)
              )
        else { return nil }

        // 구독 이름: 설정에 적은 값이 우선, 없으면 계정의 유료 등급(예: "Google AI Pro" → "AI Pro").
        var plan = context.config.string(QuotaBarConfig.Key.geminiPlan)
        if plan == nil {
            let loadRequest = AntigravityQuotaAPI.request(
                GeminiCodeAssistAPI.loadCodeAssistURL,
                token: stored.accessToken,
                body: #"{"metadata":{"ideType":"IDE_UNSPECIFIED","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}"#
            )
            if let (loadData, loadResponse) = try? await context.http.send(loadRequest),
               loadResponse.statusCode == 200,
               let status = try? GeminiCodeAssistAPI.parseLoadCodeAssist(loadData)
            {
                plan = AntigravityQuotaAPI.shortPlanName(status.plan)
            }
        }
        return UsageSnapshot(
            providerID: id,
            plan: plan,
            windows: windows,
            source: "Antigravity API",
            fetchedAt: context.now()
        )
    }

    private func readAntigravityKeychain() async -> String? {
        if let antigravityKeychainReader {
            return await antigravityKeychainReader()
        }
        #if os(macOS)
        guard context.useSystemKeychain,
              let result = try? await ProcessRunner.run(
                  executable: "/usr/bin/security",
                  arguments: [
                      "find-generic-password",
                      "-s", AntigravityStoredToken.keychainService,
                      "-a", AntigravityStoredToken.keychainAccount,
                      "-w",
                  ],
                  timeout: 10
              ),
              result.exitCode == 0
        else { return nil }
        return result.stdoutString
        #else
        return nil
        #endif
    }

    private func runAntigravityUsage(
        _ agy: String, environment: [String: String], workDirectory: URL, timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: agy,
            arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "90s"],
            environment: environment,
            currentDirectory: workDirectory,
            timeout: timeout
        )
    }

    /// agy 의 시작 점검(프로필 사진 받기)이 네트워크 문제로 실패했는지.
    static func isTransientStartupFailure(_ output: String) -> Bool {
        output.lowercased().contains("eligibility check failed")
    }

    static func parseVersion(_ output: String) -> (Int, Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.(\d+)\.(\d+)"#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output))
        else { return nil }
        let numbers = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: output) else { return nil }
            return Int(output[range])
        }
        guard numbers.count == 3 else { return nil }
        return (numbers[0], numbers[1], numbers[2])
    }

    static func isAtLeast(_ version: (Int, Int, Int), _ minimum: (Int, Int, Int)) -> Bool {
        if version.0 != minimum.0 { return version.0 > minimum.0 }
        if version.1 != minimum.1 { return version.1 > minimum.1 }
        return version.2 >= minimum.2
    }

    // MARK: - Gemini CLI

    var geminiDirectory: URL {
        context.homeDirectory.appendingPathComponent(".gemini", isDirectory: true)
    }

    private func fetchFromGeminiCLI() async throws -> UsageSnapshot {
        try checkAuthType()
        let token = try await accessToken()

        var loadRequest = URLRequest(url: GeminiCodeAssistAPI.loadCodeAssistURL)
        loadRequest.httpMethod = "POST"
        loadRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        loadRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loadRequest.httpBody = Data(#"{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}"#.utf8)
        let (loadData, loadResponse) = try await context.http.send(loadRequest)
        try checkShutdown(loadData, response: loadResponse)
        let status = try GeminiCodeAssistAPI.parseLoadCodeAssist(loadData)

        var quotaRequest = URLRequest(url: GeminiCodeAssistAPI.retrieveQuotaURL)
        quotaRequest.httpMethod = "POST"
        quotaRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        quotaRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: JSONValue = status.projectID.map { ["project": .string($0)] } ?? [:]
        quotaRequest.httpBody = try body.encodedData()
        let (quotaData, quotaResponse) = try await context.http.send(quotaRequest)
        try checkShutdown(quotaData, response: quotaResponse)

        return UsageSnapshot(
            providerID: id,
            plan: status.plan,
            windows: try GeminiCodeAssistAPI.parseQuota(quotaData),
            source: "Gemini CLI OAuth",
            fetchedAt: context.now()
        )
    }

    private func checkShutdown(_ data: Data, response: HTTPURLResponse) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let body = String(decoding: data, as: UTF8.self)
        if GeminiCodeAssistAPI.isConsumerShutdown(body) {
            throw ProviderError.setupRequired(Self.consumerShutdownHint)
        }
        try HTTPStatus.check(response, data: data, authMessage: Self.geminiCLIHint)
    }

    /// API 키·Vertex 로그인은 구독 쿼터가 없으므로 안내한다.
    private func checkAuthType() throws {
        guard let data = context.readFile(geminiDirectory.appendingPathComponent("settings.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let nested = ((root["security"] as? [String: Any])?["auth"] as? [String: Any])?["selectedType"] as? String
        let selected = nested ?? (root["selectedAuthType"] as? String)
        if let selected, selected != "oauth-personal", !selected.isEmpty {
            throw ProviderError.setupRequired("Gemini CLI 가 `\(selected)` 방식으로 로그인되어 있어 구독 쿼터를 조회할 수 없습니다. Google 계정 로그인으로 바꾸세요.")
        }
    }

    private func accessToken() async throws -> String {
        guard let data = context.readFile(geminiDirectory.appendingPathComponent("oauth_creds.json")) else {
            throw ProviderError.setupRequired(Self.geminiCLIHint)
        }
        let credentials = try GeminiOAuthCredentials.parse(data)
        let now = context.now()
        if credentials.isUsable(now: now), let token = credentials.accessToken {
            return token
        }
        if let cached = await tokenCache.token(now: now) {
            return cached
        }
        guard let refreshToken = credentials.refreshToken else {
            throw ProviderError.authExpired(Self.geminiCLIHint)
        }
        guard let client = oauthClient() else {
            throw ProviderError.authExpired("Gemini 토큰이 만료되었습니다. 터미널에서 `gemini` 를 한 번 실행하거나 .env 에 GEMINI_OAUTH_CLIENT_ID/SECRET 을 지정하세요.")
        }

        // 갱신한 토큰은 메모리에만 보관한다. (Gemini CLI 파일은 수정하지 않음)
        var request = URLRequest(url: GeminiCodeAssistAPI.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncoded([
            ("client_id", client.id),
            ("client_secret", client.secret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ]).utf8)
        let (tokenData, tokenResponse) = try await context.http.send(request)
        try checkShutdown(tokenData, response: tokenResponse)
        guard let json = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let token = json["access_token"] as? String
        else {
            throw ProviderError.invalidResponse("토큰 갱신 응답에 access_token 이 없습니다.")
        }
        let expiresIn = (json["expires_in"] as? Double) ?? (json["expires_in"] as? Int).map(Double.init) ?? 3600
        await tokenCache.store(token, expiresAt: now.addingTimeInterval(expiresIn))
        return token
    }

    private func oauthClient() -> (id: String, secret: String)? {
        let config = context.config
        if let id = config.string(QuotaBarConfig.Key.geminiOAuthClientID),
           let secret = config.string(QuotaBarConfig.Key.geminiOAuthClientSecret)
        {
            return (id, secret)
        }
        guard let gemini = context.locator.locate("gemini") else { return nil }
        for candidate in Self.oauthScriptCandidates(forExecutable: gemini) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
                  let size = attributes[.size] as? Int, size < 64 * 1024 * 1024,
                  let contents = try? String(contentsOf: candidate, encoding: .utf8)
            else { continue }
            if let client = GeminiCodeAssistAPI.extractClientCredentials(fromScript: contents) {
                return client
            }
        }
        return nil
    }

    /// 설치된 Gemini CLI 패키지 안에서 OAuth 설정이 들어 있는 스크립트 후보.
    static func oauthScriptCandidates(forExecutable path: String) -> [URL] {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var candidates = [resolved]
        let relativePaths = [
            "node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            "dist/src/code_assist/oauth2.js",
            "lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            "libexec/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
        ]
        var directory = resolved.deletingLastPathComponent()
        for _ in 0..<6 {
            candidates += relativePaths.map { directory.appendingPathComponent($0) }
            directory = directory.deletingLastPathComponent()
        }
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func formEncoded(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }
}

/// 갱신한 Gemini 액세스 토큰을 메모리에 보관한다.
actor GeminiTokenCache {
    private var token: String?
    private var expiresAt: Date?

    func token(now: Date) -> String? {
        guard let token, let expiresAt, expiresAt.addingTimeInterval(-60) > now else { return nil }
        return token
    }

    func store(_ token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }
}
