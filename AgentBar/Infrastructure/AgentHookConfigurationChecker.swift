import Foundation

struct AgentHookSourceStatus: Equatable {
    let isConfigured: Bool
    let detail: String
}

struct AgentHookConfigurationStatus: Equatable {
    let codex: AgentHookSourceStatus
    let claude: AgentHookSourceStatus
    var claudeStatusLine = AgentHookSourceStatus(isConfigured: false, detail: "Not checked yet.")
    let checkedAt: Date

    static let unknown = AgentHookConfigurationStatus(
        codex: AgentHookSourceStatus(
            isConfigured: false,
            detail: "Not checked yet."
        ),
        claude: AgentHookSourceStatus(
            isConfigured: false,
            detail: "Not checked yet."
        ),
        checkedAt: .distantPast
    )
}

struct AgentHookConfigurationChecker {
    private let fileManager: FileManager
    private let codexConfigURL: URL
    private let claudeConfigURLs: [URL]
    private let statusLineInstaller: ClaudeStatusLineInstaller?
    private let claudeAccounts: [ClaudeAccount]?

    init(
        fileManager: FileManager = .default,
        codexConfigURL: URL? = nil,
        claudeConfigURLs: [URL]? = nil,
        statusLineInstaller: ClaudeStatusLineInstaller? = ClaudeStatusLineInstaller(),
        claudeAccounts: [ClaudeAccount]? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.fileManager = fileManager
        self.codexConfigURL = codexConfigURL ?? home.appendingPathComponent(".codex/config.toml")
        self.claudeConfigURLs = claudeConfigURLs ?? [
            home.appendingPathComponent(".claude/settings.json"),
            home.appendingPathComponent(".claude/hooks/config.json")
        ]
        self.statusLineInstaller = statusLineInstaller
        self.claudeAccounts = claudeAccounts
    }

    func check(now: Date = Date()) -> AgentHookConfigurationStatus {
        AgentHookConfigurationStatus(
            codex: checkCodexConfig(),
            claude: checkClaudeConfig(),
            claudeStatusLine: checkClaudeStatusLine(),
            checkedAt: now
        )
    }

    /// Reports AgentBar's statusline wrapper per configured Claude account,
    /// including when another tool (e.g. Orca) replaced it.
    private func checkClaudeStatusLine() -> AgentHookSourceStatus {
        guard let installer = statusLineInstaller else {
            return AgentHookSourceStatus(isConfigured: false, detail: "Not checked.")
        }
        let accounts = claudeAccounts ?? ClaudeAccountStore.load()
        let states = accounts.map { account -> (String, ClaudeStatusLineInstaller.State) in
            let name = account.resolvedConfigDir.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "~/.claude"
            return (name, installer.state(configDir: account.resolvedConfigDir))
        }
        let detail = states.map { name, state in
            switch state {
            case .installed: return "\(name): installed"
            case .notInstalled: return "\(name): not installed"
            case .replaced: return "\(name): replaced by another statusLine command, install again"
            case .wrapperMissing: return "\(name): wrapper script missing, install again"
            case .settingsUnreadable: return "\(name): settings.json unreadable"
            }
        }.joined(separator: "; ")
        return AgentHookSourceStatus(
            isConfigured: !states.isEmpty && states.allSatisfy { $0.1 == .installed },
            detail: detail
        )
    }

    private func checkCodexConfig() -> AgentHookSourceStatus {
        guard fileManager.fileExists(atPath: codexConfigURL.path) else {
            return AgentHookSourceStatus(
                isConfigured: false,
                detail: "Codex config file not found."
            )
        }

        guard let content = try? String(contentsOf: codexConfigURL, encoding: .utf8) else {
            return AgentHookSourceStatus(
                isConfigured: false,
                detail: "Codex config exists but could not be read."
            )
        }

        let lines = content.components(separatedBy: .newlines)
        let firstTableIndex = lines.firstIndex { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
        } ?? lines.count
        let topLevelContent = lines.prefix(firstTableIndex).joined(separator: "\n")

        let hasNotifySetting = topLevelContent.range(
            of: #"(?m)^\s*notify\s*="#,
            options: .regularExpression
        ) != nil
        let hasAgentBarCommand = topLevelContent.contains("agentbar-codex-hook.sh")
            || topLevelContent.contains(".agentbar/events.sock")
            || topLevelContent.contains("AGENTBAR_SOCKET")

        if hasNotifySetting && hasAgentBarCommand {
            return AgentHookSourceStatus(
                isConfigured: true,
                detail: "Codex notify hook is configured for AgentBar."
            )
        }

        if hasNotifySetting {
            return AgentHookSourceStatus(
                isConfigured: false,
                detail: "Codex notify is configured, but AgentBar hook was not detected."
            )
        }

        return AgentHookSourceStatus(
            isConfigured: false,
            detail: "Codex notify hook is not configured."
        )
    }

    private func checkClaudeConfig() -> AgentHookSourceStatus {
        var readableConfigs: [String] = []
        for url in claudeConfigURLs where fileManager.fileExists(atPath: url.path) {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                readableConfigs.append(content)
            }
        }

        guard !readableConfigs.isEmpty else {
            return AgentHookSourceStatus(
                isConfigured: false,
                detail: "Claude hook config file was not found."
            )
        }

        let mergedContent = readableConfigs.joined(separator: "\n")
        let hasAgentBarCommand = mergedContent.contains("agentbar-hook.sh")
            || mergedContent.contains("claude-hook-notify-bridge.sh")
            || mergedContent.contains(".agentbar/events.sock")
            || mergedContent.contains("AGENTBAR_CLAUDE_HOOK_LOG")
            || mergedContent.contains(".claude/agentbar/hook-events.jsonl")

        if hasAgentBarCommand {
            return AgentHookSourceStatus(
                isConfigured: true,
                detail: "Claude hook command is configured for AgentBar."
            )
        }

        return AgentHookSourceStatus(
            isConfigured: false,
            detail: "Claude hooks exist, but AgentBar command was not detected."
        )
    }
}
