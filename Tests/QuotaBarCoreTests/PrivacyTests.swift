import Foundation
import Testing

/// 배포판이 지켜야 하는 약속: 앱은 각 서비스의 공식 서버 말고는 어디에도 접속하지 않는다.
/// 수집·원격 측정용 주소가 소스에 들어오면 여기서 걸린다.
@Suite struct PrivacyTests {
    /// 접속을 허용하는 곳. 새 서비스를 붙일 때만 늘린다.
    private static let allowedHosts: Set<String> = [
        // 사용량 조회 (사용자 본인의 로그인 정보로, 해당 서비스에만)
        "api.anthropic.com",
        "chatgpt.com",
        "cloudcode-pa.googleapis.com",
        "daily-cloudcode-pa.googleapis.com",
        "oauth2.googleapis.com",
        // 요청을 보내지 않는 문자열: JWT 클레임 이름, 터미널에 보여 주는 설치 안내 주소
        "api.openai.com",
        "claude.com",
        "github.com",
        "brew.sh",
        "x.ai",
    ]

    @Test func sourcesOnlyNameKnownHosts() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let pattern = try NSRegularExpression(pattern: #"https?://([A-Za-z0-9.-]+)"#)

        var checked = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            checked += 1
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let host = try String(text[#require(Range(match.range(at: 1), in: text))])
                #expect(Self.allowedHosts.contains(host), "\(file.lastPathComponent) 에 허용되지 않은 주소: \(host)")
            }
        }
        #expect(checked > 0)
    }
}
