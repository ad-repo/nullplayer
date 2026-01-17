import Foundation
import Security

/// Helper for secure storage of sensitive data
/// Uses UserDefaults for development (to avoid keychain prompts with unsigned builds)
/// In production, set useKeychain = true for proper security
class KeychainHelper {
    
    // MARK: - Singleton
    
    static let shared = KeychainHelper()
    
    /// Set to true for production builds with proper code signing
    /// Set to false for development to avoid keychain permission prompts
    private let useKeychain = false
    
    private init() {}
    
    // MARK: - Keys
    
    private enum Keys {
        static let service = "com.adamp.app"
        static let plexAuthToken = "plex_auth_token"
        static let plexClientIdentifier = "plex_client_identifier"
        static let plexAccountData = "plex_account_data"
    }
    
    // MARK: - Plex Auth Token
    
    /// Store the Plex auth token securely
    func setPlexAuthToken(_ token: String) -> Bool {
        return setString(token, forKey: Keys.plexAuthToken)
    }
    
    /// Retrieve the stored Plex auth token
    func getPlexAuthToken() -> String? {
        return getString(forKey: Keys.plexAuthToken)
    }
    
    /// Delete the Plex auth token
    func deletePlexAuthToken() {
        delete(forKey: Keys.plexAuthToken)
    }
    
    // MARK: - Plex Client Identifier
    
    /// Get or create a persistent client identifier for Plex API
    func getOrCreateClientIdentifier() -> String {
        if let existing = getString(forKey: Keys.plexClientIdentifier) {
            return existing
        }
        
        // Generate a new unique identifier
        let newIdentifier = "com.adamp.app-\(UUID().uuidString)"
        _ = setString(newIdentifier, forKey: Keys.plexClientIdentifier)
        return newIdentifier
    }
    
    // MARK: - Plex Account Data
    
    /// Store the full Plex account data
    func setPlexAccount(_ account: PlexAccount) -> Bool {
        guard let data = try? JSONEncoder().encode(account) else {
            return false
        }
        return setData(data, forKey: Keys.plexAccountData)
    }
    
    /// Retrieve the stored Plex account
    func getPlexAccount() -> PlexAccount? {
        guard let data = getData(forKey: Keys.plexAccountData) else {
            return nil
        }
        return try? JSONDecoder().decode(PlexAccount.self, from: data)
    }
    
    /// Delete all Plex-related credentials
    func clearPlexCredentials() {
        delete(forKey: Keys.plexAuthToken)
        delete(forKey: Keys.plexAccountData)
        // Note: We keep the client identifier as it should persist
    }
    
    // MARK: - Generic Keychain Operations
    
    private func setString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return setData(data, forKey: key)
    }
    
    private func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private func setData(_ data: Data, forKey key: String) -> Bool {
        if useKeychain {
            return setDataKeychain(data, forKey: key)
        } else {
            return setDataUserDefaults(data, forKey: key)
        }
    }
    
    private func getData(forKey key: String) -> Data? {
        if useKeychain {
            return getDataKeychain(forKey: key)
        } else {
            return getDataUserDefaults(forKey: key)
        }
    }
    
    private func delete(forKey key: String) {
        if useKeychain {
            deleteKeychain(forKey: key)
        } else {
            deleteUserDefaults(forKey: key)
        }
    }
    
    // MARK: - UserDefaults Storage (Development)
    
    private func setDataUserDefaults(_ data: Data, forKey key: String) -> Bool {
        UserDefaults.standard.set(data, forKey: "\(Keys.service).\(key)")
        return true
    }
    
    private func getDataUserDefaults(forKey key: String) -> Data? {
        return UserDefaults.standard.data(forKey: "\(Keys.service).\(key)")
    }
    
    private func deleteUserDefaults(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: "\(Keys.service).\(key)")
    }
    
    // MARK: - Keychain Storage (Production)
    
    private func setDataKeychain(_ data: Data, forKey key: String) -> Bool {
        // Delete any existing item first
        deleteKeychain(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func getDataKeychain(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    private func deleteKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
