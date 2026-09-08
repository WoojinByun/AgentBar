import Foundation

enum NotificationSoundMode: String, CaseIterable, Sendable {
    case system
    case mute

    static let defaultsKey = "notificationSoundMode"

    static func resolve(from defaults: UserDefaults) -> NotificationSoundMode {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = NotificationSoundMode(rawValue: rawValue) else {
            return .system
        }
        return mode
    }
}

enum CopilotCredentialSettings {
    /// Enables Keychain fallback for Copilot when gh CLI token is unavailable.
    static let manualPATEnabledKey = "copilotManualPATEnabled"
    /// One-time marker for migrating pre-flag users who already saved a Copilot PAT.
    static let legacyManualPATMigrationCheckedKey = "copilotManualPATMigrationChecked"

    static func isManualPATEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: manualPATEnabledKey, defaultValue: false)
    }

    /// Backward compatibility for users from builds that saved Copilot PAT
    /// in Keychain before `copilotManualPATEnabled` existed.
    static func migrateLegacyManualPATIfNeeded(
        in defaults: UserDefaults,
        loadSavedToken: (String) -> String? = { account in
            KeychainManager.load(account: account)
        }
    ) {
        guard !defaults.bool(forKey: legacyManualPATMigrationCheckedKey, defaultValue: false) else {
            return
        }

        if !isManualPATEnabled(in: defaults),
           loadSavedToken(ServiceType.copilot.keychainAccount) != nil {
            defaults.set(true, forKey: manualPATEnabledKey)
        }

        defaults.set(true, forKey: legacyManualPATMigrationCheckedKey)
    }
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else { return defaultValue }
        return bool(forKey: key)
    }
}

extension String {
    func capitalizingFirstCharacter() -> String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst()
    }
}
