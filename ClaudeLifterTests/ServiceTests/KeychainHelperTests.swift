import Testing
import Foundation
@testable import ClaudeLifter

@Suite("KeychainHelper Tests")
struct KeychainHelperTests {
    @Test("write and read round-trip returns the stored value")
    func writeReadRoundTrip() {
        let key = "test_key_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }

        KeychainHelper.write(key: key, value: "secret123")
        let result = KeychainHelper.read(key: key)
        #expect(result == "secret123")
    }

    @Test("read returns nil for non-existent key")
    func readNonExistent() {
        let result = KeychainHelper.read(key: "non_existent_\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test("write overwrites existing value")
    func writeOverwrites() {
        let key = "test_overwrite_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }

        KeychainHelper.write(key: key, value: "first")
        KeychainHelper.write(key: key, value: "second")
        let result = KeychainHelper.read(key: key)
        #expect(result == "second")
    }

    @Test("delete removes stored value")
    func deleteRemovesValue() {
        let key = "test_delete_\(UUID().uuidString)"
        KeychainHelper.write(key: key, value: "to_delete")
        KeychainHelper.delete(key: key)
        let result = KeychainHelper.read(key: key)
        #expect(result == nil)
    }
}
