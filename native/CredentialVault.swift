import Foundation
import Security

struct ServerCredentials: Codable, Sendable {
    var username: String
    var password: String
    var aliases: [String]? = nil
}

enum CredentialVault {
    static let service = "com.studio.network-drive-manager.accounts"
    static func key(_ address: String) -> String {
        address.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
    static func query(_ address: String, service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key(address)]
    }
    static func load(_ address: String, service: String = service) throws -> ServerCredentials? {
        var attributes = query(address, service: service)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw VaultError(status: status) }
        return try JSONDecoder().decode(ServerCredentials.self, from: data)
    }
    static func save(_ credentials: ServerCredentials, address: String, service: String = service) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes = query(address, service: service)
        let updated = SecItemUpdate(attributes as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound {
            var item = attributes
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "MacNDMG · \(address)"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw VaultError(status: added) }
        } else if updated != errSecSuccess { throw VaultError(status: updated) }
    }
    static func remove(_ address: String, service: String = service) throws {
        let status = SecItemDelete(query(address, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }
    struct VaultError: LocalizedError {
        var status: OSStatus
        var errorDescription: String? { "Keychain could not access this saved account (\(status))." }
    }
}
