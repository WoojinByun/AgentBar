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
    let sessionID: String?
    /// The session's transcript (`transcript_path`), which carries its identity and API activity.
    let transcriptPath: String?
    /// Org of the credentials the session runs with: the last `credential_org`
    /// attachment in its transcript. Filled in by `ClaudeStatusLineSnapshotStore`.
    var sessionOrganizationUUID: String? = nil
    /// Time of the session's last assistant message, i.e. its last API response,
    /// which is when its `rate_limits` were last refreshed. Filled in by the store.
    var lastAPIResponseAt: Date? = nil

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

        return ClaudeStatusLineSnapshot(
            receivedAt: Date(timeIntervalSince1970: receivedAt),
            configDir: normalizedConfigDir(root["config_dir"] as? String),
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            sessionID: payload["session_id"] as? String,
            transcriptPath: payload["transcript_path"] as? String
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
    private let inspector: ClaudeTranscriptInspector

    static var defaultDirectory: URL {
        ClaudeStatusLineInstaller.defaultBaseDirectory.appendingPathComponent("snapshots", isDirectory: true)
    }

    init(
        directory: URL = ClaudeStatusLineSnapshotStore.defaultDirectory,
        inspector: ClaudeTranscriptInspector = .shared
    ) {
        self.directory = directory
        self.inspector = inspector
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
            .map(withTranscriptEvidence)
    }

    private func withTranscriptEvidence(_ snapshot: ClaudeStatusLineSnapshot) -> ClaudeStatusLineSnapshot {
        guard let path = snapshot.transcriptPath,
              let evidence = inspector.sessionEvidence(forTranscriptAt: path) else {
            return snapshot
        }
        var enriched = snapshot
        enriched.sessionOrganizationUUID = evidence.organizationUUID
        enriched.lastAPIResponseAt = evidence.lastAssistantAt
        return enriched
    }
}

// MARK: - Transcript evidence

struct ClaudeTranscriptEvidence: Equatable, Sendable {
    var organizationUUID: String?
    var lastAssistantAt: Date?
}

/// Reads a Claude Code session transcript (JSONL) for the two facts the
/// statusline payload lacks:
/// - `{"type":"attachment","attachment":{"type":"credential_org","organizationUuid":…}}`,
///   which Claude Code writes when a session starts and whenever its credential org changes;
/// - the timestamp of the last `"type":"assistant"` message, i.e. the last API response.
/// Files are scanned incrementally (only appended complete lines), so a poll
/// re-reads only what was written since the previous one.
final class ClaudeTranscriptInspector: @unchecked Sendable {
    static let shared = ClaudeTranscriptInspector()

    private struct ScanState {
        var offset: UInt64 = 0
        var fileNumber: UInt64?
        var evidence = ClaudeTranscriptEvidence()
    }

    private let lock = NSLock()
    private var states: [String: ScanState] = [:]

    private static let credentialMarker = Data(#""credential_org""#.utf8)
    private static let assistantMarker = Data(#""type":"assistant""#.utf8)

    /// Evidence for a whole session: the main transcript plus its subagent transcripts
    /// (`<transcript without .jsonl>/subagents/*.jsonl`), whose API responses also
    /// refresh the session's rate limits. The org comes from the main transcript.
    func sessionEvidence(forTranscriptAt path: String) -> ClaudeTranscriptEvidence? {
        guard var combined = evidence(forTranscriptAt: path) else { return nil }
        let subagents = URL(fileURLWithPath: path).deletingPathExtension().appendingPathComponent("subagents")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: subagents.path)) ?? []
        for name in names where name.hasSuffix(".jsonl") {
            guard let sub = evidence(forTranscriptAt: subagents.appendingPathComponent(name).path) else { continue }
            if combined.organizationUUID == nil { combined.organizationUUID = sub.organizationUUID }
            if let at = sub.lastAssistantAt, at > (combined.lastAssistantAt ?? .distantPast) {
                combined.lastAssistantAt = at
            }
        }
        return combined
    }

    func evidence(forTranscriptAt path: String) -> ClaudeTranscriptEvidence? {
        lock.lock()
        defer { lock.unlock() }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            states[path] = nil
            return nil
        }
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value

        var state = states[path] ?? ScanState(fileNumber: fileNumber)
        if size < state.offset || state.fileNumber != fileNumber {
            state = ScanState(fileNumber: fileNumber)
        }

        if size > state.offset, let handle = FileHandle(forReadingAtPath: path) {
            defer { try? handle.close() }
            try? handle.seek(toOffset: state.offset)
            let data = (try? handle.readToEnd()) ?? Data()
            // A line still being written is consumed on a later poll.
            if let lastNewline = data.lastIndex(of: 0x0A) {
                let complete = data[data.startIndex...lastNewline]
                for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                    Self.scan(line, into: &state.evidence)
                }
                state.offset += UInt64(complete.count)
            }
        }

        states[path] = state
        return state.evidence
    }

    private static func scan(_ line: Data.SubSequence, into evidence: inout ClaudeTranscriptEvidence) {
        let hasCredential = line.range(of: credentialMarker) != nil
        let hasAssistant = line.range(of: assistantMarker) != nil
        guard hasCredential || hasAssistant,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
            return
        }
        if let attachment = object["attachment"] as? [String: Any],
           attachment["type"] as? String == "credential_org",
           let org = attachment["organizationUuid"] as? String {
            evidence.organizationUUID = org
        }
        if object["type"] as? String == "assistant",
           let raw = object["timestamp"] as? String,
           let timestamp = DateUtils.parseISO8601(raw) {
            evidence.lastAssistantAt = max(evidence.lastAssistantAt ?? timestamp, timestamp)
        }
    }
}
