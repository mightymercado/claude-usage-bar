import Foundation

struct StoredCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: [String]

    var hasRefreshToken: Bool {
        guard let rt = refreshToken else { return false }
        return !rt.isEmpty
    }

    func needsRefresh(leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(leeway) >= expiresAt
    }
}

struct StoredCredentialsStore {
    private let configDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar")
    }()

    private var credentialsFile: URL { configDir.appendingPathComponent("credentials.json") }
    private var legacyFile: URL { configDir.appendingPathComponent("token") }

    func save(_ credentials: StoredCredentials) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(credentials)
        try data.write(to: credentialsFile, options: .atomic)
        chmod(credentialsFile.path, 0o600)
    }

    func load(defaultScopes: [String] = ["user:profile", "user:inference"]) -> StoredCredentials? {
        if let data = try? Data(contentsOf: credentialsFile) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let creds = try? decoder.decode(StoredCredentials.self, from: data) {
                return creds
            }
        }
        // Legacy fallback: plain token file
        if let tokenData = try? Data(contentsOf: legacyFile),
           let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty
        {
            return StoredCredentials(
                accessToken: token,
                refreshToken: nil,
                expiresAt: nil,
                scopes: defaultScopes
            )
        }
        return nil
    }

    func delete() {
        try? FileManager.default.removeItem(at: credentialsFile)
        try? FileManager.default.removeItem(at: legacyFile)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        chmod(configDir.path, 0o700)
    }
}
