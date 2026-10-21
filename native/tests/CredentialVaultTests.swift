import Foundation

@main struct CredentialVaultTests {
    static func main() throws {
        let service = "com.studio.network-drive-manager.tests.\(UUID().uuidString)"
        let address = "qa.invalid"
        defer { try? CredentialVault.remove(address, service: service) }
        let missing = try CredentialVault.load(address, service: service)
        precondition(missing == nil)
        try CredentialVault.save(ServerCredentials(username: "qa-user", password: "synthetic-test-only", aliases: ["qa.invalid", "qa-alias.invalid"]), address: address, service: service)
        let first = try CredentialVault.load("QA.INVALID.", service: service)
        precondition(first?.username == "qa-user" && first?.password == "synthetic-test-only")
        precondition(first?.aliases == ["qa.invalid", "qa-alias.invalid"])
        try CredentialVault.save(ServerCredentials(username: "qa-updated", password: "synthetic-replacement"), address: address, service: service)
        let updated = try CredentialVault.load(address, service: service)
        precondition(updated?.username == "qa-updated" && updated?.password == "synthetic-replacement")
        try CredentialVault.remove(address, service: service)
        let removed = try CredentialVault.load(address, service: service)
        precondition(removed == nil)
        print("Keychain tests passed: missing, save, load, update, remove (isolated synthetic account)")
    }
}
