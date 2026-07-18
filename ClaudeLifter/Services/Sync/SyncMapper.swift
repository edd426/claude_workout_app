import Foundation

/// Model ↔ wire-DTO conversion for the snapshot mirror (issue #78) and for
/// BackupService's on-disk backup format.
///
/// The pull-merge machinery (applyDTO, last-write-wins field merging) was
/// deleted with the bidirectional sync design — the phone is authoritative,
/// so DTOs only flow model → wire on push, and wire → NEW model on restore.
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

    static func toDTO(_ exercise: Exercise) -> ExerciseDTO {
        ExerciseDTO(
            id: exercise.id,
            name: exercise.name,
            force: exercise.force,
            level: exercise.level,
            mechanic: exercise.mechanic,
            equipment: exercise.equipment,
            instructions: exercise.instructions,
            primaryMuscles: exercise.primaryMuscles,
            secondaryMuscles: exercise.secondaryMuscles,
            isCustom: exercise.isCustom,
            externalId: exercise.externalId,
            notes: exercise.notes,
            imageURL: exercise.imageURL,
            photoURL: exercise.photoURL,
            tags: exercise.tags.map { ExerciseTagDTO(category: $0.category, value: $0.value) }
        )
    }

    static func toDTO(_ entry: BodyWeightEntry) -> BodyWeightEntryDTO {
        BodyWeightEntryDTO(
            id: entry.id,
            weightKg: entry.weightKg,
            recordedAt: entry.recordedAt,
            source: entry.source,
            healthKitSampleUUID: entry.healthKitSampleUUID,
            lastModified: entry.lastModified
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

    /// Builds the Exercise WITHOUT its tags. Tags are relationship objects;
    /// the caller attaches them after the exercise is inserted into a context
    /// (the pattern ExerciseImportService and BackupService use).
    static func createExercise(from dto: ExerciseDTO) -> Exercise {
        Exercise(
            id: dto.id,
            name: dto.name,
            force: dto.force,
            level: dto.level,
            mechanic: dto.mechanic,
            equipment: dto.equipment,
            instructions: dto.instructions,
            primaryMuscles: dto.primaryMuscles,
            secondaryMuscles: dto.secondaryMuscles,
            isCustom: dto.isCustom,
            externalId: dto.externalId,
            notes: dto.notes,
            imageURL: dto.imageURL,
            photoURL: dto.photoURL
        )
    }

    static func createBodyWeightEntry(from dto: BodyWeightEntryDTO) -> BodyWeightEntry {
        BodyWeightEntry(
            id: dto.id,
            weightKg: dto.weightKg,
            recordedAt: dto.recordedAt,
            source: dto.source,
            healthKitSampleUUID: dto.healthKitSampleUUID,
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
