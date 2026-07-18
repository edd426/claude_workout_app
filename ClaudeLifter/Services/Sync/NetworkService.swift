import Foundation

final class NetworkService: NetworkServiceProtocol, @unchecked Sendable {
    private let settings: SettingsManager
    private let session: URLSession

    private var encoder: JSONEncoder { Self.makeWireEncoder() }
    private var decoder: JSONDecoder { Self.makeWireDecoder() }

    // MARK: - Wire codecs
    //
    // The v2 snapshot contract mandates ISO 8601 with fractional seconds
    // (e.g. "2026-07-18T18:00:00.000Z"). Foundation's stock `.iso8601`
    // strategies neither emit nor parse fractional seconds, so both
    // directions are custom. Decoding is tolerant: it accepts fractional
    // and plain-second timestamps.

    // ISO8601DateFormatter is documented thread-safe (unlike NSDateFormatter
    // pre-iOS 7), and these are configured once and never mutated again —
    // hence nonisolated(unsafe) rather than a per-call allocation.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func makeWireEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFractional.string(from: date))
        }
        return encoder
    }

    static func makeWireDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = isoFractional.date(from: string) ?? isoPlain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not an ISO 8601 date: \(string)"
            )
        }
        return decoder
    }

    init(settings: SettingsManager, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    private func baseURL() throws -> URL {
        let urlString = settings.serverURL
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw SyncError.notConfigured
        }
        return url
    }

    private func request(for endpoint: String) throws -> URLRequest {
        let base = try baseURL()
        let url = base.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = settings.apiKey
        if !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        return request
    }

    func post<R: Decodable & Sendable>(endpoint: String, body: some Encodable & Sendable) async throws -> R {
        var req = try request(for: endpoint)
        req.httpMethod = "POST"
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: req)
        try validate(response: response)

        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw SyncError.decodingError(error)
        }
    }

    func get<R: Decodable & Sendable>(endpoint: String, queryItems: [URLQueryItem]) async throws -> R {
        var req = try request(for: endpoint)
        req.httpMethod = "GET"

        if !queryItems.isEmpty {
            var components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
            components?.queryItems = queryItems
            if let url = components?.url {
                req.url = url
            }
        }

        let (data, response) = try await session.data(for: req)
        try validate(response: response)

        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw SyncError.decodingError(error)
        }
    }

    func streamPost(endpoint: String, body: some Encodable & Sendable) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var req = try self.request(for: endpoint)
                    req.httpMethod = "POST"
                    req.httpBody = try self.encoder.encode(body)

                    let (bytes, response) = try await self.session.bytes(for: req)
                    try self.validate(response: response)

                    for try await byte in bytes {
                        continuation.yield(Data([byte]))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func pushSnapshot(_ request: SnapshotPushRequest) async throws -> SnapshotPushResponse {
        try await post(endpoint: "/api/sync/snapshot", body: request)
    }

    func fetchSnapshot() async throws -> SnapshotFetchResponse {
        try await get(endpoint: "/api/sync/snapshot", queryItems: [])
    }

    func uploadBlob(url: URL, data: Data, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")

        let (_, response) = try await session.upload(for: request, from: data)
        try validate(response: response)
    }

    func downloadBlob(url: URL) async throws -> Data {
        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return data
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw SyncError.unauthorized
        default:
            throw SyncError.serverError(http.statusCode)
        }
    }
}
