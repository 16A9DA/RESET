import Foundation

public enum NetError: Error, Equatable, LocalizedError {
    case offline
    case rateLimited
    case unauthorized
    case server(Int)
    /// The service refused the request itself (wrong model name, image too large). `message` is its own explanation.
    case rejected(Int, String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .offline: "No internet connection."
        case .rateLimited: "The service is rate limiting requests. Try again in a minute."
        case .unauthorized: "The service rejected the credentials."
        case .server(let c): "The service returned an error (\(c))."
        case .rejected(let c, let m): m.isEmpty ? "The service refused the request (\(c))." : "The service refused the request (\(c)): \(m)"
        case .badResponse: "The service returned an unexpected response."
        }
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> Data
}

/// Pure helpers for retry and error text, kept apart from URLSession so they can be tested.
public enum NetPolicy {
    public static let maxAttempts = 3

    /// Seconds to wait before another try, or nil when the status is not worth retrying.
    /// Overloaded (529) and transient 5xx get a short backoff. A rate limit honours Retry-After, capped so the user is not left waiting.
    public static func retryDelay(status: Int, attempt: Int, retryAfter: String?) -> TimeInterval? {
        guard attempt < maxAttempts - 1 else { return nil }
        switch status {
        case 429:
            let asked = retryAfter.flatMap(TimeInterval.init) ?? 2
            return asked <= 8 ? max(asked, 1) : nil   // a long wait means the quota is spent. Fail now and say so.
        case 500, 502, 503, 504, 529:
            return 0.6 * Double(attempt + 1)
        default:
            return nil
        }
    }

    /// Pulls the human message out of {"error":{"message":"..."}} (Anthropic, OpenAI) or {"detail":"..."} (the proxy).
    public static func message(from body: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "" }
        if let err = root["error"] as? [String: Any], let m = err["message"] as? String { return String(m.prefix(200)) }
        if let err = root["error"] as? String { return String(err.prefix(200)) }
        if let d = root["detail"] as? String { return String(d.prefix(200)) }
        return ""
    }
}

public struct URLSessionClient: HTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                let (data, resp) = try await session.data(for: request)
                guard let http = resp as? HTTPURLResponse else { throw NetError.badResponse }
                switch http.statusCode {
                case 200..<300: return data
                case 401, 403: throw NetError.unauthorized
                default:
                    if let wait = NetPolicy.retryDelay(status: http.statusCode, attempt: attempt, retryAfter: http.value(forHTTPHeaderField: "retry-after")) {
                        attempt += 1
                        try await Task.sleep(for: .seconds(wait))
                        continue
                    }
                    if http.statusCode == 429 { throw NetError.rateLimited }
                    if (400..<500).contains(http.statusCode) { throw NetError.rejected(http.statusCode, NetPolicy.message(from: data)) }
                    throw NetError.server(http.statusCode)
                }
            } catch let e as NetError {
                throw e
            } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(e.code) {
                // A dropped connection or timeout is retried once or twice. A phone with no network at all is not.
                if e.code != .notConnectedToInternet, attempt < NetPolicy.maxAttempts - 1 {
                    attempt += 1
                    try await Task.sleep(for: .seconds(0.6 * Double(attempt)))
                    continue
                }
                throw NetError.offline
            }
        }
    }
}
