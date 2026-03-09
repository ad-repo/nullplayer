import Foundation
import Security

/// Helper for secure storage of sensitive data
/// Uses UserDefaults for development (to avoid keychain prompts with unsigned builds)
/// In production, set useKeychain = true for proper security
class KeychainHelper {
    
    // MARK: - Singleton
    
    static let shared = KeychainHelper()
    
    /// Use the data-protection keychain only when running as a proper app bundle.
    /// Raw dev binaries have no bundle ID and get -34018 from the data-protection keychain.
    private var useKeychain: Bool {
        return Bundle.main.bundleIdentifier != nil
    }
    
    private init() {}
    
    // MARK: - Keys
    
    private enum Keys {
        static let service = "com.nullplayer.app"
        static let plexAuthToken = "plex_auth_token"
        static let plexClientIdentifier = "plex_client_identifier"
        static let plexAccountData = "plex_account_data"
        static let subsonicServers = "subsonic_servers"
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
        let newIdentifier = "com.nullplayer.app-\(UUID().uuidString)"
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
    
    // MARK: - Subsonic Server Credentials
    
    /// Store Subsonic server credentials
    func setSubsonicServers(_ servers: [SubsonicServerCredentials]) -> Bool {
        guard let data = try? JSONEncoder().encode(servers) else {
            return false
        }
        return setData(data, forKey: Keys.subsonicServers)
    }
    
    /// Retrieve all stored Subsonic server credentials
    func getSubsonicServers() -> [SubsonicServerCredentials] {
        guard let data = getData(forKey: Keys.subsonicServers) else {
            return []
        }
        return (try? JSONDecoder().decode([SubsonicServerCredentials].self, from: data)) ?? []
    }
    
    /// Add a new Subsonic server
    func addSubsonicServer(_ server: SubsonicServerCredentials) -> Bool {
        var servers = getSubsonicServers()
        // Remove existing server with same ID if any
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        return setSubsonicServers(servers)
    }
    
    /// Update an existing Subsonic server
    func updateSubsonicServer(_ server: SubsonicServerCredentials) -> Bool {
        var servers = getSubsonicServers()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            return setSubsonicServers(servers)
        }
        return false
    }
    
    /// Remove a Subsonic server by ID
    func removeSubsonicServer(id: String) -> Bool {
        var servers = getSubsonicServers()
        servers.removeAll { $0.id == id }
        return setSubsonicServers(servers)
    }
    
    /// Get a specific Subsonic server by ID
    func getSubsonicServer(id: String) -> SubsonicServerCredentials? {
        return getSubsonicServers().first { $0.id == id }
    }
    
    /// Delete all Subsonic server credentials
    func clearSubsonicCredentials() {
        delete(forKey: Keys.subsonicServers)
    }
    
    // MARK: - Jellyfin Server Credentials
    
    private enum JellyfinKeys {
        static let jellyfinServers = "jellyfin_servers"
    }
    
    /// Store Jellyfin server credentials
    func setJellyfinServers(_ servers: [JellyfinServerCredentials]) -> Bool {
        guard let data = try? JSONEncoder().encode(servers) else { return false }
        return setData(data, forKey: JellyfinKeys.jellyfinServers)
    }
    
    /// Retrieve all stored Jellyfin server credentials
    func getJellyfinServers() -> [JellyfinServerCredentials] {
        guard let data = getData(forKey: JellyfinKeys.jellyfinServers) else { return [] }
        return (try? JSONDecoder().decode([JellyfinServerCredentials].self, from: data)) ?? []
    }
    
    /// Add a new Jellyfin server
    func addJellyfinServer(_ server: JellyfinServerCredentials) -> Bool {
        var servers = getJellyfinServers()
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        return setJellyfinServers(servers)
    }
    
    /// Update an existing Jellyfin server
    func updateJellyfinServer(_ server: JellyfinServerCredentials) -> Bool {
        var servers = getJellyfinServers()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            return setJellyfinServers(servers)
        }
        return false
    }
    
    /// Remove a Jellyfin server by ID
    func removeJellyfinServer(id: String) -> Bool {
        var servers = getJellyfinServers()
        servers.removeAll { $0.id == id }
        return setJellyfinServers(servers)
    }
    
    /// Get a specific Jellyfin server by ID
    func getJellyfinServer(id: String) -> JellyfinServerCredentials? {
        return getJellyfinServers().first { $0.id == id }
    }
    
    /// Delete all Jellyfin server credentials
    func clearJellyfinCredentials() {
        delete(forKey: JellyfinKeys.jellyfinServers)
    }

    // MARK: - Emby Server Credentials

    private enum EmbyKeys {
        static let embyServers = "emby_servers"
    }

    /// Store Emby server credentials
    func setEmbyServers(_ servers: [EmbyServerCredentials]) -> Bool {
        guard let data = try? JSONEncoder().encode(servers) else { return false }
        return setData(data, forKey: EmbyKeys.embyServers)
    }

    /// Retrieve all stored Emby server credentials
    func getEmbyServers() -> [EmbyServerCredentials] {
        guard let data = getData(forKey: EmbyKeys.embyServers) else { return [] }
        return (try? JSONDecoder().decode([EmbyServerCredentials].self, from: data)) ?? []
    }

    /// Add a new Emby server
    func addEmbyServer(_ server: EmbyServerCredentials) -> Bool {
        var servers = getEmbyServers()
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        return setEmbyServers(servers)
    }

    /// Update an existing Emby server
    func updateEmbyServer(_ server: EmbyServerCredentials) -> Bool {
        var servers = getEmbyServers()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            return setEmbyServers(servers)
        }
        return false
    }

    /// Remove an Emby server by ID
    func removeEmbyServer(id: String) -> Bool {
        var servers = getEmbyServers()
        servers.removeAll { $0.id == id }
        return setEmbyServers(servers)
    }

    /// Get a specific Emby server by ID
    func getEmbyServer(id: String) -> EmbyServerCredentials? {
        return getEmbyServers().first { $0.id == id }
    }

    /// Delete all Emby server credentials
    func clearEmbyCredentials() {
        delete(forKey: EmbyKeys.embyServers)
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
            // 1. Try new data-protection keychain first
            if let dp = getDataKeychain(forKey: key) { return dp }
            // 2. Migrate from legacy login keychain (items stored before this fix)
            if let legacy = getDataLegacyKeychain(forKey: key) {
                _ = setDataKeychain(legacy, forKey: key)
                deleteLegacyKeychain(forKey: key)
                return legacy
            }
            // 3. Migrate from UserDefaults (pre-Keychain items)
            if let ud = getDataUserDefaults(forKey: key) {
                _ = setDataKeychain(ud, forKey: key)
                deleteUserDefaults(forKey: key)
                return ud
            }
            return nil
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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true
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
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
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
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Legacy Login Keychain (migration only)

    private func getDataLegacyKeychain(forKey key: String) -> Data? {
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

    private func deleteLegacyKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
