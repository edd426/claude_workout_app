import Foundation

protocol NetworkServiceProtocol: Sendable {
    func post<R: Decodable & Sendable>(endpoint: String, body: some Encodable & Sendable) async throws -> R
    func get<R: Decodable & Sendable>(endpoint: String, queryItems: [URLQueryItem]) async throws -> R
    func streamPost(endpoint: String, body: some Encodable & Sendable) -> AsyncThrowingStream<Data, Error>
    func uploadBlob(url: URL, data: Data, contentType: String) async throws
    func downloadBlob(url: URL) async throws -> Data
}
