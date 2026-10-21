import CryptoKit
import Foundation

// MARK: - API Response Models

struct ClaudeOAuthCredentials: Decodable, Sendable {
    let claudeAiOauth: ClaudeOAuthToken
}

struct ClaudeOAuthToken: Decodable, Sendable {
    let accessToken: String
}

struct ClaudeUsageResponse: Decodable, Sendable {
    private let windows: [String: ClaudeUsageWindow]

    init(windows: [String: ClaudeUsageWindow] = [:]) {
        self.windows = windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var parsed: [String: ClaudeUsageWindow] = [:]

        for key in container.allKeys {
            if let window = try? container.decode(ClaudeUsageWindow.self, forKey: key) {
                parsed[key.stringValue] = window
            }
        }
        self.windows = parsed
    }

    func mergedWindow(for baseKey: String) -> ClaudeUsageWindow? {
        if let exact = windows[baseKey] {
            return exact
        }

        let prefix = "\(baseKey)_"
        let candidates = windows
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
        guard !candidates.isEmpty else { return nil }

        let utilization = candidates.map(\.utilization).max() ?? 0
        let resetTime = candidates
            .compactMap { window -> (Date, String)? in
                guard let resetRaw = window.resets_at,
                      let resetDate = DateUtils.parseISO8601(resetRaw) else {
                    return nil
                }
                return (resetDate, resetRaw)
            }
            .sorted { $0.0 < $1.0 }
            .first?
            .1

        return ClaudeUsageWindow(utilization: utilization, resets_at: resetTime)
    }
}

struct ClaudeUsageWindow: Decodable, Sendable {
    let utilization: Double
    let resets_at: String?
}

// MARK: - Accounts

/// One Claude Code login. An empty `configDir` is the default `~/.claude` login;
/// any other value is the `CLAUDE_CONFIG_DIR` that login was created with.
struct ClaudeAccount: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var label: String
    var configDir: String

    /// Fixed ID so the default login keeps its pre-multi-account usage cache keys.
    static let defaultLoginID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let defaultLogin = ClaudeAccount(id: defaultLoginID, label: "", configDir: "")

    init(id: UUID = UUID(), label: String = "", configDir: String = "") {
        self.id = id
        self.label = label
        self.configDir = configDir
    }

    /// Absolute config dir with `~` expanded, or nil for the default login.
    var resolvedConfigDir: String? {
        let trimmed = configDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    /// Claude Code names the Keychain item `Claude Code-credentials-<sha256(dir)[:8]>`
    /// when `CLAUDE_CONFIG_DIR` is set. Both slash spellings are tried because
    /// the CLI hashes the directory string it was given.
    var keychainServiceCandidates: [String] {
        let base = "Claude Code-credentials"
        guard let dir = resolvedConfigDir else { return [base] }
        let spellings = [dir, dir + "/"]
        return spellings.map { "\(base)-\(Self.shortSHA256($0.precomposedStringWithCanonicalMapping))" }
    }

    /// Plain-file credentials Claude Code writes when Keychain is unavailable.
    var credentialsFileURL: URL? {
        resolvedConfigDir.map { URL(fileURLWithPath: $0).appendingPathComponent(".credentials.json") }
    }

    /// Account metadata file (`oauthAccount.emailAddress`) for this login.
    var accountMetadataURL: URL {
        if let dir = resolvedConfigDir {
            return URL(fileURLWithPath: dir).appendingPathComponent(".claude.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    /// Signed-in email from the account metadata file, if any.
    func signedInEmail() -> String? {
        guard let data = try? Data(contentsOf: accountMetadataURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["oauthAccount"] as? [String: Any],
              let email = oauth["emailAddress"] as? String,
              !email.isEmpty else {
            return nil
        }
        return email
    }

    /// Row label: explicit label, then signed-in email, then the directory name.
    func displayLabel() -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let email = signedInEmail() { return email }
        if let dir = resolvedConfigDir { return (dir as NSString).lastPathComponent }
        return "default"
    }

    private static func shortSHA256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(8)
            .description
    }
}

/// Persists the Claude account list; an empty or missing list means the default login only.
enum ClaudeAccountStore {
    static let defaultsKey = "claudeAccounts"

    static func load(defaults: UserDefaults = .standard) -> [ClaudeAccount] {
        guard let data = defaults.data(forKey: defaultsKey),
              let accounts = try? JSONDecoder().decode([ClaudeAccount].self, from: data),
              !accounts.isEmpty else {
            return [.defaultLogin]
        }
        return accounts
    }

    static func save(_ accounts: [ClaudeAccount], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

// MARK: - Provider

final class ClaudeUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .claude
    let account: ClaudeAccount
    /// Position among several configured accounts; nil when only one is configured.
    let accountIndex: Int?

    private let session: URLSession
    private let credentialProvider: @Sendable () -> String?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static let tokenCacheLock = NSLock()
    private static let defaultCacheTTL: TimeInterval = 60
    private static let securityCLITimeout: TimeInterval = 2
    /// 429 backoff: doubles per consecutive 429 up to the cap. The endpoint sends
    /// `retry-after: 0`, so without this every poll would hit the limit again.
    private static let rateLimitBaseBackoff: TimeInterval = 60
    private static let rateLimitMaxBackoff: TimeInterval = 15 * 60
    private static let retryAfterMax: TimeInterval = 60 * 60
    nonisolated(unsafe) private static var tokenCache: [String: (token: String?, lookedUpAt: Date)] = [:]
    typealias SecurityCLIProcessRuntime = CLIProcessRuntime
    nonisolated(unsafe) static var securityCLIRunner: @Sendable (_ service: String, _ timeout: TimeInterval) -> String? = {
        service, timeout in
        runSecurityCLICommand(service: service, timeout: timeout)
    }

    init(
        session: URLSession = .shared,
        credentialProvider: (@Sendable () -> String?)? = nil,
        defaults: UserDefaults = .standard,
        account: ClaudeAccount = .defaultLogin,
        accountIndex: Int? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.credentialProvider = credentialProvider ?? { Self.readToken(for: account) }
        self.defaults = defaults
        self.account = account
        self.accountIndex = accountIndex
        self.now = now
    }

    /// Shown only when several accounts are configured or the user named this one.
    var accountLabel: String? {
        let hasExplicitLabel = !account.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard accountIndex != nil || hasExplicitLabel else { return nil }
        return account.displayLabel()
    }

    /// Added accounts stay visible even before login so a missing login is explained.
    func isConfigured() async -> Bool {
        account.resolvedConfigDir != nil || credentialProvider() != nil
    }

    func fetchUsage() async throws -> UsageData {
        guard let token = credentialProvider() else {
            if let dir = account.resolvedConfigDir {
                return (try? cachedOrThrow(APIError.unauthorized)) ?? notSignedInUsage(configDir: dir)
            }
            return try cachedOrThrow(APIError.unauthorized)
        }

        // Persisted per account so a provider rebuild doesn't skip the backoff.
        if let until = defaults.object(forKey: cacheKey("rateLimitedUntil")) as? Double,
           now().timeIntervalSince1970 < until {
            return try cachedOrThrow(APIError.rateLimited)
        }

        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let usageResponse: ClaudeUsageResponse
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return try cachedOrThrow(APIError.invalidResponse)
            }

            if httpResponse.statusCode == 429 {
                recordRateLimit(retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After"))
                return try cachedOrThrow(APIError.rateLimited)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let error: APIError = httpResponse.statusCode == 401
                    ? .unauthorized : .httpError(httpResponse.statusCode)
                return try cachedOrThrow(error)
            }

            clearRateLimit()
            defaults.set(now().timeIntervalSince1970, forKey: cacheKey("savedAt"))

            usageResponse = (try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data))
                ?? ClaudeUsageResponse()
        } catch {
            return try cachedOrThrow(error)
        }

        let fiveHour = resolveMetric(
            window: usageResponse.mergedWindow(for: "five_hour"),
            cacheKey: cacheKey("fiveHour")
        )
        let sevenDay = resolveMetric(
            window: usageResponse.mergedWindow(for: "seven_day"),
            cacheKey: cacheKey("sevenDay")
        )

        let planName = (defaults.string(forKey: "claudePlan")
            .flatMap { ClaudePlan(rawValue: $0) } ?? .pro).rawValue

        return UsageData(
            service: .claude,
            fiveHourUsage: fiveHour,
            weeklyUsage: sevenDay,
            lastUpdated: now(),
            isAvailable: true,
            planName: planName,
            accountLabel: accountLabel,
            accountIndex: accountIndex
        )
    }

    /// Returns cached usage data when available, otherwise re-throws the original error.
    /// This preserves valid 7d values when the API fails (e.g. token expiry overnight)
    /// but the 7d reset window hasn't passed yet. The result stays available so the
    /// menu bar keeps it, but carries the last success time and a stale notice.
    private func cachedOrThrow(_ error: Error) throws -> UsageData {
        let now = self.now()
        let fiveHour = validCachedMetric(forKey: cacheKey("fiveHour"), now: now)
        let sevenDay = validCachedMetric(forKey: cacheKey("sevenDay"), now: now)

        guard fiveHour != nil || sevenDay != nil else { throw error }

        let zeroPercent = UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil)
        let planName = (defaults.string(forKey: "claudePlan")
            .flatMap { ClaudePlan(rawValue: $0) } ?? .pro).rawValue

        let savedAt = (defaults.object(forKey: cacheKey("savedAt")) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
        let isRateLimited: Bool
        if case APIError.rateLimited = error { isRateLimited = true } else { isRateLimited = false }

        return UsageData(
            service: .claude,
            fiveHourUsage: fiveHour ?? zeroPercent,
            weeklyUsage: sevenDay ?? zeroPercent,
            lastUpdated: savedAt ?? now,
            isAvailable: true,
            planName: planName,
            statusMessage: isRateLimited
                ? "Rate limited — showing last known usage"
                : "Update failed — showing last known usage",
            accountLabel: accountLabel,
            accountIndex: accountIndex
        )
    }

    /// Honors a positive `Retry-After` (seconds); otherwise backs off exponentially.
    private func recordRateLimit(retryAfter: String?) {
        let streakKey = cacheKey("rateLimitStreak")
        let streak = defaults.integer(forKey: streakKey) + 1
        defaults.set(streak, forKey: streakKey)

        let delay: TimeInterval
        if let seconds = retryAfter.flatMap({ TimeInterval($0.trimmingCharacters(in: .whitespaces)) }),
           seconds > 0 {
            delay = min(seconds, Self.retryAfterMax)
        } else {
            let exponent = Double(min(streak - 1, 10))
            delay = min(Self.rateLimitBaseBackoff * pow(2, exponent), Self.rateLimitMaxBackoff)
        }
        defaults.set(now().addingTimeInterval(delay).timeIntervalSince1970, forKey: cacheKey("rateLimitedUntil"))
    }

    private func clearRateLimit() {
        defaults.removeObject(forKey: cacheKey("rateLimitStreak"))
        defaults.removeObject(forKey: cacheKey("rateLimitedUntil"))
    }

    /// The default login keeps the original keys so existing caches survive.
    private func cacheKey(_ window: String) -> String {
        account.id == ClaudeAccount.defaultLoginID
            ? "claudeUsageCache.\(window)"
            : "claudeUsageCache.\(account.id.uuidString).\(window)"
    }

    private func notSignedInUsage(configDir: String) -> UsageData {
        let zeroPercent = UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil)
        let shortDir = (configDir as NSString).abbreviatingWithTildeInPath
        return UsageData(
            service: .claude,
            fiveHourUsage: zeroPercent,
            weeklyUsage: nil,
            lastUpdated: now(),
            isAvailable: true,
            showsFiveHourUsage: false,
            statusMessage: "Not signed in. Run: CLAUDE_CONFIG_DIR=\(shortDir) claude",
            accountLabel: accountLabel,
            accountIndex: accountIndex
        )
    }

    private func resolveMetric(window: ClaudeUsageWindow?, cacheKey: String) -> UsageMetric {
        let now = self.now()
        let cached = validCachedMetric(forKey: cacheKey, now: now)

        guard let window else {
            return cached ?? UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil)
        }

        let incoming = UsageMetric(
            used: window.utilization,
            total: 100,
            unit: .percent,
            resetTime: window.resets_at.flatMap { DateUtils.parseISO8601($0) }
        )

        let pendingZeroKey = "\(cacheKey).pendingZero"
        if let cached, shouldPreferCachedMetric(cached, over: incoming, now: now) {
            // A usage reset pass drops to 0 without moving the boundary, so a zero
            // seen on two consecutive polls is accepted; a single one is a gap.
            guard incoming.resetTime != nil else { return cached }
            guard defaults.bool(forKey: pendingZeroKey) else {
                defaults.set(true, forKey: pendingZeroKey)
                return cached
            }
        }

        defaults.removeObject(forKey: pendingZeroKey)
        saveMetricCache(incoming, forKey: cacheKey)
        return incoming
    }

    private func validCachedMetric(forKey key: String, now: Date) -> UsageMetric? {
        guard let cached = loadMetricCache(forKey: key) else { return nil }

        if let reset = cached.resetTime, reset <= now {
            clearMetricCache(forKey: key)
            return nil
        }

        // Legacy or meaningless cache entry from older builds.
        if cached.used <= 0, cached.resetTime == nil {
            clearMetricCache(forKey: key)
            return nil
        }

        return cached
    }

    private func shouldPreferCachedMetric(
        _ cached: UsageMetric?,
        over incoming: UsageMetric,
        now: Date
    ) -> Bool {
        guard let cached else { return false }
        guard cached.used > 0 else { return false }
        guard let cachedReset = cached.resetTime, cachedReset > now else { return false }
        guard incoming.used <= 0 else { return false }

        // Idle sessions can return empty windows; keep cached usage until known reset.
        if incoming.resetTime == nil {
            return true
        }

        // If reset boundary didn't actually advance, sudden zero is likely a transient API gap.
        if let incomingReset = incoming.resetTime,
           abs(incomingReset.timeIntervalSince(cachedReset)) < 1 {
            return true
        }

        return false
    }

    private func saveMetricCache(_ metric: UsageMetric, forKey key: String) {
        defaults.set(metric.used, forKey: "\(key).used")
        defaults.set(metric.total, forKey: "\(key).total")
        defaults.set(metric.resetTime?.timeIntervalSince1970, forKey: "\(key).resetTime")
    }

    private func loadMetricCache(forKey key: String) -> UsageMetric? {
        guard defaults.object(forKey: "\(key).used") != nil else { return nil }
        let used = defaults.double(forKey: "\(key).used")
        let total = defaults.object(forKey: "\(key).total") != nil ? defaults.double(forKey: "\(key).total") : 100
        let resetTimestamp = defaults.object(forKey: "\(key).resetTime") as? Double
        let resetTime = resetTimestamp.map { Date(timeIntervalSince1970: $0) }
        return UsageMetric(used: used, total: total, unit: .percent, resetTime: resetTime)
    }

    private func clearMetricCache(forKey key: String) {
        defaults.removeObject(forKey: "\(key).used")
        defaults.removeObject(forKey: "\(key).total")
        defaults.removeObject(forKey: "\(key).resetTime")
        defaults.removeObject(forKey: "\(key).pendingZero")
    }

    // MARK: - Keychain Access via security CLI

    /// Reads the OAuth token for `account` from Keychain, falling back to the
    /// plain `.credentials.json` file in a custom config dir.
    static func readToken(for account: ClaudeAccount, now: Date = Date()) -> String? {
        if let token = readKeychainTokenViaCLI(services: account.keychainServiceCandidates, now: now) {
            return token
        }
        guard let fileURL = account.credentialsFileURL,
              let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        return parseAccessToken(from: raw)
    }

    /// Reads the Claude Code OAuth token using the `security` CLI to avoid
    /// per-app Keychain ACL prompts. The first service that yields a token wins.
    /// The result is cached per service list with a TTL matching the refresh interval.
    static func readKeychainTokenViaCLI(
        services: [String] = ClaudeAccount.defaultLogin.keychainServiceCandidates,
        now: Date = Date(),
        cacheTTL: TimeInterval? = nil
    ) -> String? {
        let effectiveTTL = max(0, cacheTTL ?? cacheTTLFromRefreshInterval())
        let cacheKey = services.joined(separator: "\n")
        tokenCacheLock.lock()
        defer { tokenCacheLock.unlock() }

        if let entry = tokenCache[cacheKey],
           now.timeIntervalSince(entry.lookedUpAt) < effectiveTTL {
            return entry.token
        }

        var token: String?
        for service in services {
            if let raw = securityCLIRunner(service, securityCLITimeout),
               let parsed = parseAccessToken(from: raw) {
                token = parsed
                break
            }
        }
        tokenCache[cacheKey] = (token, now)
        return token
    }

    static func resetTokenCache() {
        tokenCacheLock.lock()
        tokenCache.removeAll()
        tokenCacheLock.unlock()
    }

    /// Parses the OAuth access token from the raw JSON credential blob.
    static func parseAccessToken(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let creds = try? JSONDecoder().decode(ClaudeOAuthCredentials.self, from: data) else {
            return nil
        }
        return creds.claudeAiOauth.accessToken
    }

    private static func cacheTTLFromRefreshInterval() -> TimeInterval {
        let refreshInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        return refreshInterval > 0 ? refreshInterval : defaultCacheTTL
    }

    /// Runs `security find-generic-password -s <service> -w`
    /// which outputs the password data to stdout. The `security` binary is a
    /// system-trusted application so it bypasses per-app ACL prompts.
    private static func runSecurityCLICommand(service: String, timeout: TimeInterval) -> String? {
        CLIProcessExecutor.executeCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-generic-password", "-s", service, "-w"],
            timeout: timeout
        )
    }

    static func executeSecurityCLICommand(timeout: TimeInterval, runtime: SecurityCLIProcessRuntime) -> String? {
        CLIProcessExecutor.executeCommand(timeout: timeout, runtime: runtime)
    }
}
