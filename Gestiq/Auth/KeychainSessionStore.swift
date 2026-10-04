import Foundation
import Security

struct KeychainSessionStore: RefreshSessionStore {
    let service: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "refresh-session"]
    }

    func read() throws -> StoredRefreshSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw storageError }
        guard let saved = try? JSONDecoder().decode(StoredRefreshSession.self, from: data) else {
            try clear()
            return nil
        }
        return saved
    }

    func save(_ session: StoredRefreshSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw storageError }
        } else if status != errSecSuccess { throw storageError }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError }
    }

    private var storageError: AuthError {
        .message("No se pudo acceder a tu sesión guardada. Desbloquea el dispositivo e intenta de nuevo.")
    }
}
