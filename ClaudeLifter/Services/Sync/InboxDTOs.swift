import Foundation

/// A lossless Codable representation of an arbitrary JSON value.
///
/// Inbox payloads stay generic at the batch boundary so one malformed
/// operation can be failed independently instead of making the entire GET
/// response undecodable. `InboxApplier` decodes each payload into its
/// operation-specific type.
enum InboxJSONValue: Codable, Sendable, Equatable {
    case object([String: InboxJSONValue])
    case array([InboxJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([InboxJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: InboxJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func decode<Payload: Decodable>(_ type: Payload.Type) throws -> Payload {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }

}

struct InboxTemplateExercisePayload: Codable, Sendable, Equatable {
    let externalId: String
    let order: Int
    let defaultSets: Int
    let defaultReps: Int
    let defaultWeight: Double?
    let defaultRestSeconds: Int?
    let notes: String?
}

struct CreateTemplatePayload: Codable, Sendable, Equatable {
    let name: String
    let notes: String?
    let exercises: [InboxTemplateExercisePayload]
}

struct UpdateTemplatePayload: Codable, Sendable, Equatable {
    let id: String
    let name: String?
    let notes: String?
    let exercises: [InboxTemplateExercisePayload]?
}

struct DeleteTemplatePayload: Codable, Sendable, Equatable {
    let id: String
    let name: String
}

struct CreateCustomExercisePayload: Codable, Sendable, Equatable {
    let name: String
    let externalId: String?
    let equipment: String?
    let primaryMuscles: [String]?
    let secondaryMuscles: [String]?
    let instructions: [String]?
    let notes: String?
}

/// GET /api/inbox operation envelope. `op` and `status` remain raw strings so
/// an unknown value is isolated to this operation by the applier.
struct InboxOperationDTO: Codable, Sendable, Equatable {
    let id: String
    let createdAt: String
    let op: String
    let payload: InboxJSONValue
    let requiresApproval: Bool
    let status: String
    let appliedAt: String?
    let error: String?
}

struct InboxListResponse: Codable, Sendable, Equatable {
    let operations: [InboxOperationDTO]
}

enum InboxOperationStatus: String, Codable, Sendable, Equatable {
    case pending
    case awaitingApproval
    case applied
    case rejected
    case failed
}

enum InboxAckStatus: String, Codable, Sendable, Equatable {
    case awaitingApproval
    case applied
    case rejected
    case failed
}

struct InboxAckResult: Codable, Sendable, Equatable {
    let id: String
    let status: InboxAckStatus
    let error: String?

    init(id: String, status: InboxAckStatus, error: String? = nil) {
        self.id = id
        self.status = status
        self.error = error
    }
}

struct InboxAckRequest: Codable, Sendable, Equatable {
    let results: [InboxAckResult]
}

struct InboxAckCounts: Codable, Sendable, Equatable {
    let updated: Int
    let unchanged: Int
    let notFound: Int
    let invalid: Int
}

enum InboxAckOutcome: String, Codable, Sendable, Equatable {
    case updated
    case unchanged
    case notFound
    case conflict
}

struct InboxAckOperationResult: Codable, Sendable, Equatable {
    let id: String
    let requestedStatus: InboxAckStatus
    let resultingStatus: String?
    let outcome: InboxAckOutcome
    let conflict: String?
}

struct InboxAckResponse: Codable, Sendable, Equatable {
    let counts: InboxAckCounts
    let results: [InboxAckOperationResult]

    init(
        counts: InboxAckCounts,
        results: [InboxAckOperationResult] = []
    ) {
        self.counts = counts
        self.results = results
    }
}
