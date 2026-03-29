import Foundation
import Observation

@Observable
@MainActor
final class TemplateListViewModel {
    var templates: [WorkoutTemplate] = []
    var isLoading = false
    var errorMessage: String? = nil

    private let templateRepository: any TemplateRepository

    init(templateRepository: any TemplateRepository) {
        self.templateRepository = templateRepository
    }

    func loadTemplates() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await templateRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
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
