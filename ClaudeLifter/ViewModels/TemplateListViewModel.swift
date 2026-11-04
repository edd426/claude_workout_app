import Foundation
import Observation

@Observable
@MainActor
final class TemplateListViewModel {
    var templates: [WorkoutTemplate] = []
    var isLoading = false
    var errorMessage: String? = nil
    /// Start date of the latest finished workout per template (#176).
    private(set) var lastDone: [UUID: Date] = [:]

    private let templateRepository: any TemplateRepository
    private let workoutRepository: (any WorkoutRepository)?

    init(
        templateRepository: any TemplateRepository,
        workoutRepository: (any WorkoutRepository)? = nil
    ) {
        self.templateRepository = templateRepository
        self.workoutRepository = workoutRepository
    }

    func loadTemplates() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await templateRepository.fetchAll()
            if let workoutRepository {
                lastDone = TemplateLastDone.dates(from: try await workoutRepository.fetchAll())
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func lastDoneDate(for template: WorkoutTemplate) -> Date? {
        TemplateLastDone.date(for: template, in: lastDone)
    }

    func deleteTemplate(_ template: WorkoutTemplate) async {
        // Capture ID before await to avoid sending @Model across actor boundary
        let id = template.id
        do {
            if let toDelete = try await templateRepository.fetch(id: id) {
                try await templateRepository.delete(toDelete)
            }
            templates.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
