import Foundation
import Combine
import CryptoKit
import AppKit

@MainActor
class UsageService: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isAuthenticated = false
    @Published var isAwaitingCode = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var pollingMinutes: Int
    @Published private(set) var isPeakHours: Bool = false
    @Published private(set) var eta5hHours: Double?
    @Published private(set) var eta7dHours: Double?
    @Published private(set) var willExceed5h: Bool = false
    @Published private(set) var willExceed7d: Bool = false
    @Published private(set) var usageHistory: [UsageSnapshot] = []

    private var timer: Timer?
    private let session: URLSession
    private let credentialsStore: StoredCredentialsStore
    private var currentInterval: TimeInterval
    private var refreshTask: Task<Bool, Never>?
    private var previousSnapshot: UsageSnapshot?
    private static let historyFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/claude-usage-bar/history.json")
    private static let historyMaxAge: TimeInterval = 6 * 3600

    static let defaultPollingMinutes = 30
    static let pollingOptions = [1, 5, 15, 30, 60]
    private static let maxBackoffInterval: TimeInterval = 3600

    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let userinfoEndpoint = URL(string: "https://api.anthropic.com/api/oauth/userinfo")!
    private static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    private static let defaultRedirectURI = "https://platform.claude.com/oauth/code/callback"
    private static let defaultOAuthScopes = ["user:profile", "user:inference"]

    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let redirectUri = UsageService.defaultRedirectURI

    // PKCE state
    private var codeVerifier: String?
    private var oauthState: String?

    var pct5h: Double { (usage?.fiveHour?.utilization ?? 0) / 100.0 }
    var pct7d: Double { (usage?.sevenDay?.utilization ?? 0) / 100.0 }
    var pctExtra: Double { (usage?.extraUsage?.utilization ?? 0) / 100.0 }
    var reset5h: Date? { usage?.fiveHour?.resetsAtDate }
    var reset7d: Date? { usage?.sevenDay?.resetsAtDate }

    init(session: URLSession = .shared) {
        self.session = session
        self.credentialsStore = StoredCredentialsStore()
        let stored = UserDefaults.standard.integer(forKey: "pollingMinutes")
        let minutes = Self.pollingOptions.contains(stored) ? stored : Self.defaultPollingMinutes
        self.pollingMinutes = minutes
        self.currentInterval = TimeInterval(minutes * 60)
        self.isAuthenticated = credentialsStore.load() != nil
        updatePeakHours()
        usageHistory = Self.loadHistory()
        previousSnapshot = usageHistory.last
    }

    // MARK: - Polling

    func startPolling() {
        guard isAuthenticated else { return }
        Task {
            await fetchUsage()
            if accountEmail == nil { await fetchProfile() }
        }
        scheduleTimer()
    }

    func updatePollingInterval(_ minutes: Int) {
        pollingMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "pollingMinutes")
        currentInterval = TimeInterval(minutes * 60)
        if isAuthenticated {
            scheduleTimer()
            Task { await fetchUsage() }
        }
    }

    private var baseInterval: TimeInterval { TimeInterval(pollingMinutes * 60) }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isAuthenticated else { return }
                Task { await self.fetchUsage() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - OAuth PKCE Flow

    func startOAuthFlow() {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier()

        codeVerifier = verifier
        oauthState = state

        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: Self.defaultOAuthScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
            isAwaitingCode = true
        }
    }

    func submitOAuthCode(_ rawCode: String) async {
        let parts = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1)
        let code = String(parts[0])

        if parts.count > 1 {
            let returnedState = String(parts[1])
            guard returnedState == oauthState else {
                lastError = "OAuth state mismatch - try again"
                isAwaitingCode = false
                codeVerifier = nil
                oauthState = nil
                return
            }
        }

        guard let verifier = codeVerifier else {
            lastError = "No pending OAuth flow"
            isAwaitingCode = false
            return
        }

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": oauthState ?? "",
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "code_verifier": verifier,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Invalid token response"
                return
            }
            guard http.statusCode == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                lastError = "Token exchange failed: HTTP \(http.statusCode) \(bodyStr)"
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let credentials = credentials(from: json) else {
                lastError = "Could not parse token response"
                return
            }
            do {
                try credentialsStore.save(credentials)
            } catch {
                lastError = "Failed to save credentials: \(error.localizedDescription)"
                return
            }
            isAuthenticated = true
            isAwaitingCode = false
            lastError = nil
            codeVerifier = nil
            oauthState = nil
            await fetchProfile()
            startPolling()
        } catch {
            lastError = "Token exchange error: \(error.localizedDescription)"
        }
    }

    func signOut() {
        credentialsStore.delete()
        isAuthenticated = false
        usage = nil
        lastUpdated = nil
        accountEmail = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        lastError = nil
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    // MARK: - API

    func fetchUsage() async {
        guard credentialsStore.load() != nil else {
            lastError = "Not signed in"
            isAuthenticated = false
            return
        }
        do {
            guard let result = try await sendAuthorizedRequest(to: Self.usageEndpoint) else { return }
            let (data, http) = result
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? currentInterval
                currentInterval = min(max(retryAfter, currentInterval * 2), Self.maxBackoffInterval)
                lastError = "Rate limited - backing off to \(Int(currentInterval))s"
                scheduleTimer()
                return
            }
            guard http.statusCode == 200 else {
                lastError = "HTTP \(http.statusCode)"
                return
            }
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            usage = decoded.reconciled(with: usage)
            lastError = nil
            lastUpdated = Date()
            updateForecast()
            updatePeakHours()
            recordHistory()
            if currentInterval != baseInterval {
                currentInterval = baseInterval
                scheduleTimer()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetchProfile() async {
        // Try local Claude config first
        if let local = Self.loadLocalProfile() {
            accountEmail = local
            return
        }
        guard let result = try? await sendAuthorizedRequest(to: Self.userinfoEndpoint, expireOnAuthFail: false) else { return }
        let (data, http) = result
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let email = json["email"] as? String, !email.isEmpty {
            accountEmail = email
        } else if let name = json["name"] as? String, !name.isEmpty {
            accountEmail = name
        }
    }

    private static func loadLocalProfile() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any] else { return nil }
        if let email = account["emailAddress"] as? String, !email.isEmpty { return email }
        if let name = account["displayName"] as? String, !name.isEmpty { return name }
        return nil
    }

    // MARK: - Forecast & Peak Hours

    private func updateForecast() {
        let now = Date()
        let cur5h = pct5h
        let cur7d = pct7d

        defer {
            previousSnapshot = UsageSnapshot(date: now, pct5h: cur5h, pct7d: cur7d)
        }

        // 5-hour bucket — based on consumed % vs elapsed time in window
        if cur5h >= 1.0 {
            eta5hHours = 0
            willExceed5h = true
        } else if let reset = reset5h, cur5h > 0 {
            let secondsRemaining = reset.timeIntervalSince(now)
            let totalWindow: TimeInterval = 5 * 3600
            let hoursElapsed = (totalWindow - secondsRemaining) / 3600
            if hoursElapsed > 0.01 {
                let hourlyRate = cur5h / hoursElapsed
                let hoursToFull = (1.0 - cur5h) / hourlyRate
                eta5hHours = hoursToFull
                willExceed5h = hoursToFull * 3600 < secondsRemaining
            } else {
                eta5hHours = nil
                willExceed5h = false
            }
        } else {
            eta5hHours = nil
            willExceed5h = false
        }

        // 7-day bucket — based on consumed % vs elapsed days in window
        if cur7d >= 1.0 {
            eta7dHours = 0
            willExceed7d = true
        } else if let reset = reset7d, cur7d > 0 {
            let secondsRemaining = reset.timeIntervalSince(now)
            let totalWindow: TimeInterval = 7 * 24 * 3600
            let daysElapsed = (totalWindow - secondsRemaining) / 86400
            if daysElapsed > 0.01 {
                let dailyRate = cur7d / daysElapsed
                let daysToFull = (1.0 - cur7d) / dailyRate
                eta7dHours = daysToFull * 24
                willExceed7d = daysToFull * 86400 < secondsRemaining
            } else {
                eta7dHours = nil
                willExceed7d = false
            }
        } else {
            eta7dHours = nil
            willExceed7d = false
        }
    }

    private func updatePeakHours() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let components = calendar.dateComponents([.hour, .weekday], from: Date())
        let hour = components.hour ?? 0
        let weekday = components.weekday ?? 1
        isPeakHours = (2...6).contains(weekday) && (7..<17).contains(hour)
    }

    // MARK: - Usage History

    private func recordHistory() {
        let entry = UsageSnapshot(date: Date(), pct5h: pct5h, pct7d: pct7d)
        usageHistory.append(entry)
        let cutoff = Date().addingTimeInterval(-Self.historyMaxAge)
        usageHistory = usageHistory.filter { $0.date > cutoff }
        Self.persistHistory(usageHistory)
    }

    private static func persistHistory(_ entries: [UsageSnapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }

    private static func loadHistory() -> [UsageSnapshot] {
        guard let data = try? Data(contentsOf: historyFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([UsageSnapshot].self, from: data) else { return [] }
        let cutoff = Date().addingTimeInterval(-historyMaxAge)
        return entries.filter { $0.date > cutoff }
    }

    // MARK: - Authorized Requests

    private func sendAuthorizedRequest(to url: URL, expireOnAuthFail: Bool = true) async throws -> (Data, HTTPURLResponse)? {
        guard let initial = credentialsStore.load() else {
            lastError = "Not signed in"
            isAuthenticated = false
            return nil
        }
        if initial.needsRefresh() {
            _ = await refreshCredentials(force: true)
        }
        let active = credentialsStore.load() ?? initial
        var result = try await performRequest(token: active.accessToken, url: url)

        if result.1.statusCode != 401 { return result }

        guard await refreshCredentials(force: true), let refreshed = credentialsStore.load() else {
            if expireOnAuthFail { expireSession() }
            return nil
        }
        result = try await performRequest(token: refreshed.accessToken, url: url)
        if result.1.statusCode == 401 {
            if expireOnAuthFail { expireSession() }
            return nil
        }
        return result
    }

    private func performRequest(token: String, url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private func refreshCredentials(force: Bool) async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.performRefresh(force: force)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh(force: Bool) async -> Bool {
        guard let current = credentialsStore.load(),
              let refreshToken = current.refreshToken, !refreshToken.isEmpty else { return false }
        if !force && !current.needsRefresh() { return true }

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ]
        if !current.scopes.isEmpty { body["scope"] = current.scopes.joined(separator: " ") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let updated = credentials(from: json, fallback: current) else { return false }
            try credentialsStore.save(updated)
            isAuthenticated = true
            return true
        } catch { return false }
    }

    private func credentials(from json: [String: Any], fallback: StoredCredentials? = nil) -> StoredCredentials? {
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else { return nil }
        let scopeStr = json["scope"] as? String
        let scopes = scopeStr?.split(whereSeparator: \.isWhitespace).map(String.init)
            ?? fallback?.scopes ?? Self.defaultOAuthScopes
        return StoredCredentials(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? fallback?.refreshToken,
            expiresAt: Self.expirationDate(from: json["expires_in"]) ?? fallback?.expiresAt,
            scopes: scopes
        )
    }

    private static func expirationDate(from value: Any?) -> Date? {
        let seconds: TimeInterval?
        switch value {
        case let n as NSNumber: seconds = n.doubleValue
        case let n as Double: seconds = n
        case let n as Int: seconds = TimeInterval(n)
        case let s as String: seconds = TimeInterval(s)
        default: seconds = nil
        }
        guard let seconds else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private func expireSession() {
        credentialsStore.delete()
        isAuthenticated = false
        usage = nil
        lastUpdated = nil
        accountEmail = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        lastError = "Session expired - please sign in again"
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
