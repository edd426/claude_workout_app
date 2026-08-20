import Foundation
import SwiftData

/// What kind of complaint this is. The category is the ONLY thing the user
/// chooses when filing — every context field (exercise, workout, template,
/// set state) is captured automatically, because context is something the app
/// already knows and the gym is a bad place to fill in a form.
///
/// The category tells the AI reading these over MCP which captured context
/// actually matters: `.bug` cares about `workoutId` + `appVersion` and ignores
/// the exercise; `.wrongExercise` cares about `exerciseExternalId` and
/// `suggestedReplacement`.
enum ReportCategory: String, Codable, CaseIterable, Sendable {
    /// The app misbehaved. Read workoutId, appVersion, contextSummary.
    case bug
    /// "Swap this exercise for something else." Read exercise + template.
    case swapRequest
    /// The logged exercise is a stand-in because the real one isn't in the
    /// catalog. Read exerciseExternalId + suggestedReplacement; the fix is
    /// usually create_custom_exercise plus a template update.
    case wrongExercise
    /// A logged value is wrong (bad weight, phantom set).
    case dataError
    /// A note about form, setup, or machine settings — folds into the
    /// exercise's own notes rather than becoming an issue.
    case formOrSetup
    case other

    var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .swapRequest: return "Swap it out"
        case .wrongExercise: return "Wrong exercise"
        case .dataError: return "Bad data"
        case .formOrSetup: return "Form / setup"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .bug: return "ladybug"
        case .swapRequest: return "arrow.triangle.2.circlepath"
        case .wrongExercise: return "tag"
        case .dataError: return "exclamationmark.triangle"
        case .formOrSetup: return "figure.strengthtraining.traditional"
        case .other: return "ellipsis.bubble"
        }
    }
}

/// Report lifecycle. Without this the AI re-surfaces the same complaints every
/// session and the backlog stops being trusted — the status is not an
/// afterthought, it is what makes `list_exercise_reports(status: "open")`
/// mean something.
enum ReportStatus: String, Codable, CaseIterable, Sendable {
    /// Filed, nothing has happened yet.
    case open
    /// Seen and understood, but the fix is not done (e.g. a GitHub issue exists).
    case acknowledged
    /// Dealt with. Out of the open backlog for good.
    case resolved
}

/// What the reports list is showing (#146).
///
/// Separate from `ReportStatus` because one of the useful views is not a single
/// status: `backlog` is open + acknowledged, which is what "still outstanding"
/// actually means and what `list_exercise_reports` returns by default over MCP.
/// Keeping the two vocabularies aligned matters — the phone and the AI should
/// not disagree about what is left to do.
enum ReportStatusFilter: String, CaseIterable, Sendable, Identifiable {
    /// Open + acknowledged. The default, and the honest answer to "what is left".
    case backlog
    case open
    case acknowledged
    case resolved
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .backlog: return "Outstanding"
        case .open: return "Open"
        case .acknowledged: return "Acknowledged"
        case .resolved: return "Resolved"
        case .all: return "All"
        }
    }

    var systemImage: String {
        switch self {
        case .backlog: return "tray.full"
        case .open: return "flag"
        case .acknowledged: return "checkmark.bubble"
        case .resolved: return "checkmark.circle"
        case .all: return "list.bullet"
        }
    }

    func includes(_ status: ReportStatus) -> Bool {
        switch self {
        case .all: return true
        case .backlog: return status != .resolved
        case .open: return status == .open
        case .acknowledged: return status == .acknowledged
        case .resolved: return status == .resolved
        }
    }
}

/// A complaint filed from the app — usually mid-workout, in one or two taps —
/// about an exercise, a logged value, or the app itself (issue #135).
///
/// Mirrored to Cosmos by snapshot sync so Claude Code can read the backlog
/// over MCP, and closed back out through the inbox write path
/// (`resolveExerciseReport`). Schema V3.
///
/// Exercises are referenced by `externalId`, never by `Exercise.id` — the UUID
/// is minted per install at import time and is meaningless off-device
/// (`infra/MCP_WRITE_PATH.md`). `exerciseName` is a snapshot taken at file
/// time so the report stays readable even if the exercise is later swapped
/// out or renamed — which is precisely what a `.swapRequest` asks for.
@Model
final class ExerciseReport: SyncableModel {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    var categoryRaw: String
    /// The complaint, in the user's own words.
    var detail: String

    var exerciseExternalId: String?
    var exerciseName: String?
    /// For `.swapRequest` / `.wrongExercise`: what it should be instead.
    var suggestedReplacement: String?

    var workoutId: UUID?
    var workoutExerciseId: UUID?
    var templateId: UUID?
    /// Bounded, human-readable snapshot of the set state at file time, so a
    /// `.bug` arrives with a repro nobody had to type in the gym.
    var contextSummary: String?

    var statusRaw: String
    var resolution: String?

    var appVersion: String?
    var iosVersion: String?
    var photoURL: String?

    var syncStatusRaw: String = "pending"
    var lastModified: Date

    var category: ReportCategory {
        get { ReportCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var status: ReportStatus {
        get { ReportStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        category: ReportCategory,
        detail: String,
        exerciseExternalId: String? = nil,
        exerciseName: String? = nil,
        suggestedReplacement: String? = nil,
        workoutId: UUID? = nil,
        workoutExerciseId: UUID? = nil,
        templateId: UUID? = nil,
        contextSummary: String? = nil,
        status: ReportStatus = .open,
        resolution: String? = nil,
        appVersion: String? = nil,
        iosVersion: String? = nil,
        photoURL: String? = nil,
        syncStatus: SyncStatus = .pending,
        lastModified: Date = .now
    ) {
        self.id = id
        self.createdAt = createdAt
        self.categoryRaw = category.rawValue
        self.detail = detail
        self.exerciseExternalId = exerciseExternalId
        self.exerciseName = exerciseName
        self.suggestedReplacement = suggestedReplacement
        self.workoutId = workoutId
        self.workoutExerciseId = workoutExerciseId
        self.templateId = templateId
        self.contextSummary = contextSummary
        self.statusRaw = status.rawValue
        self.resolution = resolution
        self.appVersion = appVersion
        self.iosVersion = iosVersion
        self.photoURL = photoURL
        self.syncStatusRaw = syncStatus.rawValue
        self.lastModified = lastModified
    }
}
