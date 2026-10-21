import Foundation

// MARK: - Claude Code statusline snapshots
//
// Claude Code pipes a JSON payload to the `statusLine` command on every
// statusline refresh. Its `rate_limits` object comes from API response headers
// (Claude Code 2.1.306 docs embedded in the binary):
//
//   "rate_limits": {
//     "five_hour": { "used_percentage": number, "resets_at": number },   // 0-100, Unix epoch seconds
//     "seven_day": { "used_percentage": number, "resets_at": number },
//     "spend_limit": { ... }                                              // gateway only, ignored here
//   }
//
// The AgentBar statusline wrapper (see ClaudeStatusLineInstaller) stores each
// payload as `{"version":1,"received_at":<epoch s>,"config_dir":"<CLAUDE_CONFIG_DIR>","payload":<raw>}`.

struct ClaudeStatusLineWindow: Equatable, Sendable {
    let usedPercentage: Double
    let resetsAt: Date
}

struct ClaudeStatusLineSnapshot: Equatable, Sendable {
    /// When the wrapper received the payload.
    let receivedAt: Date
    /// Normalized `CLAUDE_CONFIG_DIR`; nil for the default login.
    let configDir: String?
    let fiveHour: ClaudeStatusLineWindow?
    let sevenDay: ClaudeStatusLineWindow?
    /// `session_id` and `cost.total_api_duration_ms` identify whether a payload
    /// carries a new API observation or is a re-render of older data.
    let sessionID: String?
    let apiDurationMs: Double?

    static func parse(_ data: Data) -> ClaudeStatusLineSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let receivedAt = (root["received_at"] as? NSNumber)?.doubleValue,
              let payload = root["payload"] as? [String: Any],
              let rateLimits = payload["rate_limits"] as? [String: Any] else {
            return nil
        }

        let fiveHour = window(rateLimits["five_hour"])
        let sevenDay = window(rateLimits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }

        let cost = payload["cost"] as? [String: Any]
        return ClaudeStatusLineSnapshot(
            receivedAt: Date(timeIntervalSince1970: receivedAt),
            configDir: normalizedConfigDir(root["config_dir"] as? String),
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            sessionID: payload["session_id"] as? String,
            apiDurationMs: (cost?["total_api_duration_ms"] as? NSNumber)?.doubleValue
        )
    }

    /// Same normalization as `ClaudeAccount.resolvedConfigDir`: tilde expanded,
    /// standardized, no trailing slash. Unset or empty means the default login.
    static func normalizedConfigDir(_ raw: String?) -> String? {
        ClaudeAccount(configDir: raw ?? "").resolvedConfigDir
    }

    func belongs(to account: ClaudeAccount) -> Bool {
        configDir == account.resolvedConfigDir
    }

    private static func window(_ value: Any?) -> ClaudeStatusLineWindow? {
        guard let object = value as? [String: Any],
              let used = (object["used_percentage"] as? NSNumber)?.doubleValue,
              let resetsAt = (object["resets_at"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return ClaudeStatusLineWindow(usedPercentage: used, resetsAt: Date(timeIntervalSince1970: resetsAt))
    }
}

/// Reads the snapshot files the statusline wrapper writes, one per config dir.
struct ClaudeStatusLineSnapshotStore: Sendable {
    let directory: URL

    static var defaultDirectory: URL {
        ClaudeStatusLineInstaller.defaultBaseDirectory.appendingPathComponent("snapshots", isDirectory: true)
    }

    init(directory: URL = ClaudeStatusLineSnapshotStore.defaultDirectory) {
        self.directory = directory
    }

    /// Newest snapshot whose `CLAUDE_CONFIG_DIR` maps to `account`. Files are
    /// matched by content, not by name, so the wrapper's file key is opaque.
    func latestSnapshot(for account: ClaudeAccount) -> ClaudeStatusLineSnapshot? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        return names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .compactMap { name in
                (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap(ClaudeStatusLineSnapshot.parse)
            }
            .filter { $0.belongs(to: account) }
            .max { $0.receivedAt < $1.receivedAt }
    }
}
