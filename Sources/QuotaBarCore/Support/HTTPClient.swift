import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP 요청 추상화. 테스트에서 가짜 응답을 넣을 수 있게 한다.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // 토큰이 포함된 응답이 디스크 캐시에 남지 않도록 캐시를 끈다.
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("HTTP 응답이 아닙니다.")
        }
        return (data, http)
    }
}

extension HTTPURLResponse {
    /// `Retry-After` 헤더(초 또는 HTTP 날짜)를 Date 로 바꾼다.
    func retryAfterDate(now: Date = Date()) -> Date? {
        guard let raw = value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty
        else { return nil }
        if let seconds = TimeInterval(raw) { return now.addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: raw)
    }
}

/// 상태 코드별 공통 오류 변환.
enum HTTPStatus {
    static func check(_ response: HTTPURLResponse, data: Data, authMessage: String) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw ProviderError.authExpired(authMessage)
        case 429:
            throw ProviderError.rateLimited(retryAfter: response.retryAfterDate())
        default:
            throw ProviderError.httpStatus(response.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}
