import Foundation

protocol NetworkServiceProtocol: Sendable {
    func post<R: Decodable & Sendable>(endpoint: String, body: some Encodable & Sendable) async throws -> R
    func get<R: Decodable & Sendable>(endpoint: String, queryItems: [URLQueryItem]) async throws -> R
    func streamPost(endpoint: String, body: some Encodable & Sendable) -> AsyncThrowingStream<Data, Error>
    func uploadBlob(url: URL, data: Data, contentType: String) async throws
    func downloadBlob(url: URL) async throws -> Data

    // v2 one-way snapshot sync (issue #78)

    /// POST /api/sync/snapshot — full-state replace of the cloud mirror.
    func pushSnapshot(_ request: SnapshotPushRequest) async throws -> SnapshotPushResponse
    /// GET /api/sync/snapshot — disaster-restore read of the mirror.
    func fetchSnapshot() async throws -> SnapshotFetchResponse

    // Durable MCP write inbox (issue #88)

    /// GET /api/inbox?status=... — operations in one server-durable state.
    func fetchInbox(status: InboxOperationStatus) async throws -> InboxListResponse
    /// POST /api/inbox/ack — acknowledge independent operation results.
    func ackInbox(_ request: InboxAckRequest) async throws -> InboxAckResponse
}
