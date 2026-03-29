import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
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
}
