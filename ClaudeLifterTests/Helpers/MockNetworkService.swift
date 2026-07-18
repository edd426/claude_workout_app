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

    /// Runs mid-request, after the call is recorded and before the response is
    /// returned — lets tests simulate mutations that happen while a POST is in
    /// flight (issue #74's edit-during-push race).
    var onPost: (@MainActor () -> Void)?

    func post<R: Decodable & Sendable>(endpoint: String, body: some Encodable & Sendable) async throws -> R {
        postCallCount += 1
        lastPostEndpoint = endpoint
        if let onPost { await onPost() }
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

    // MARK: - v2 snapshot sync (issue #78)

    var pushSnapshotCallCount = 0
    var lastSnapshotRequest: SnapshotPushRequest?
    var pushSnapshotResult: SnapshotPushResponse?
    /// Runs mid-request, after the request is recorded and before the response
    /// is returned — lets tests simulate edits made while the POST is in flight.
    var onPushSnapshot: (@MainActor () -> Void)?

    func pushSnapshot(_ request: SnapshotPushRequest) async throws -> SnapshotPushResponse {
        pushSnapshotCallCount += 1
        lastSnapshotRequest = request
        if let onPushSnapshot { await onPushSnapshot() }
        if let error = errorToThrow { throw error }
        guard let result = pushSnapshotResult else {
            throw SyncError.serverError(500)
        }
        return result
    }

    var fetchSnapshotCallCount = 0
    var fetchSnapshotResult: SnapshotFetchResponse?

    func fetchSnapshot() async throws -> SnapshotFetchResponse {
        fetchSnapshotCallCount += 1
        if let error = errorToThrow { throw error }
        guard let result = fetchSnapshotResult else {
            throw SyncError.serverError(500)
        }
        return result
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
