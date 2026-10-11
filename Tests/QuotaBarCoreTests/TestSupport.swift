import Foundation
@testable import QuotaBarCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 요청을 기록하고 미리 정한 응답을 돌려주는 HTTP 클라이언트.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    convenience init(status: Int = 200, json: String) {
        self.init { _ in (status, Data(json.utf8)) }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func record(_ request: URLRequest) -> Handler {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let handler = record(request)
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (data, response)
    }
}

/// 테스트마다 쓰고 지우는 임시 디렉터리.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ relativePath: String, _ contents: String) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// 실행 가능한 셸 스크립트를 만든다. (가짜 CLI)
    @discardableResult
    func writeScript(_ name: String, _ body: String) throws -> URL {
        let file = try write("bin/\(name)", "#!/bin/sh\n" + body)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    var binDirectory: String { url.appendingPathComponent("bin").path }
}

/// 고정 시각: 2026-10-08 00:00:00 UTC
let fixedNow = Date(timeIntervalSince1970: 1_791_417_600)

func makeContext(
    home: TemporaryDirectory,
    values: [String: String] = [:],
    http: any HTTPClient = MockHTTPClient(status: 500, json: "{}"),
    now: Date = fixedNow
) -> ProviderContext {
    let config = QuotaBarConfig(values: values, processEnvironment: ["PATH": "/usr/bin:/bin"])
    let locator = ExecutableLocator(searchDirectories: [home.binDirectory, "/usr/bin", "/bin"])
    return ProviderContext(
        config: config,
        http: http,
        locator: locator,
        homeDirectory: home.url,
        useSystemKeychain: false,
        now: { now }
    )
}

func date(_ iso: String) -> Date {
    DateParsing.iso8601(iso)!
}
