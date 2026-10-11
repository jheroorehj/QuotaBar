import Foundation

/// QuotaBar 가 다루는 AI 서비스.
public enum ServiceID: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    case gemini
    case grok

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .grok: "Grok"
        }
    }

    /// API 사용량 카드에 쓰는 이름. Codex 의 API 는 OpenAI API 로 과금된다.
    public var apiDisplayName: String {
        switch self {
        case .claude: "Claude API"
        case .codex: "OpenAI API"
        case .gemini: "Gemini API"
        case .grok: "xAI API"
        }
    }
}

/// 사용량의 종류. 구독(정액제) 한도와 API(종량제) 과금은 데이터 소스가 완전히 다르다.
public enum UsageKind: String, Codable, Sendable {
    case subscription
    case api
}

/// 프로바이더 식별자. 같은 서비스라도 구독/API 를 별도 카드로 보여준다.
public struct ProviderID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let service: ServiceID
    public let kind: UsageKind

    public init(service: ServiceID, kind: UsageKind) {
        self.service = service
        self.kind = kind
    }

    public static func subscription(_ service: ServiceID) -> ProviderID {
        ProviderID(service: service, kind: .subscription)
    }

    public static func api(_ service: ServiceID) -> ProviderID {
        ProviderID(service: service, kind: .api)
    }

    public var displayName: String {
        switch kind {
        case .subscription: service.displayName
        case .api: service.apiDisplayName
        }
    }

    public var description: String { "\(service.rawValue).\(kind.rawValue)" }
}
