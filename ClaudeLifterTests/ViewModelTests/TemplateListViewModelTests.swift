import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("TemplateListViewModel Tests")
@MainActor
struct TemplateListViewModelTests {

    @Test("loadTemplates populates templates")
    func loadTemplatesPopulatesTemplates() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let t1 = TestFixtures.makeTemplate(name: "Push Day")
        let t2 = TestFixtures.makeTemplate(name: "Pull Day")
        context.insert(t1)
        context.insert(t2)
        try context.save()

        let repo = MockTemplateRepository()
        repo.templates = [t1, t2]
        let vm = TemplateListViewModel(templateRepository: repo)

        await vm.loadTemplates()

        #expect(vm.templates.count == 2)
    }

    @Test("loadTemplates with error sets errorMessage")
    func loadTemplatesWithErrorSetsErrorMessage() async throws {
        let repo = MockTemplateRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = TemplateListViewModel(templateRepository: repo)

        await vm.loadTemplates()

        #expect(vm.errorMessage != nil)
    }

    @Test("deleteTemplate removes from templates and calls repository")
    func deleteTemplateRemovesFromList() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let template = TestFixtures.makeTemplate(name: "Push Day")
        context.insert(template)
        try context.save()

        let repo = MockTemplateRepository()
        repo.templates = [template]
        let vm = TemplateListViewModel(templateRepository: repo)
        await vm.loadTemplates()

        await vm.deleteTemplate(template)

        #expect(vm.templates.isEmpty)
        #expect(repo.deleteCallCount == 1)
    }

    @Test("isLoading is false after loadTemplates")
    func isLoadingDuringLoad() async throws {
        let repo = MockTemplateRepository()
        let vm = TemplateListViewModel(templateRepository: repo)

        #expect(vm.isLoading == false)
        await vm.loadTemplates()
        #expect(vm.isLoading == false)
    }
}
