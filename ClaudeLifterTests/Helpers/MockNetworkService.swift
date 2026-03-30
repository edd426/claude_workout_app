import Foundation
@testable import ClaudeLifter

final class MockNetworkService: NetworkServiceProtocol, @unchecked Sendable {
    var postCallCount = 0
    var lastPostEndpoint: String?
    var lastQueryItems: [URLQueryItem]?
    var uploadBlobCallCount = 0
    var downloadBlobResult: Data = Data()
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
        lastQueryItems = queryItems
        if let error = errorToThrow { throw error }
        guard let value = responses[endpoint] as? R else {
            throw SyncError.serverError(500)
        }
        return value
    }

    // SSE chunks to emit from streamPost, keyed by endpoint
    var streamChunks: [String: [Data]] = [:]
    var streamError: Error?
    var streamCallCount = 0
    var lastStreamEndpoint: String?

    func streamPost(endpoint: String, body: some Encodable & Sendable) -> AsyncThrowingStream<Data, Error> {
        streamCallCount += 1
        lastStreamEndpoint = endpoint
        let chunks = streamChunks[endpoint] ?? []
        let error = streamError
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func uploadBlob(url: URL, data: Data, contentType: String) async throws {
        uploadBlobCallCount += 1
        if let error = errorToThrow { throw error }
    }

    func downloadBlob(url: URL) async throws -> Data {
        if let error = errorToThrow { throw error }
        return downloadBlobResult
    }
}
