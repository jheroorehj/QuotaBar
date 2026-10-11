import Foundation

/// 프로바이더 조회 실패 사유. 메시지는 사용자가 바로 조치할 수 있도록 한국어로 안내한다.
public enum ProviderError: Error, Equatable, Sendable {
    /// CLI 설치, 로그인 등 사용자의 조치가 필요하다.
    case setupRequired(String)
    /// 로그인 토큰이 만료되었거나 거부되었다.
    case authExpired(String)
    case rateLimited(retryAfter: Date?)
    case httpStatus(Int, String?)
    case network(String)
    case timeout(TimeInterval)
    /// 응답 형식이 예상과 다르다 (비공식 API 변경 가능성).
    case invalidResponse(String)
    /// 외부 명령 실행이 실패했다.
    case commandFailed(String)
    case cancelled

    /// 사용자가 무언가를 해야 해결되는 오류인지 여부.
    public var requiresUserAction: Bool {
        switch self {
        case .setupRequired, .authExpired: true
        default: false
        }
    }
}

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .setupRequired(message), let .authExpired(message):
            return message
        case let .rateLimited(retryAfter):
            // 서비스의 사용 한도가 아니라 "사용량 조회"를 너무 자주 해서 잠시 막힌 것이다. 헷갈리지 않게 분명히 적는다.
            if let retryAfter {
                return "사용량 조회가 잠시 제한됐습니다 (사용 한도와는 무관). \(UsageFormatting.clockTime(retryAfter)) 이후 다시 시도합니다."
            }
            return "사용량 조회가 잠시 제한됐습니다 (사용 한도와는 무관). 잠시 후 다시 시도합니다."
        case let .httpStatus(code, body):
            if let body, !body.isEmpty {
                return "서버 오류 (HTTP \(code)): \(ProviderError.shorten(body))"
            }
            return "서버 오류 (HTTP \(code))"
        case let .network(message):
            return "네트워크 오류: \(message)"
        case let .timeout(seconds):
            return "응답 시간 초과 (\(Int(seconds))초)"
        case let .invalidResponse(message):
            return "응답 형식을 해석하지 못했습니다: \(message)"
        case let .commandFailed(message):
            return "명령 실행 실패: \(message)"
        case .cancelled:
            return "취소되었습니다."
        }
    }

    static func shorten(_ text: String, limit: Int = 200) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.count > limit ? String(flattened.prefix(limit)) + "…" : flattened
    }

    /// 임의의 오류를 ProviderError 로 정규화한다.
    public static func wrap(_ error: Error) -> ProviderError {
        if let providerError = error as? ProviderError { return providerError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return .cancelled }
            return .network(urlError.localizedDescription)
        }
        if let processError = error as? ProcessRunnerError {
            return .commandFailed(processError.localizedDescription)
        }
        if let rpcError = error as? JSONRPCError {
            return .commandFailed(rpcError.localizedDescription)
        }
        if error is DecodingError {
            return .invalidResponse(String(describing: error))
        }
        return .network(error.localizedDescription)
    }
}
