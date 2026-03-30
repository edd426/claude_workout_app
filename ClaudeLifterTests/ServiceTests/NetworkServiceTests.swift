import Testing
import Foundation
@testable import ClaudeLifter

@Suite("NetworkService Tests")
struct NetworkServiceTests {
    @Test("SyncError not configured has descriptive localizedDescription")
    func syncErrorNotConfigured() {
        let error = SyncError.notConfigured
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("SyncError unauthorized has descriptive localizedDescription")
    func syncErrorUnauthorized() {
        let error = SyncError.unauthorized
        #expect(error.errorDescription != nil)
    }

    @Test("SyncError serverError includes status code")
    func syncErrorServerError() {
        let error = SyncError.serverError(503)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("503"))
    }

    @Test("SyncError networkUnavailable has descriptive localizedDescription")
    func syncErrorNetworkUnavailable() {
        let error = SyncError.networkUnavailable
        #expect(error.errorDescription != nil)
    }

    @Test("NetworkService initializes with SettingsManager")
    func networkServiceInit() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-netinit-\(UUID())")!)
        settings.serverURL = "https://example.com"
        settings.apiKey = "test-key"
        let service = NetworkService(settings: settings)
        #expect(service != nil)
    }
}
