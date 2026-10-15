import Foundation

public enum NetError: Error, Equatable, LocalizedError {
    case offline
    case rateLimited
    case unauthorized
    case server(Int)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .offline: "No internet connection."
        case .rateLimited: "The service is rate limiting requests. Try again in a minute."
        case .unauthorized: "The service rejected the credentials."
        case .server(let c): "The service returned an error (\(c))."
        case .badResponse: "The service returned an unexpected response."
        }
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> Data
}

public struct URLSessionClient: HTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse else { throw NetError.badResponse }
            switch http.statusCode {
            case 200..<300: return data
            case 401, 403: throw NetError.unauthorized
            case 429: throw NetError.rateLimited
            default: throw NetError.server(http.statusCode)
            }
        } catch let e as NetError {
            throw e
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(e.code) {
            throw NetError.offline
        }
    }
}
