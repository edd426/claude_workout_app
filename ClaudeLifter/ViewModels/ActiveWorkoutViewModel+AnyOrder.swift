import Foundation

/// Where one exercise stands in the session, for the strip and the collapsed
/// cards.
struct ExerciseProgress: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case untouched
        case inProgress
        case finished
        case skipped
    }

    let completedSets: Int
    let totalSets: Int
    let status: Status
}

/// A template-listed substitute for a planned exercise (#169).
struct AlternativeOption: Identifiable {
    let exercise: Exercise
    let note: String?
    /// The alternative's own last working set, if it has history.
    let last: AutoFillResult?

    var id: UUID { exercise.id }
    var name: String { exercise.name }

    /// "last: 40 kg × 12", or nil with no history.
    func lastText(locale: Locale = .current) -> String? {
        guard let last else { return nil }
        let reps = last.reps.map(String.init) ?? "–"
        guard let weight = last.weight else { return "last: BW × \(reps)" }
        let number = SetEntryText.number(weight, locale: locale)
        return "last: \(number) \(last.weightUnit.rawValue) × \(reps)"
    }
}

/// What a swapped slot held before the first swap, for Undo.
struct SwapRecord {
    let original: Exercise
    let notes: String?
    let values: [UUID: SetEntryText.Entry]
    let previous: [UUID: AutoFillResult]
}

// MARK: - Ordering, expansion, skip

extension ActiveWorkoutViewModel {
    /// The session's exercises in order. Derived here rather than in `body`
    /// (UI-E5); it reads the model, so a Coach tool that adds an exercise
    /// still shows up.
    var orderedExercises: [WorkoutExercise] {
        workout?.exercises.sorted { $0.order < $1.order } ?? []
    }

    func canMove(_ workoutExercise: WorkoutExercise, by offset: Int) -> Bool {
        let ordered = orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == workoutExercise.id }) else {
            return false
        }
        return ordered.indices.contains(index + offset)
    }

    /// Move up (-1) or down (+1). An explicit reorder, so unlike a skip or a
    /// swap it is offered to the template at the end (#129).
    func moveExercise(_ workoutExercise: WorkoutExercise, by offset: Int) {
        var ordered = orderedExercises
        guard
            let index = ordered.firstIndex(where: { $0.id == workoutExercise.id }),
            ordered.indices.contains(index + offset)
        else { return }
        ordered.swapAt(index, index + offset)
        for (position, exercise) in ordered.enumerated() where exercise.order != position {
            exercise.order = position
        }
        persistMutation()
    }

    func isExpanded(_ workoutExercise: WorkoutExercise) -> Bool {
        expandedExerciseId == workoutExercise.id
    }

    /// Opens one card and closes the rest. Opening a skipped card means he
    /// is doing it after all, so it is un-skipped.
    func expand(_ workoutExercise: WorkoutExercise) {
        skippedExerciseIds.remove(workoutExercise.id)
        expandedExerciseId = workoutExercise.id
    }

    func toggleExpansion(_ workoutExercise: WorkoutExercise) {
        if isExpanded(workoutExercise) {
            expandedExerciseId = nil
        } else {
            expand(workoutExercise)
        }
    }

    /// The first exercise with unfinished sets that isn't skipped. Used once,
    /// when the screen first has a workout; after that only taps move it.
    func expandFirstIncomplete() {
        guard expandedExerciseId == nil else { return }
        expandedExerciseId = orderedExercises.first { exercise in
            !skippedExerciseIds.contains(exercise.id)
                && exercise.sets.contains { !$0.isCompleted }
        }?.id
    }

    func progress(for workoutExercise: WorkoutExercise) -> ExerciseProgress {
        let total = workoutExercise.sets.count
        let completed = workoutExercise.sets.filter(\.isCompleted).count
        let status: ExerciseProgress.Status
        if completed == 0, skippedExerciseIds.contains(workoutExercise.id) {
            status = .skipped
        } else if completed == 0 {
            status = .untouched
        } else if completed >= total {
            status = .finished
        } else {
            status = .inProgress
        }
        return ExerciseProgress(completedSets: completed, totalSets: total, status: status)
    }

    /// Skip is for something not started. Once a set is logged, the rest can
    /// simply be left, or removed.
    func canSkip(_ workoutExercise: WorkoutExercise) -> Bool {
        !workoutExercise.sets.contains(where: \.isCompleted)
    }

    func isSkipped(_ workoutExercise: WorkoutExercise) -> Bool {
        progress(for: workoutExercise).status == .skipped
    }

    /// Greys and collapses the card. Never a prompt, and never a template
    /// change: the rows stay as they are, and an exercise with no completed
    /// sets is already "not done" to the detector (#129).
    func skip(_ workoutExercise: WorkoutExercise) {
        guard canSkip(workoutExercise) else { return }
        skippedExerciseIds.insert(workoutExercise.id)
        if isExpanded(workoutExercise) {
            expandedExerciseId = nil
        }
    }

    /// The one-line summary of a collapsed card: what was done, last time, or
    /// that it was skipped.
    func collapsedSummary(
        for workoutExercise: WorkoutExercise,
        locale: Locale = .current
    ) -> String? {
        let sets = workoutExercise.sets.sorted { $0.order < $1.order }
        switch progress(for: workoutExercise).status {
        case .skipped:
            return "Skipped today"
        case .finished, .inProgress:
            let done = sets.filter(\.isCompleted).map {
                SetEntryText.Entry(weight: $0.weight, unit: $0.weightUnit, reps: $0.reps)
            }
            return SetEntryText.summary(of: done, locale: locale).map { "✓ \($0)" }
        case .untouched:
            let last = sets.compactMap { previous(for: $0) }.map {
                SetEntryText.Entry(weight: $0.weight, unit: $0.weightUnit, reps: $0.reps)
            }
            return SetEntryText.summary(of: last, locale: locale).map { "Last \($0)" }
        }
    }

    // MARK: - Set rows

    /// The planned reps when last session's reps for this set missed them
    /// (#144); nil otherwise. Shown next to PREVIOUS as "12 × 12 → 8".
    func driftTarget(for set: WorkoutSet, in workoutExercise: WorkoutExercise) -> Int? {
        guard previousDriftedFromTarget(set, in: workoutExercise) else { return nil }
        return plannedTarget(for: workoutExercise)?.reps
    }

    func previousText(
        for set: WorkoutSet,
        in workoutExercise: WorkoutExercise,
        locale: Locale = .current
    ) -> String? {
        guard let previous = previous(for: set) else { return nil }
        return SetEntryText.previous(
            previous,
            driftTarget: driftTarget(for: set, in: workoutExercise),
            locale: locale
        )
    }

    /// The set behind a focused field, for the keyboard bar.
    func entry(exerciseID: UUID, setID: UUID) -> (workoutExercise: WorkoutExercise, set: WorkoutSet)? {
        guard
            let workoutExercise = workout?.exercises.first(where: { $0.id == exerciseID }),
            let set = workoutExercise.sets.first(where: { $0.id == setID })
        else { return nil }
        return (workoutExercise, set)
    }

    /// The keyboard bar's −2.5 / +2.5, in the set's own unit. Zero or less
    /// is bodyweight, which this app stores as nil, never as 0 kg.
    func adjustWeight(_ set: WorkoutSet, by delta: Double) {
        let next = (set.weight ?? 0) + delta
        updateSetWeight(set, weight: next > 0 ? next : nil)
    }

    /// #170: pulls any machine photos the Coach attached, once per workout,
    /// so the card thumbnails show them. Idempotent on the fetcher's side too.
    func fetchMissingPhotos(using fetcher: any ExercisePhotoFetching) async {
        guard !didFetchPhotos else { return }
        didFetchPhotos = true
        if await fetcher.fetchMissing() > 0 {
            notePhotosLanded()
        }
    }
}

// MARK: - Machine taken (#169)

extension ActiveWorkoutViewModel {
    /// For screens that build this ViewModel without the repository: the
    /// workout view supplies it from the environment.
    func useAlternatives(from repository: any ExerciseAlternativeRepository) {
        guard alternativeRepository == nil else { return }
        alternativeRepository = repository
        if workout != nil {
            queueAlternativesLoad()
        }
    }

    func awaitAlternativesLoad() async {
        await pendingAlternativesLoad?.value
    }

    func alternatives(for workoutExercise: WorkoutExercise) -> [AlternativeOption] {
        alternativeOptions[workoutExercise.id] ?? []
    }

    /// Only before the first logged set: swapping after that would relabel
    /// sets already done as a different exercise.
    func canSwap(_ workoutExercise: WorkoutExercise) -> Bool {
        guard case .active = completionState else { return false }
        return !workoutExercise.sets.contains(where: \.isCompleted)
    }

    /// The slot holds a different exercise from the one it was planned with.
    /// Derived from the baseline, so it survives a crash and resume.
    func isSwapped(_ workoutExercise: WorkoutExercise) -> Bool {
        if swapRecords[workoutExercise.id] != nil { return true }
        guard
            let planned = plannedExerciseIds[workoutExercise.id],
            let current = workoutExercise.exercise
        else { return false }
        return !TemplateChangeDetector.isSameExercise(
            current,
            plannedId: planned.id,
            plannedExternalId: planned.externalId
        )
    }

    func swappedFromName(for workoutExercise: WorkoutExercise) -> String? {
        swapRecords[workoutExercise.id]?.original.name
    }

    /// One tap: the exercise changes in place. Order and set count stay; the
    /// sets take the alternative's own last session, so the committed values
    /// are honest (a squat's 80 kg is not a leg press weight). Undo is in the
    /// same menu, so there is no confirmation.
    func swap(_ workoutExercise: WorkoutExercise, to exercise: Exercise) async {
        guard canSwap(workoutExercise), let current = workoutExercise.exercise else { return }
        guard current.id != exercise.id else { return }
        if let record = swapRecords[workoutExercise.id], record.original.id == exercise.id {
            await undoSwap(workoutExercise)
            return
        }
        let sets = workoutExercise.sets.sorted { $0.order < $1.order }
        if swapRecords[workoutExercise.id] == nil {
            swapRecords[workoutExercise.id] = SwapRecord(
                original: current,
                notes: workoutExercise.notes,
                values: Dictionary(uniqueKeysWithValues: sets.map {
                    ($0.id, SetEntryText.Entry(weight: $0.weight, unit: $0.weightUnit, reps: $0.reps))
                }),
                previous: sets.reduce(into: [:]) { result, set in
                    result[set.id] = previous(for: set)
                }
            )
        }
        workoutExercise.exercise = exercise
        // The planned cue was about the planned exercise.
        workoutExercise.notes = nil

        let autoFills = (try? await autoFillService.autoFillValues(
            exerciseId: exercise.id,
            setCount: sets.count,
            excludingWorkoutId: workout?.id
        )) ?? []
        let plannedReps = plannedTarget(for: workoutExercise)?.reps
        for (index, set) in sets.enumerated() {
            let autoFill = index < autoFills.count ? autoFills[index] : nil
            set.weight = autoFill?.weight
            set.weightUnit = autoFill?.weightUnit ?? set.weightUnit
            set.reps = autoFill?.reps ?? plannedReps ?? set.reps
            previousValues[set.id] = autoFill
            weightDecidedByUser.remove(set.id)
            repsDecidedByUser.remove(set.id)
        }
        persistMutation()
    }

    func undoSwap(_ workoutExercise: WorkoutExercise) async {
        guard canSwap(workoutExercise), let record = swapRecords[workoutExercise.id] else { return }
        workoutExercise.exercise = record.original
        workoutExercise.notes = record.notes
        for set in workoutExercise.sets {
            if let entry = record.values[set.id] {
                set.weight = entry.weight
                set.weightUnit = entry.unit
                set.reps = entry.reps
            }
            previousValues[set.id] = record.previous[set.id]
        }
        swapRecords[workoutExercise.id] = nil
        persistMutation()
    }

    /// The muscle "Other…" pre-filters the library to.
    func primaryMuscle(for workoutExercise: WorkoutExercise) -> String? {
        let planned = swapRecords[workoutExercise.id]?.original ?? workoutExercise.exercise
        return planned?.primaryMuscles.first
    }

    /// Loads every planned slot's alternatives up front, so the menu has them
    /// the moment it opens; a Menu cannot wait on a fetch.
    func queueAlternativesLoad() {
        guard alternativeRepository != nil else { return }
        let preceding = pendingAlternativesLoad
        pendingAlternativesLoad = Task { [weak self] in
            await preceding?.value
            guard let self else { return }
            await self.loadAlternatives()
        }
    }

    private func loadAlternatives() async {
        guard let alternativeRepository, let exerciseRepository else { return }
        var options: [UUID: [AlternativeOption]] = [:]
        for (slotId, templateExerciseId) in sourceTemplateExerciseIds {
            guard let listed = try? await alternativeRepository.alternatives(
                forTemplateExercise: templateExerciseId
            ) else { continue }
            var resolved: [AlternativeOption] = []
            for alternative in listed {
                guard let exercise = try? await exerciseRepository.fetchByExternalId(
                    alternative.externalId
                ) else { continue }
                let last = try? await autoFillService.lastPerformed(exerciseId: exercise.id)
                resolved.append(AlternativeOption(exercise: exercise, note: alternative.note, last: last))
            }
            if !resolved.isEmpty {
                options[slotId] = resolved
            }
        }
        alternativeOptions = options
    }
}
