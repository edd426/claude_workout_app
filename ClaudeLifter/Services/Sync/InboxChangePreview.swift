import Foundation

/// What an inbox operation would actually do to this phone, in words (#153, #147).
///
/// The approval card used to say "replaces the template details and its
/// exercise list (4 exercises)" for every update, whether it changed one reps
/// value or rewrote the whole plan. Evan, twice: "This doesn't actually let me
/// see what's getting changed." This is the diff.
struct InboxChangePreview: Equatable, Sendable {
    /// "Update “Lower B”", "Delete “Lower B”".
    let title: String
    /// One line for the Home card. The first change, or the no-op sentence.
    let summary: String
    /// Every change, one per line, in template order. Empty for a no-op.
    let lines: [InboxChangeLine]
    let isDestructive: Bool
}

/// One human-readable difference between the incoming payload and the local
/// template. Cases are data, not strings, so the tests pin meaning and the
/// view decides presentation.
enum InboxChangeLine: Equatable, Sendable, Identifiable {
    case renamed(from: String, to: String)
    case templateNoteChanged(from: String?, to: String?)
    case exerciseAdded(name: String, prescription: String)
    case exerciseRemoved(name: String)
    case prescriptionChanged(name: String, from: String, to: String)
    case weightChanged(name: String, from: Double?, to: Double?)
    case restChanged(name: String, from: Int, to: Int)
    case noteChanged(name: String, from: String?, to: String?)
    case reordered(names: [String])
    /// The slot's listed substitutes changed. Names, in order; empty = none.
    case alternativesChanged(name: String, from: [String], to: [String])

    var id: String { text }

    var text: String {
        switch self {
        case .renamed(let from, let to):
            return "Renamed: \(from) → \(to)"
        case .templateNoteChanged(let from, let to):
            return "Template note: \(Self.quote(from)) → \(Self.quote(to))"
        case .exerciseAdded(let name, let prescription):
            return "+ \(name) \(prescription)"
        case .exerciseRemoved(let name):
            return "− \(name)"
        case .prescriptionChanged(let name, let from, let to):
            return "\(name): \(from) → \(to)"
        case .weightChanged(let name, let from, let to):
            return "\(name): weight \(Self.format(from)) → \(Self.format(to))"
        case .restChanged(let name, let from, let to):
            return "\(name): rest \(from)s → \(to)s"
        case .noteChanged(let name, let from, let to):
            return "\(name): note \(Self.quote(from)) → \(Self.quote(to))"
        case .reordered(let names):
            return "Reordered: \(names.joined(separator: ", "))"
        case .alternativesChanged(let name, let from, let to):
            return "\(name): alternatives \(Self.list(from)) → \(Self.list(to))"
        }
    }

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    /// Adds, removes and renames matter more than a tweaked cue.
    var isStructural: Bool {
        switch self {
        case .exerciseAdded, .exerciseRemoved, .renamed, .reordered: return true
        default: return false
        }
    }

    private static func quote(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return "“\(value)”"
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "none" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }
}

/// The local template flattened into value types, so the diff is pure and
/// testable without SwiftData.
struct TemplateSnapshot: Equatable, Sendable {
    struct Exercise: Equatable, Sendable {
        let externalId: String?
        let name: String
        let sets: Int
        let reps: Int
        let weight: Double?
        let restSeconds: Int
        let notes: String?
        /// The slot's alternatives as externalIds, in order.
        var alternatives: [String] = []
    }

    let name: String
    let notes: String?
    let exercises: [Exercise]

    init(name: String, notes: String?, exercises: [Exercise]) {
        self.name = name
        self.notes = notes
        self.exercises = exercises
    }

    /// `alternatives` maps a template exercise's id to its alternatives'
    /// externalIds; the template itself cannot answer that (plain-UUID link).
    init(_ template: WorkoutTemplate, alternatives: [UUID: [String]] = [:]) {
        name = template.name
        notes = template.notes
        exercises = template.exercises
            .sorted { $0.order < $1.order }
            .map {
                Exercise(
                    externalId: $0.exercise?.externalId,
                    name: $0.exercise?.name ?? "Unknown exercise",
                    sets: $0.defaultSets,
                    reps: $0.defaultReps,
                    weight: $0.defaultWeight,
                    restSeconds: $0.defaultRestSeconds,
                    notes: $0.notes,
                    alternatives: alternatives[$0.id] ?? []
                )
            }
    }
}

/// Compares an `updateTemplate` payload with the template it targets.
///
/// Matching is by `externalId`, slot by slot for duplicates, because that is
/// how `InboxApplier` resolves the payload; a local exercise with no
/// externalId can never be matched and reads as removed. A nil rest in the
/// payload is the 90s default the applier will write, so it is not a change.
enum TemplateUpdateDiff {
    static let defaultRestSeconds = 90

    static func lines(
        payload: UpdateTemplatePayload,
        current: TemplateSnapshot,
        nameFor: (String) -> String
    ) -> [InboxChangeLine] {
        var lines: [InboxChangeLine] = []

        if let name = payload.name, name != current.name {
            lines.append(.renamed(from: current.name, to: name))
        }
        if let notes = payload.notes,
           normalized(notes) != normalized(current.notes) {
            lines.append(.templateNoteChanged(
                from: normalized(current.notes),
                to: normalized(notes)
            ))
        }
        guard let incoming = payload.exercises else { return lines }

        let proposed = incoming.sorted { $0.order < $1.order }

        // Slot-by-slot matching: a queue of unmatched local rows per externalId.
        var unmatched: [String: [Int]] = [:]
        for (index, exercise) in current.exercises.enumerated() {
            guard let externalId = exercise.externalId else { continue }
            unmatched[externalId, default: []].append(index)
        }

        var matchedCurrentIndices: [Int] = []
        var added: [InboxChangeLine] = []
        var fieldChanges: [InboxChangeLine] = []

        for proposal in proposed {
            guard var queue = unmatched[proposal.externalId], !queue.isEmpty else {
                added.append(.exerciseAdded(
                    name: nameFor(proposal.externalId),
                    prescription: prescription(proposal.defaultSets, proposal.defaultReps)
                ))
                if let proposed = proposal.alternatives?.map(\.externalId), !proposed.isEmpty {
                    fieldChanges.append(.alternativesChanged(
                        name: nameFor(proposal.externalId),
                        from: [],
                        to: proposed.map(nameFor)
                    ))
                }
                continue
            }
            let index = queue.removeFirst()
            unmatched[proposal.externalId] = queue
            matchedCurrentIndices.append(index)

            let local = current.exercises[index]
            if local.sets != proposal.defaultSets || local.reps != proposal.defaultReps {
                fieldChanges.append(.prescriptionChanged(
                    name: local.name,
                    from: prescription(local.sets, local.reps),
                    to: prescription(proposal.defaultSets, proposal.defaultReps)
                ))
            }
            if local.weight != proposal.defaultWeight {
                fieldChanges.append(.weightChanged(
                    name: local.name, from: local.weight, to: proposal.defaultWeight
                ))
            }
            let proposedRest = proposal.defaultRestSeconds ?? defaultRestSeconds
            if local.restSeconds != proposedRest {
                fieldChanges.append(.restChanged(
                    name: local.name, from: local.restSeconds, to: proposedRest
                ))
            }
            if normalized(local.notes) != normalized(proposal.notes) {
                fieldChanges.append(.noteChanged(
                    name: local.name,
                    from: normalized(local.notes),
                    to: normalized(proposal.notes)
                ))
            }
            // Absent alternatives keep the slot's list (InboxApplier carries
            // them over), so only an explicit, different list is a change.
            if let proposed = proposal.alternatives?.map(\.externalId),
               proposed != local.alternatives {
                fieldChanges.append(.alternativesChanged(
                    name: local.name,
                    from: local.alternatives.map(nameFor),
                    to: proposed.map(nameFor)
                ))
            }
        }

        let matchedSet = Set(matchedCurrentIndices)
        let removed: [InboxChangeLine] = current.exercises.indices
            .filter { !matchedSet.contains($0) }
            .map { .exerciseRemoved(name: current.exercises[$0].name) }

        // Survivors in proposal order vs. their local order.
        if matchedCurrentIndices != matchedCurrentIndices.sorted() {
            lines.append(.reordered(
                names: matchedCurrentIndices.map { current.exercises[$0].name }
            ))
        }

        lines.append(contentsOf: added)
        lines.append(contentsOf: removed)
        lines.append(contentsOf: fieldChanges)
        return lines
    }

    static func prescription(_ sets: Int, _ reps: Int) -> String {
        "\(sets) × \(reps)"
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// "Hanging_Leg_Raise" → "Hanging Leg Raise", for an externalId the
    /// library does not know yet.
    static func humanized(_ externalId: String) -> String {
        externalId.replacingOccurrences(of: "_", with: " ")
    }
}

@MainActor
protocol InboxChangePreviewBuilding {
    func preview(for operation: InboxOperationDTO) async -> InboxChangePreview
}

/// Resolves an operation's payload against local data and renders the preview.
/// Never throws: a preview that cannot be computed says why, because the
/// decision still has to be made.
@MainActor
final class InboxChangePreviewBuilder: InboxChangePreviewBuilding {
    private let templateRepository: any TemplateRepository
    private let exerciseRepository: any ExerciseRepository
    /// Optional so existing call sites keep compiling. Without it the preview
    /// cannot see the template's current alternatives, so a change to them
    /// reads as added-from-nothing; pass it wherever the app builds one.
    private let alternativeRepository: (any ExerciseAlternativeRepository)?

    init(
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        alternativeRepository: (any ExerciseAlternativeRepository)? = nil
    ) {
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.alternativeRepository = alternativeRepository
    }

    func preview(for operation: InboxOperationDTO) async -> InboxChangePreview {
        switch operation.op {
        case "updateTemplate":
            return await updatePreview(operation)
        case "deleteTemplate":
            return await deletePreview(operation)
        case "setExercisePhoto":
            return await photoPreview(operation)
        default:
            return InboxChangePreview(
                title: "Apply proposed change",
                summary: "Review this \(operation.op) operation before it changes local data.",
                lines: [],
                isDestructive: false
            )
        }
    }

    private func updatePreview(_ operation: InboxOperationDTO) async -> InboxChangePreview {
        guard let payload = try? operation.payload.decode(UpdateTemplatePayload.self) else {
            return InboxChangePreview(
                title: "Update template",
                summary: "The change could not be read; approving it will fail.",
                lines: [],
                isDestructive: false
            )
        }
        guard let id = UUID(uuidString: payload.id),
              let template = try? await templateRepository.fetch(id: id) else {
            return InboxChangePreview(
                title: "Update template",
                summary: "This template is not on this phone; the change cannot apply here.",
                lines: [],
                isDestructive: false
            )
        }

        var alternatives: [UUID: [String]] = [:]
        if let alternativeRepository {
            for te in template.exercises {
                let listed = (try? await alternativeRepository.alternatives(forTemplateExercise: te.id)) ?? []
                alternatives[te.id] = listed.map(\.externalId)
            }
        }
        let current = TemplateSnapshot(template, alternatives: alternatives)
        var referenced = Set((payload.exercises ?? []).map(\.externalId))
        referenced.formUnion((payload.exercises ?? []).flatMap { ($0.alternatives ?? []).map(\.externalId) })
        referenced.formUnion(current.exercises.flatMap(\.alternatives))
        var names: [String: String] = [:]
        for externalId in referenced {
            if let exercise = try? await exerciseRepository.fetchByExternalId(externalId) {
                names[externalId] = exercise.name
            }
        }
        let lines = TemplateUpdateDiff.lines(payload: payload, current: current) { externalId in
            names[externalId] ?? TemplateUpdateDiff.humanized(externalId)
        }
        return InboxChangePreview(
            title: "Update “\(current.name)”",
            summary: Self.summary(for: lines),
            lines: lines,
            isDestructive: false
        )
    }

    private func deletePreview(_ operation: InboxOperationDTO) async -> InboxChangePreview {
        let payload = try? operation.payload.decode(DeleteTemplatePayload.self)
        let name = payload?.name ?? "template"
        var count: Int?
        if let raw = payload?.id, let id = UUID(uuidString: raw),
           let template = try? await templateRepository.fetch(id: id) {
            count = template.exercises.count
        }
        let what = count.map { "its \($0) exercise\($0 == 1 ? "" : "s")" } ?? "its exercises"
        return InboxChangePreview(
            title: "Delete “\(name)”",
            summary: "Removes the template and \(what) from this phone and the cloud.",
            lines: [],
            isDestructive: true
        )
    }

    /// One line per op (#170): the title names the exercise, the summary says
    /// what approving does — including when it is going to fail, in the same
    /// order the applier checks.
    private func photoPreview(_ operation: InboxOperationDTO) async -> InboxChangePreview {
        guard let payload = try? operation.payload.decode(SetExercisePhotoPayload.self) else {
            return InboxChangePreview(
                title: "Set photo",
                summary: "The change could not be read; approving it will fail.",
                lines: [],
                isDestructive: false
            )
        }
        let exercise = try? await exerciseRepository.fetchByExternalId(payload.externalId)
        let name = exercise?.name ?? TemplateUpdateDiff.humanized(payload.externalId)
        let summary: String
        if payload.blobPath != SetExercisePhotoPayload.expectedBlobPath(for: payload.externalId) {
            summary = "The photo path does not match this exercise; approving it will fail."
        } else if let exercise {
            if exercise.photoURL == payload.blobPath {
                summary = "This photo is already on the exercise card."
            } else if exercise.photoURL?.isEmpty == false {
                summary = "Replaces the photo already on the exercise card."
            } else {
                summary = "Adds a photo to the exercise card."
            }
        } else {
            summary = "This exercise is not on this phone; approving it will fail."
        }
        return InboxChangePreview(
            title: "Set photo · \(name)",
            summary: summary,
            lines: [],
            isDestructive: false
        )
    }

    static func summary(for lines: [InboxChangeLine]) -> String {
        guard let first = lines.first else {
            return "No differences from the current template."
        }
        if lines.count == 1 { return first.text }
        return "\(first.text) · \(lines.count - 1) more"
    }
}
