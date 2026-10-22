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

        // Remember the command we replace so uninstall can restore it, including the
        // exact original text of the value so the file comes back byte for byte.
        let original = settings["statusLine"]
        var record: [String: Any] = [:]
        record["statusLine"] = original
        if let bytes = rawSettings(configDir: configDir),
           let range = JSONTopLevelEditor.valueRange(of: "statusLine", in: bytes) {
            record["raw"] = String(decoding: bytes[range], as: UTF8.self)
        }
        try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
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
        try writeSettings(settings, configDir: configDir, edit: .install(command: wrapper))
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
                try writeSettings(settings, configDir: configDir, edit: .restore(raw: record["raw"] as? String))
            } else {
                settings.removeValue(forKey: "statusLine")
                try writeSettings(settings, configDir: configDir, edit: .remove)
            }
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

    private func rawSettings(configDir: String?) -> [UInt8]? {
        (try? Data(contentsOf: resolvedSettingsURL(configDir: configDir))).map { Array($0) }
    }

    private enum StatusLineEdit {
        /// Replace only the `command` string inside the existing statusLine object.
        case install(command: String)
        /// Put back the original value text recorded at install time.
        case restore(raw: String?)
        /// Remove the statusLine member (there was none before install).
        case remove
    }

    /// Writes `settings` (the current file with only `statusLine` changed) by
    /// editing just the top-level `statusLine` member in place, so key order,
    /// indentation, spacing and the trailing newline stay byte-for-byte.
    /// Each candidate edit is parsed back and must equal `settings`.
    /// Fallback: if the scanner cannot handle the file (e.g. duplicate keys) or no
    /// candidate validates, the whole file is rewritten with sorted keys and
    /// pretty printing as before. A backup is taken first in both cases.
    private func writeSettings(_ settings: [String: Any], configDir: String?, edit: StatusLineEdit) throws {
        let url = resolvedSettingsURL(configDir: configDir)
        let permissions = (try? fileManager.attributesOfItem(atPath: url.path))?[.posixPermissions]
        try backup(url)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let data = try minimalEdit(of: rawSettings(configDir: configDir), to: settings, edit: edit)
            ?? fullRewrite(settings)
        try data.write(to: url, options: .atomic)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private func minimalEdit(of bytes: [UInt8]?, to settings: [String: Any], edit: StatusLineEdit) -> Data? {
        guard let bytes else { return nil }
        let statusLine = settings["statusLine"] as? [String: Any]
        var candidates: [() -> [UInt8]?] = []
        switch edit {
        case .install(let command):
            candidates.append {
                guard let range = JSONTopLevelEditor.valueRange(of: "statusLine", in: bytes),
                      let value = JSONTopLevelEditor.replacingStringMember(
                          "command", with: command, inObject: Array(bytes[range])
                      ) else { return nil }
                return JSONTopLevelEditor.settingValue(value, forKey: "statusLine", in: bytes)
            }
        case .restore(let raw):
            if let raw {
                candidates.append { JSONTopLevelEditor.settingValue(Array(raw.utf8), forKey: "statusLine", in: bytes) }
            }
        case .remove:
            candidates.append { JSONTopLevelEditor.removingMember("statusLine", in: bytes) }
        }
        if let statusLine {
            candidates.append { JSONTopLevelEditor.settingGeneratedObject(statusLine, forKey: "statusLine", in: bytes) }
        }

        let intended = settings as NSDictionary
        for candidate in candidates {
            guard let edited = candidate(),
                  let parsed = try? JSONSerialization.jsonObject(with: Data(edited)) as? NSDictionary,
                  parsed.isEqual(intended) else { continue }
            return Data(edited)
        }
        return nil
    }

    private func fullRewrite(_ settings: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
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

// MARK: - Top-level JSON member editor

/// Scans a JSON object at byte level to find and splice one top-level member,
/// leaving every other byte of the file untouched. It assumes the text already
/// parses with JSONSerialization; callers validate every result by parsing it again.
/// Returns nil whenever the shape is unexpected (not an object, duplicate target key,
/// unknown tokens), so callers fall back to a full rewrite.
enum JSONTopLevelEditor {
    struct Member {
        let key: String
        let keyStart: Int
        let keyEnd: Int
        let valueStart: Int
        let valueEnd: Int
    }

    struct Layout {
        let open: Int
        let close: Int
        let members: [Member]
    }

    private static let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
    private static let openBrace = UInt8(ascii: "{"), closeBrace = UInt8(ascii: "}")
    private static let openBracket = UInt8(ascii: "["), closeBracket = UInt8(ascii: "]")
    private static let comma = UInt8(ascii: ","), colon = UInt8(ascii: ":")
    private static let newline = UInt8(ascii: "\n")

    static func layout(_ b: [UInt8]) -> Layout? {
        var i = b.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        skipWhitespace(b, &i)
        guard i < b.count, b[i] == openBrace else { return nil }
        let open = i
        i += 1
        var members: [Member] = []
        skipWhitespace(b, &i)
        var close: Int
        if i < b.count, b[i] == closeBrace {
            close = i
        } else {
            while true {
                skipWhitespace(b, &i)
                let keyStart = i
                guard skipString(b, &i) else { return nil }
                let keyEnd = i
                guard let key = try? JSONSerialization.jsonObject(
                    with: Data(b[keyStart..<keyEnd]), options: .fragmentsAllowed
                ) as? String else { return nil }
                skipWhitespace(b, &i)
                guard i < b.count, b[i] == colon else { return nil }
                i += 1
                skipWhitespace(b, &i)
                let valueStart = i
                guard skipValue(b, &i) else { return nil }
                members.append(Member(key: key, keyStart: keyStart, keyEnd: keyEnd, valueStart: valueStart, valueEnd: i))
                skipWhitespace(b, &i)
                guard i < b.count else { return nil }
                if b[i] == comma { i += 1; continue }
                guard b[i] == closeBrace else { return nil }
                close = i
                break
            }
        }
        i = close + 1
        skipWhitespace(b, &i)
        guard i == b.count else { return nil }
        return Layout(open: open, close: close, members: members)
    }

    /// Byte range of the value of top-level `key`; nil if absent, duplicated or unscannable.
    static func valueRange(of key: String, in bytes: [UInt8]) -> Range<Int>? {
        guard let layout = layout(bytes) else { return nil }
        let matches = layout.members.filter { $0.key == key }
        guard matches.count == 1 else { return nil }
        return matches[0].valueStart..<matches[0].valueEnd
    }

    /// Replaces the value of `key`, or appends a new member after the last one using
    /// that member's leading whitespace and key/value separator.
    static func settingValue(_ value: [UInt8], forKey key: String, in b: [UInt8]) -> [UInt8]? {
        guard let layout = layout(b) else { return nil }
        let matches = layout.members.filter { $0.key == key }
        guard matches.count <= 1 else { return nil }
        if let member = matches.first {
            return Array(b[..<member.valueStart]) + value + Array(b[member.valueEnd...])
        }
        let keyToken = Array(jsonString(key).utf8)
        guard let last = layout.members.last else {
            // Empty object: `{}` -> `{"key": value}`; removal restores `{}` exactly.
            return Array(b[...layout.open]) + keyToken + Array(": ".utf8) + value + Array(b[(layout.open + 1)...])
        }
        let style = memberStyle(of: layout, in: b)
        let insertion = [comma] + style.gap + keyToken + style.separator + value
        return Array(b[..<last.valueEnd]) + insertion + Array(b[last.valueEnd...])
    }

    /// Like `settingValue`, with the object serialized to match the file's style:
    /// multi-line with the file's indent unit when the file is multi-line, else compact.
    static func settingGeneratedObject(_ object: [String: Any], forKey key: String, in b: [UInt8]) -> [UInt8]? {
        guard let layout = layout(b) else { return nil }
        let style = memberStyle(of: layout, in: b)
        guard let value = encodeObject(object, style: style) else { return nil }
        return settingValue(Array(value.utf8), forKey: key, in: b)
    }

    /// Removes member `key` with its comma, so `settingValue`'s insertion is undone exactly.
    static func removingMember(_ key: String, in b: [UInt8]) -> [UInt8]? {
        guard let layout = layout(b) else { return nil }
        let indices = layout.members.indices.filter { layout.members[$0].key == key }
        guard indices.count == 1, let index = indices.first else { return nil }
        let member = layout.members[index]
        let range: Range<Int>
        if layout.members.count == 1 {
            range = member.keyStart..<member.valueEnd
        } else if index == layout.members.count - 1 {
            range = layout.members[index - 1].valueEnd..<member.valueEnd
        } else {
            range = member.keyStart..<layout.members[index + 1].keyStart
        }
        return Array(b[..<range.lowerBound]) + Array(b[range.upperBound...])
    }

    /// Replaces the string value of `key` inside a JSON object text.
    static func replacingStringMember(_ key: String, with string: String, inObject b: [UInt8]) -> [UInt8]? {
        guard let layout = layout(b) else { return nil }
        let matches = layout.members.filter { $0.key == key }
        guard matches.count == 1, let member = matches.first, b[member.valueStart] == quote else { return nil }
        return Array(b[..<member.valueStart]) + Array(jsonString(string).utf8) + Array(b[member.valueEnd...])
    }

    // MARK: Style

    struct MemberStyle {
        /// Whitespace before a member key (e.g. "\n  "), copied from the last member.
        let gap: [UInt8]
        /// Bytes between a key and its value (e.g. ": ").
        let separator: [UInt8]
        let indent: String
        let multiline: Bool
    }

    private static func memberStyle(of layout: Layout, in b: [UInt8]) -> MemberStyle {
        guard let last = layout.members.last else {
            return MemberStyle(gap: [], separator: Array(": ".utf8), indent: "", multiline: false)
        }
        let index = layout.members.count - 1
        let gapStart = index == 0 ? layout.open + 1 : (b[layout.members[index - 1].valueEnd..<last.keyStart].firstIndex(of: comma) ?? layout.members[index - 1].valueEnd) + 1
        let gap = Array(b[gapStart..<last.keyStart])
        let indentBytes = gap.lastIndex(of: newline).map { Array(gap[($0 + 1)...]) } ?? []
        return MemberStyle(
            gap: gap,
            separator: Array(b[last.keyEnd..<last.valueStart]),
            indent: String(decoding: indentBytes, as: UTF8.self),
            multiline: gap.contains(newline)
        )
    }

    /// `type` and `command` first, then the remaining keys sorted.
    private static func encodeObject(_ object: [String: Any], style: MemberStyle) -> String? {
        let order = ["type", "command"].filter { object[$0] != nil } + object.keys.filter { $0 != "type" && $0 != "command" }.sorted()
        let separator = String(decoding: style.separator, as: UTF8.self)
        var entries: [String] = []
        for key in order {
            guard let value = encodeValue(object[key]!) else { return nil }
            entries.append(jsonString(key) + separator + value)
        }
        guard style.multiline else { return "{" + entries.joined(separator: ",") + "}" }
        let unit = style.indent.isEmpty ? "  " : style.indent
        let inner = entries.map { style.indent + unit + $0 }.joined(separator: ",\n")
        return "{\n" + inner + "\n" + style.indent + "}"
    }

    private static func encodeValue(_ value: Any) -> String? {
        if let string = value as? String { return jsonString(string) }
        guard let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func jsonString(_ string: String) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]
        )) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Scanning

    private static func skipWhitespace(_ b: [UInt8], _ i: inout Int) {
        while i < b.count, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 }
    }

    private static func skipString(_ b: [UInt8], _ i: inout Int) -> Bool {
        guard i < b.count, b[i] == quote else { return false }
        i += 1
        while i < b.count {
            switch b[i] {
            case backslash: i += 2
            case quote: i += 1; return true
            case 0x00..<0x20: return false
            default: i += 1
            }
        }
        return false
    }

    /// Skips one value. Nested objects and arrays are matched by depth, skipping strings,
    /// which is sound because the input is known to be valid JSON.
    private static func skipValue(_ b: [UInt8], _ i: inout Int) -> Bool {
        guard i < b.count else { return false }
        switch b[i] {
        case quote:
            return skipString(b, &i)
        case openBrace, openBracket:
            var depth = 0
            while i < b.count {
                switch b[i] {
                case quote:
                    guard skipString(b, &i) else { return false }
                    continue
                case openBrace, openBracket:
                    depth += 1
                case closeBrace, closeBracket:
                    depth -= 1
                    if depth == 0 { i += 1; return true }
                default:
                    break
                }
                i += 1
            }
            return false
        default:
            let start = i
            while i < b.count, ![comma, closeBrace, closeBracket, 0x20, 0x0A, 0x0D, 0x09].contains(b[i]) { i += 1 }
            return i > start
        }
    }
}
