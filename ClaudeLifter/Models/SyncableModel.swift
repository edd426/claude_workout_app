import Foundation

/// Marker protocol for @Model classes that participate in cloud sync.
///
/// Every mutation of a syncable field MUST eventually result in a
/// `recordChange()` call, so that:
///   (a) the sync manager's last-write-wins comparison uses a correct timestamp,
///   (b) the record is re-queued as `.pending` for the next push.
///
/// Historically many mutation sites silently forgot one or both — e.g.
/// TemplateEditor.save bumped `updatedAt` but not `lastModified`, and
/// WorkoutSet mutations never propagated to the parent Workout's
/// `lastModified`. That made sync LWW subtly wrong. A single helper lets us
/// audit conformance uniformly in tests (see LastModifiedPropagationTests).
protocol SyncableModel: AnyObject {
    var lastModified: Date { get set }
    var syncStatusRaw: String { get set }
}

extension SyncableModel {
    /// Mark this model as locally modified: bumps `lastModified` to now
    /// and resets `syncStatusRaw` to `.pending`. Idempotent and safe to
    /// call multiple times per mutation.
    func recordChange(at date: Date = .now) {
        lastModified = date
        syncStatusRaw = SyncStatus.pending.rawValue
    }
}
