import CryptoKit
import Foundation

/// Installs AgentBar's Claude Code `statusLine` wrapper into a config dir's
/// `settings.json`. The wrapper saves each statusline payload (which carries
/// `rate_limits`) for `ClaudeUsageProvider`, then runs the original command
/// with the same stdin so Orca or any statusline text keeps working.
///
/// Layout under `baseDirectory` (default `~/Library/Application Support/AgentBar/claude-statusline`):
/// - `statusline-wrapper.sh`        the wrapper script
/// - `originals/<key>.json|.cmd`    the replaced `statusLine` object and its command
/// - `snapshots/<key>.json`         payloads written by the wrapper
///
/// The settings command never names Orca's `agent-hooks/claude-statusline.*`
/// script, so Orca classifies it as a user command and leaves it alone.
struct ClaudeStatusLineInstaller {
    enum State: Equatable {
        case notInstalled
        case installed
        /// Our wrapper was installed but `statusLine` now holds another command.
        case replaced
        /// `statusLine` points at the wrapper but the script file is gone.
        case wrapperMissing
        case settingsUnreadable
    }

    enum InstallError: LocalizedError {
        case settingsUnreadable(URL)

        var errorDescription: String? {
            switch self {
            case .settingsUnreadable(let url):
                return "Could not parse \(url.path) as a JSON object."
            }
        }
    }

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentBar/claude-statusline", isDirectory: true)
    }

    let baseDirectory: URL
    let backupRoot: URL
    let homeDirectory: URL
    private let now: () -> Date
    private let fileManager = FileManager.default

    init(
        baseDirectory: URL = ClaudeStatusLineInstaller.defaultBaseDirectory,
        backupRoot: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: @escaping () -> Date = { Date() }
    ) {
        self.baseDirectory = baseDirectory
        self.backupRoot = backupRoot ?? homeDirectory.appendingPathComponent(".agentbar/backups", isDirectory: true)
        self.homeDirectory = homeDirectory
        self.now = now
    }

    var wrapperURL: URL { baseDirectory.appendingPathComponent("statusline-wrapper.sh") }
    private var originalsDirectory: URL { baseDirectory.appendingPathComponent("originals", isDirectory: true) }

    /// `configDir` is `ClaudeAccount.resolvedConfigDir`: nil for the default login.
    func settingsURL(configDir: String?) -> URL {
        let dir = configDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        return dir.appendingPathComponent("settings.json")
    }

    /// The file actually edited. Config dirs may share one settings.json through a
    /// symlink (e.g. `~/.claude-2/settings.json -> ~/.claude/settings.json`); writing
    /// the target keeps the link, and keying originals by it wraps the file once.
    private func resolvedSettingsURL(configDir: String?) -> URL {
        settingsURL(configDir: configDir).resolvingSymlinksInPath()
    }

    func originalCommandURL(configDir: String?) -> URL {
        originalsDirectory.appendingPathComponent("\(key(for: configDir)).cmd")
    }

    private func originalStatusLineURL(configDir: String?) -> URL {
        originalsDirectory.appendingPathComponent("\(key(for: configDir)).json")
    }

    func wrapperCommand(configDir: String?) -> String {
        "/bin/sh \(Self.shellQuoted(wrapperURL.path)) \(Self.shellQuoted(originalCommandURL(configDir: configDir).path))"
    }

    // MARK: - State

    func state(configDir: String?) -> State {
        guard let settings = try? readSettings(configDir: configDir) else { return .settingsUnreadable }
        if currentCommand(in: settings) == wrapperCommand(configDir: configDir) {
            return fileManager.fileExists(atPath: wrapperURL.path) ? .installed : .wrapperMissing
        }
        if fileManager.fileExists(atPath: originalStatusLineURL(configDir: configDir).path) {
            return .replaced
        }
        return .notInstalled
    }

    // MARK: - Install / Uninstall

    func install(configDir: String?) throws {
        try writeWrapperScript()
        var settings = try readSettings(configDir: configDir)
        let wrapper = wrapperCommand(configDir: configDir)
        guard currentCommand(in: settings) != wrapper else { return }

        // Remember the command we replace so uninstall can restore it.
        let original = settings["statusLine"]
        try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        let record: [String: Any] = original.map { ["statusLine": $0] } ?? [:]
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            .write(to: originalStatusLineURL(configDir: configDir), options: .atomic)
        let commandURL = originalCommandURL(configDir: configDir)
        if let command = currentCommand(in: settings), !command.isEmpty {
            try Data(command.utf8).write(to: commandURL, options: .atomic)
        } else {
            try? fileManager.removeItem(at: commandURL)
        }

        var statusLine = (original as? [String: Any]) ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = wrapper
        settings["statusLine"] = statusLine
        try writeSettings(settings, configDir: configDir)
    }

    func uninstall(configDir: String?) throws {
        let recordURL = originalStatusLineURL(configDir: configDir)
        var settings = try readSettings(configDir: configDir)

        // Only restore when the wrapper is still in place; a command another tool
        // wrote since then is left alone.
        if currentCommand(in: settings) == wrapperCommand(configDir: configDir) {
            let record = (try? Data(contentsOf: recordURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            if let original = record["statusLine"] {
                settings["statusLine"] = original
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeSettings(settings, configDir: configDir)
        }

        try? fileManager.removeItem(at: recordURL)
        try? fileManager.removeItem(at: originalCommandURL(configDir: configDir))
        let remaining = (try? fileManager.contentsOfDirectory(atPath: originalsDirectory.path)) ?? []
        if remaining.filter({ $0.hasSuffix(".json") }).isEmpty {
            try? fileManager.removeItem(at: wrapperURL)
        }
    }

    // MARK: - Settings I/O

    private func readSettings(configDir: String?) throws -> [String: Any] {
        let url = resolvedSettingsURL(configDir: configDir)
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.settingsUnreadable(url)
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any], configDir: String?) throws {
        let url = resolvedSettingsURL(configDir: configDir)
        try backup(url)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    /// Copies `url` to `<backupRoot>/<UTC timestamp>/<absolute path>` like
    /// `scripts/install-agent-hooks.sh`, never overwriting an earlier backup.
    private func backup(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = formatter.string(from: now())

        var attempt = 0
        var target: URL
        repeat {
            let folder = attempt == 0 ? stamp : "\(stamp)-\(attempt)"
            target = backupRoot.appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(String(url.path.drop { $0 == "/" }))
            attempt += 1
        } while fileManager.fileExists(atPath: target.path)

        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: url, to: target)
    }

    private func currentCommand(in settings: [String: Any]) -> String? {
        (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    private func writeWrapperScript() throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let existing = try? String(contentsOf: wrapperURL, encoding: .utf8)
        if existing != Self.wrapperScript {
            try Data(Self.wrapperScript.utf8).write(to: wrapperURL, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
    }

    /// Keyed by the resolved settings file, so config dirs sharing one file share one record.
    private func key(for configDir: String?) -> String {
        let path = resolvedSettingsURL(configDir: configDir).path
        if path == resolvedSettingsURL(configDir: nil).path { return "default" }
        return SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(12)
            .description
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Wrapper script

    /// POSIX sh, no jq. Buffers stdin so the original command receives the
    /// identical bytes, saves payloads that contain `rate_limits` atomically
    /// (tmp + mv), then runs the original command and exits with its status.
    /// Only `date`, `mv` (and `cksum`/`sed` for a custom config dir) are spawned
    /// besides the original command, keeping the per-refresh overhead small.
    static let wrapperScript = #"""
#!/bin/sh
# AgentBar Claude Code statusLine wrapper. Managed by AgentBar; reinstalling overwrites it.
# statusLine.command: /bin/sh '<this file>' '<file holding the original statusLine command>'
# Saves the payload for AgentBar's usage poll, then runs the original command with the
# identical stdin and passes its stdout and exit status through.

agentbar_original=${1-}
agentbar_dir=${0%/*}

# Command substitution drops trailing newlines; the sentinel keeps the bytes identical.
agentbar_payload=$(cat; printf x)
agentbar_payload=${agentbar_payload%x}

case $agentbar_payload in
  *'"rate_limits"'*)
    (
      agentbar_snapshots="$agentbar_dir/snapshots"
      [ -d "$agentbar_snapshots" ] || mkdir -p "$agentbar_snapshots" || exit 0
      agentbar_config=${CLAUDE_CONFIG_DIR-}
      agentbar_escaped=$agentbar_config
      if [ -z "$agentbar_config" ]; then
        agentbar_key=default
      else
        agentbar_key=$(printf '%s' "$agentbar_config" | cksum)
        agentbar_key=${agentbar_key%% *}
        case $agentbar_config in
          *'"'*|*'\'*)
            agentbar_escaped=$(printf '%s' "$agentbar_config" | sed 's/\\/\\\\/g; s/"/\\"/g') ;;
        esac
      fi
      agentbar_tmp="$agentbar_snapshots/.$agentbar_key.$$.tmp"
      if printf '{"version":1,"received_at":%s,"config_dir":"%s","payload":%s}\n' \
        "$(date +%s)" "$agentbar_escaped" "$agentbar_payload" >"$agentbar_tmp"; then
        mv -f "$agentbar_tmp" "$agentbar_snapshots/$agentbar_key.json" || rm -f "$agentbar_tmp"
      else
        rm -f "$agentbar_tmp"
      fi
    ) >/dev/null 2>&1
    ;;
esac

if [ -n "$agentbar_original" ] && [ -r "$agentbar_original" ]; then
  printf '%s' "$agentbar_payload" | /bin/sh "$agentbar_original"
  exit $?
fi
exit 0

"""#
}
