import Foundation

struct HTTPResponse {
    let data: Data
    let http: HTTPURLResponse
}

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> HTTPResponse
    func bytes(for request: URLRequest) async throws -> (bytes: URLSession.AsyncBytes, http: HTTPURLResponse)
}

final class DefaultHTTPClient: HTTPClient, @unchecked Sendable {
    static let uiCriticalClient = DefaultHTTPClient(configuration: DefaultHTTPClient.makeConfiguration(requestTimeout: 15, resourceTimeout: 30))
    static let discoveryClient = DefaultHTTPClient(configuration: DefaultHTTPClient.makeConfiguration(requestTimeout: 15, resourceTimeout: 30))
    static let aiClient = DefaultHTTPClient(configuration: DefaultHTTPClient.makeConfiguration(requestTimeout: 120, resourceTimeout: 120))
    static let aiStreamingClient = DefaultHTTPClient(configuration: DefaultHTTPClient.makeConfiguration(requestTimeout: 120, resourceTimeout: 7200))

    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResponse(data: data, http: http)
    }

    func bytes(for request: URLRequest) async throws -> (bytes: URLSession.AsyncBytes, http: HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (bytes: bytes, http: http)
    }

    private static func makeConfiguration(requestTimeout: TimeInterval, resourceTimeout: TimeInterval) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral // SECURITY: Prevent sensitive data from being cached to disk
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = false
        return config
    }
}
