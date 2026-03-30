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

    static func applyDTO(_ dto: WorkoutDTO, to workout: Workout) {
        workout.name = dto.name
        workout.templateId = dto.templateId
        workout.completedAt = dto.completedAt
        workout.notes = dto.notes
        workout.lastModified = dto.lastModified
        workout.syncStatus = .synced
    }

    static func applyDTO(_ dto: TemplateDTO, to template: WorkoutTemplate) {
        template.name = dto.name
        template.notes = dto.notes
        template.updatedAt = dto.updatedAt
        template.lastPerformedAt = dto.lastPerformedAt
        template.timesPerformed = dto.timesPerformed
        template.lastModified = dto.lastModified
        template.syncStatus = .synced
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
}
