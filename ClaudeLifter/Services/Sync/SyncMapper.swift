import Foundation

enum SyncMapper {
    // MARK: - Model → DTO

    static func toDTO(_ workout: Workout) -> WorkoutDTO {
        WorkoutDTO(
            id: workout.id,
            templateId: workout.templateId,
            name: workout.name,
            startedAt: workout.startedAt,
            completedAt: workout.completedAt,
            notes: workout.notes,
            lastModified: workout.lastModified,
            exercises: workout.exercises
                .sorted { $0.order < $1.order }
                .map { toDTO($0) }
        )
    }

    static func toDTO(_ we: WorkoutExercise) -> WorkoutExerciseDTO {
        WorkoutExerciseDTO(
            id: we.id,
            exerciseId: we.exercise?.id ?? UUID(),
            exerciseName: we.exercise?.name,
            order: we.order,
            notes: we.notes,
            restSeconds: we.restSeconds,
            sets: we.sets
                .sorted { $0.order < $1.order }
                .map { toDTO($0) }
        )
    }

    static func toDTO(_ set: WorkoutSet) -> WorkoutSetDTO {
        WorkoutSetDTO(
            id: set.id,
            order: set.order,
            weight: set.weight,
            weightUnit: set.weightUnit.rawValue,
            reps: set.reps,
            isCompleted: set.isCompleted,
            completedAt: set.completedAt,
            notes: set.notes
        )
    }

    static func toDTO(_ template: WorkoutTemplate) -> TemplateDTO {
        TemplateDTO(
            id: template.id,
            name: template.name,
            notes: template.notes,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt,
            lastPerformedAt: template.lastPerformedAt,
            timesPerformed: template.timesPerformed,
            lastModified: template.lastModified,
            exercises: template.exercises
                .sorted { $0.order < $1.order }
                .map { toDTO($0) }
        )
    }

    static func toDTO(_ te: TemplateExercise) -> TemplateExerciseDTO {
        TemplateExerciseDTO(
            id: te.id,
            exerciseId: te.exercise?.id ?? UUID(),
            exerciseName: te.exercise?.name,
            order: te.order,
            defaultSets: te.defaultSets,
            defaultReps: te.defaultReps,
            defaultWeight: te.defaultWeight,
            defaultRestSeconds: te.defaultRestSeconds,
            notes: te.notes
        )
    }

    static func toDTO(_ message: AIChatMessage) -> ChatMessageDTO {
        ChatMessageDTO(
            id: message.id,
            workoutId: message.workoutId,
            role: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp
        )
    }

    static func toDTO(_ insight: ProactiveInsight) -> InsightDTO {
        InsightDTO(
            id: insight.id,
            content: insight.content,
            type: insight.type.rawValue,
            generatedAt: insight.generatedAt,
            isRead: insight.isRead,
            lastModified: insight.lastModified
        )
    }

    static func toDTO(_ pref: TrainingPreference) -> PreferenceDTO {
        PreferenceDTO(
            id: pref.id,
            key: pref.key,
            value: pref.value,
            source: pref.source,
            lastModified: pref.lastModified
        )
    }

    // MARK: - DTO → Model (update existing model from DTO, last-write-wins)

    /// Simple scalar-only update (no nested exercises). Used when exerciseRepository is unavailable.
    static func applyDTO(_ dto: WorkoutDTO, to workout: Workout) {
        workout.name = dto.name
        workout.templateId = dto.templateId
        workout.completedAt = dto.completedAt
        workout.notes = dto.notes
        workout.lastModified = dto.lastModified
        workout.syncStatus = .synced
    }

    /// Full merge including nested exercises and sets.
    @MainActor
    static func applyDTO(
        _ dto: WorkoutDTO,
        to workout: Workout,
        exerciseRepository: any ExerciseRepository
    ) async throws {
        // Update scalar fields
        workout.name = dto.name
        workout.templateId = dto.templateId
        workout.completedAt = dto.completedAt
        workout.notes = dto.notes
        workout.lastModified = dto.lastModified
        workout.syncStatus = .synced

        // Merge exercises
        let localExercisesById = Dictionary(uniqueKeysWithValues: workout.exercises.map { ($0.id, $0) })
        let remoteIds = Set(dto.exercises.map(\.id))

        // Remove locals not in remote
        workout.exercises.removeAll { !remoteIds.contains($0.id) }

        // Insert or update
        for exerciseDTO in dto.exercises {
            if let local = localExercisesById[exerciseDTO.id] {
                applyDTO(exerciseDTO, to: local)
            } else {
                var exercise = try await exerciseRepository.fetch(id: exerciseDTO.exerciseId)
                if exercise == nil, let name = exerciseDTO.exerciseName {
                    exercise = try await exerciseRepository.fuzzySearch(query: name).first
                }
                if let exercise {
                    let we = WorkoutExercise(
                        id: exerciseDTO.id,
                        order: exerciseDTO.order,
                        exercise: exercise,
                        notes: exerciseDTO.notes,
                        restSeconds: exerciseDTO.restSeconds
                    )
                    for setDTO in exerciseDTO.sets {
                        let set = WorkoutSet(
                            id: setDTO.id,
                            order: setDTO.order,
                            weight: setDTO.weight,
                            weightUnit: WeightUnit(rawValue: setDTO.weightUnit) ?? .kg,
                            reps: setDTO.reps,
                            isCompleted: setDTO.isCompleted,
                            completedAt: setDTO.completedAt,
                            notes: setDTO.notes
                        )
                        we.sets.append(set)
                    }
                    workout.exercises.append(we)
                }
            }
        }
    }

    /// Simple scalar-only update (no nested exercises).
    static func applyDTO(_ dto: TemplateDTO, to template: WorkoutTemplate) {
        template.name = dto.name
        template.notes = dto.notes
        template.updatedAt = dto.updatedAt
        template.lastPerformedAt = dto.lastPerformedAt
        template.timesPerformed = dto.timesPerformed
        template.lastModified = dto.lastModified
        template.syncStatus = .synced
    }

    /// Full merge including nested template exercises.
    @MainActor
    static func applyDTO(
        _ dto: TemplateDTO,
        to template: WorkoutTemplate,
        exerciseRepository: any ExerciseRepository
    ) async throws {
        // Update scalar fields
        template.name = dto.name
        template.notes = dto.notes
        template.updatedAt = dto.updatedAt
        template.lastPerformedAt = dto.lastPerformedAt
        template.timesPerformed = dto.timesPerformed
        template.lastModified = dto.lastModified
        template.syncStatus = .synced

        // Merge exercises
        let localExercisesById = Dictionary(uniqueKeysWithValues: template.exercises.map { ($0.id, $0) })
        let remoteIds = Set(dto.exercises.map(\.id))

        // Remove locals not in remote
        template.exercises.removeAll { !remoteIds.contains($0.id) }

        // Insert or update
        for teDTO in dto.exercises {
            if let local = localExercisesById[teDTO.id] {
                applyDTO(teDTO, to: local)
            } else {
                var exercise = try await exerciseRepository.fetch(id: teDTO.exerciseId)
                if exercise == nil, let name = teDTO.exerciseName {
                    exercise = try await exerciseRepository.fuzzySearch(query: name).first
                }
                if let exercise {
                    let te = TemplateExercise(
                        id: teDTO.id,
                        order: teDTO.order,
                        exercise: exercise,
                        defaultSets: teDTO.defaultSets,
                        defaultReps: teDTO.defaultReps,
                        defaultWeight: teDTO.defaultWeight,
                        defaultRestSeconds: teDTO.defaultRestSeconds,
                        notes: teDTO.notes
                    )
                    template.exercises.append(te)
                }
            }
        }
    }

    static func applyDTO(_ dto: InsightDTO, to insight: ProactiveInsight) {
        insight.content = dto.content
        insight.isRead = dto.isRead
        insight.lastModified = dto.lastModified
        insight.syncStatus = .synced
    }

    static func applyDTO(_ dto: PreferenceDTO, to pref: TrainingPreference) {
        pref.value = dto.value
        pref.source = dto.source
        pref.lastModified = dto.lastModified
        pref.syncStatus = .synced
    }

    // MARK: - Nested DTO → Model helpers

    static func applyDTO(_ dto: WorkoutExerciseDTO, to we: WorkoutExercise) {
        we.order = dto.order
        we.notes = dto.notes
        we.restSeconds = dto.restSeconds

        // Merge sets
        let localSetsById = Dictionary(uniqueKeysWithValues: we.sets.map { ($0.id, $0) })
        let remoteSetIds = Set(dto.sets.map(\.id))

        // Remove locals not in remote
        we.sets.removeAll { !remoteSetIds.contains($0.id) }

        // Insert or update
        for setDTO in dto.sets {
            if let localSet = localSetsById[setDTO.id] {
                applyDTO(setDTO, to: localSet)
            } else {
                let newSet = WorkoutSet(
                    id: setDTO.id,
                    order: setDTO.order,
                    weight: setDTO.weight,
                    weightUnit: WeightUnit(rawValue: setDTO.weightUnit) ?? .kg,
                    reps: setDTO.reps,
                    isCompleted: setDTO.isCompleted,
                    completedAt: setDTO.completedAt,
                    notes: setDTO.notes
                )
                we.sets.append(newSet)
            }
        }
    }

    static func applyDTO(_ dto: WorkoutSetDTO, to set: WorkoutSet) {
        set.order = dto.order
        set.weight = dto.weight
        set.weightUnit = WeightUnit(rawValue: dto.weightUnit) ?? .kg
        set.reps = dto.reps
        set.isCompleted = dto.isCompleted
        set.completedAt = dto.completedAt
        set.notes = dto.notes
    }

    static func applyDTO(_ dto: TemplateExerciseDTO, to te: TemplateExercise) {
        te.order = dto.order
        te.defaultSets = dto.defaultSets
        te.defaultReps = dto.defaultReps
        te.defaultWeight = dto.defaultWeight
        te.defaultRestSeconds = dto.defaultRestSeconds
        te.notes = dto.notes
    }

    // MARK: - Factory methods (create new model from DTO)

    @MainActor
    static func createWorkout(
        from dto: WorkoutDTO,
        exerciseRepository: any ExerciseRepository
    ) async throws -> Workout {
        let workout = Workout(
            id: dto.id,
            name: dto.name,
            startedAt: dto.startedAt,
            templateId: dto.templateId,
            completedAt: dto.completedAt,
            notes: dto.notes,
            syncStatus: .synced,
            lastModified: dto.lastModified
        )

        for weDTO in dto.exercises {
            // Try fetch by ID first, then fall back to fuzzy name search
            var exercise = try await exerciseRepository.fetch(id: weDTO.exerciseId)
            if exercise == nil, let name = weDTO.exerciseName {
                exercise = try await exerciseRepository.fuzzySearch(query: name).first
            }
            guard let exercise else { continue }
            let we = WorkoutExercise(
                id: weDTO.id,
                order: weDTO.order,
                exercise: exercise,
                notes: weDTO.notes,
                restSeconds: weDTO.restSeconds
            )
            for setDTO in weDTO.sets {
                let set = WorkoutSet(
                    id: setDTO.id,
                    order: setDTO.order,
                    weight: setDTO.weight,
                    weightUnit: WeightUnit(rawValue: setDTO.weightUnit) ?? .kg,
                    reps: setDTO.reps,
                    isCompleted: setDTO.isCompleted,
                    completedAt: setDTO.completedAt,
                    notes: setDTO.notes
                )
                we.sets.append(set)
            }
            workout.exercises.append(we)
        }

        return workout
    }

    @MainActor
    static func createTemplate(
        from dto: TemplateDTO,
        exerciseRepository: any ExerciseRepository
    ) async throws -> WorkoutTemplate {
        let template = WorkoutTemplate(
            id: dto.id,
            name: dto.name,
            notes: dto.notes,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            lastPerformedAt: dto.lastPerformedAt,
            timesPerformed: dto.timesPerformed,
            syncStatus: .synced,
            lastModified: dto.lastModified
        )

        for teDTO in dto.exercises {
            // Try fetch by ID first, then fall back to fuzzy name search
            var exercise = try await exerciseRepository.fetch(id: teDTO.exerciseId)
            if exercise == nil, let name = teDTO.exerciseName {
                exercise = try await exerciseRepository.fuzzySearch(query: name).first
            }
            guard let exercise else { continue }
            let te = TemplateExercise(
                id: teDTO.id,
                order: teDTO.order,
                exercise: exercise,
                defaultSets: teDTO.defaultSets,
                defaultReps: teDTO.defaultReps,
                defaultWeight: teDTO.defaultWeight,
                defaultRestSeconds: teDTO.defaultRestSeconds,
                notes: teDTO.notes
            )
            template.exercises.append(te)
        }

        return template
    }

    static func createInsight(from dto: InsightDTO) -> ProactiveInsight {
        ProactiveInsight(
            id: dto.id,
            content: dto.content,
            type: InsightType(rawValue: dto.type) ?? .suggestion,
            generatedAt: dto.generatedAt,
            isRead: dto.isRead,
            syncStatus: .synced,
            lastModified: dto.lastModified
        )
    }

    static func createPreference(from dto: PreferenceDTO) -> TrainingPreference {
        TrainingPreference(
            id: dto.id,
            key: dto.key,
            value: dto.value,
            source: dto.source,
            syncStatus: .synced,
            lastModified: dto.lastModified
        )
    }
}
