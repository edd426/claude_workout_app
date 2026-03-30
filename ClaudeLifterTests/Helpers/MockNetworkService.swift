import Foundation
@testable import ClaudeLifter

final class MockNetworkService: NetworkServiceProtocol, @unchecked Sendable {
    var postCallCount = 0
    var lastPostEndpoint: String?
    var errorToThrow: Error? = nil

    // Generic response to return — keyed by endpoint
    private var responses: [String: Any] = [:]

    func setResponse<T>(_ value: T, forEndpoint endpoint: String) {
        responses[endpoint] = value
    }

    func post<R: Decodable & Sendable>(endpoint: String, body: some Encodable & Sendable) async throws -> R {
        postCallCount += 1
        lastPostEndpoint = endpoint
        if let error = errorToThrow { throw error }
        guard let value = responses[endpoint] as? R else {
            throw SyncError.serverError(500)
        }
        return value
    }

    func get<R: Decodable & Sendable>(endpoint: String, queryItems: [URLQueryItem]) async throws -> R {
        if let error = errorToThrow { throw error }
        guard let value = responses[endpoint] as? R else {
            throw SyncError.serverError(500)
        }
        return value
    }

    func streamPost(endpoint: String, body: some Encodable & Sendable) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func uploadBlob(url: URL, data: Data, contentType: String) async throws {
        if let error = errorToThrow { throw error }
    }

    func downloadBlob(url: URL) async throws -> Data {
        if let error = errorToThrow { throw error }
        return Data()
    }
}
