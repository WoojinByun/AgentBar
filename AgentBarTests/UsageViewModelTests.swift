import XCTest
import Security
@testable import AgentBar

@MainActor
final class UsageViewModelTests: XCTestCase {

    func testFetchAllUsageWithMultipleProviders() async {
        let mockClaude = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )
        let mockCodex = MockUsageProvider(
            serviceType: .codex,
            result: .success(UsageData.mock(service: .codex))
        )

        let vm = UsageViewModel(providers: [mockClaude, mockCodex])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 2)
        XCTAssertEqual(vm.usageData[0].service, .claude)
        XCTAssertEqual(vm.usageData[1].service, .codex)
    }

    func testProviderFailureReturnsZeroUsage() async {
        let failProvider = MockUsageProvider(
            serviceType: .codex,
            result: .failure(APIError.unauthorized)
        )
        let successProvider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )

        let vm = UsageViewModel(providers: [failProvider, successProvider])
        await vm.fetchAllUsage()

        // Both show: successful provider + zero-usage fallback for failed provider
        XCTAssertEqual(vm.usageData.count, 2)
        let codexData = vm.usageData.first { $0.service == .codex }
        XCTAssertNotNil(codexData)
        XCTAssertEqual(codexData!.fiveHourUsage.used, 0)
    }

    func testAllFailuresStillShowBars() async {
        let failProvider = MockUsageProvider(
            serviceType: .claude,
            result: .failure(APIError.noData)
        )

        let vm = UsageViewModel(providers: [failProvider])
        await vm.fetchAllUsage()

        // Failed provider still returns a zero-usage entry
        XCTAssertEqual(vm.usageData.count, 1)
        XCTAssertEqual(vm.usageData.first?.fiveHourUsage.used, 0)
        XCTAssertNil(vm.lastError)
    }

    func testSuccessfulResultsClearsError() async {
        let provider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )

        let vm = UsageViewModel(providers: [provider])
        vm.lastError = "previous error"
        await vm.fetchAllUsage()

        XCTAssertNil(vm.lastError)
    }

    func testServiceOrderIsMaintained() async {
        // Provide in reverse order
        let zai = MockUsageProvider(serviceType: .zai, result: .success(UsageData.mock(service: .zai)))
        let gemini = MockUsageProvider(serviceType: .gemini, result: .success(UsageData.mock(service: .gemini)))
        let claude = MockUsageProvider(serviceType: .claude, result: .success(UsageData.mock(service: .claude)))
        let codex = MockUsageProvider(serviceType: .codex, result: .success(UsageData.mock(service: .codex)))

        let vm = UsageViewModel(providers: [zai, gemini, claude, codex])
        await vm.fetchAllUsage()

        XCTAssertEqual(vm.usageData.count, 4)
        XCTAssertEqual(vm.usageData[0].service, .claude)
        XCTAssertEqual(vm.usageData[1].service, .codex)
        XCTAssertEqual(vm.usageData[2].service, .gemini)
        XCTAssertEqual(vm.usageData[3].service, .zai)
    }

    func testHistoryRecordsOnlySuccessfulProviderResults() async {
        let historyStore = HistoryRecordingStoreSpy()
        let successProvider = MockUsageProvider(
            serviceType: .claude,
            result: .success(UsageData.mock(service: .claude))
        )
        let failProvider = MockUsageProvider(
            serviceType: .codex,
            result: .failure(APIError.noData)
        )

        let vm = UsageViewModel(
            providers: [successProvider, failProvider],
            historyStore: historyStore
        )
        await vm.fetchAllUsage()

        let snapshots = await historyStore.recordedSnapshots()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.count, 1)
        XCTAssertEqual(snapshots.first?.first?.service, .claude)
    }

    func testHistorySkipsRecordingWhenAllProvidersFail() async {
        let historyStore = HistoryRecordingStoreSpy()
        let failProvider = MockUsageProvider(
            serviceType: .codex,
            result: .failure(APIError.noData)
        )

        let vm = UsageViewModel(
            providers: [failProvider],
            historyStore: historyStore
        )
        await vm.fetchAllUsage()

        let snapshots = await historyStore.recordedSnapshots()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testStaleUsageRemainsVisibleButIsNotRecordedAsNewHistory() async {
        let historyStore = HistoryRecordingStoreSpy()
        let stale = UsageData(
            service: .codex,
            fiveHourUsage: .zero,
            weeklyUsage: UsageMetric(used: 100, total: 100, unit: .percent, resetTime: nil),
            lastUpdated: Date(timeIntervalSince1970: 1_000),
            isAvailable: false,
            showsFiveHourUsage: false,
            statusMessage: "Update failed"
        )
        let provider = MockUsageProvider(serviceType: .codex, result: .success(stale))
        let vm = UsageViewModel(providers: [provider], historyStore: historyStore)
        await vm.fetchAllUsage()
        XCTAssertEqual(vm.usageData.first?.weeklyUsage?.used, 100)
        XCTAssertFalse(vm.usageData.first?.isAvailable ?? true)
        let snapshots = await historyStore.recordedSnapshots()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testLegacyCursorPlanBusinessMigratesToTeams() {
        let suiteName = "AgentBarTests.CursorPlanMigration"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("Business", forKey: "cursorPlan")

        let resolvedPlan = CursorPlan.resolveAndMigrateStoredPlan(in: defaults)

        XCTAssertEqual(resolvedPlan, .teams)
        XCTAssertEqual(defaults.string(forKey: "cursorPlan"), CursorPlan.teams.rawValue)
    }

    func testUnknownCursorPlanRawValueFallsBackToProAndPersists() {
        let suiteName = "AgentBarTests.CursorPlanUnknownValueMigration"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("Legacy-Unknown-Plan", forKey: "cursorPlan")

        let resolvedPlan = CursorPlan.resolveAndMigrateStoredPlan(in: defaults)

        XCTAssertEqual(resolvedPlan, .pro)
        XCTAssertEqual(defaults.string(forKey: "cursorPlan"), CursorPlan.pro.rawValue)
    }

    func testPlanEnumsRoundTripAndHaveExpectedCases() {
        XCTAssertEqual(CodexPlan.plus.fiveHourTokenLimit, 1_000_000)
        XCTAssertEqual(CodexPlan.plus.weeklyTokenLimit, 10_000_000)
        XCTAssertEqual(CodexPlan.allCases.first, .plus)
        for plan in CodexPlan.allCases {
            XCTAssertEqual(CodexPlan(rawValue: plan.rawValue), plan)
        }

        let claudeCases = ClaudePlan.allCases
        XCTAssertEqual(claudeCases.count, 5)
        XCTAssertEqual(claudeCases.map(\.rawValue), ["Free", "Pro", "Max 5x", "Max 20x", "Team"])
        for plan in claudeCases {
            XCTAssertEqual(ClaudePlan(rawValue: plan.rawValue), plan)
        }
        XCTAssertNil(ClaudePlan(rawValue: "Max"))
        XCTAssertEqual(ClaudePlan.max5x.rawValue, "Max 5x")
        XCTAssertEqual(ClaudePlan.max20x.rawValue, "Max 20x")
    }

    func testCopilotCapitalizedPlanName() {
        XCTAssertEqual(CopilotUsageProvider.capitalizedPlanName("pro"), "Pro")
        XCTAssertEqual(CopilotUsageProvider.capitalizedPlanName("business"), "Business")
        XCTAssertEqual(CopilotUsageProvider.capitalizedPlanName("enterprise"), "Enterprise")
        XCTAssertEqual(CopilotUsageProvider.capitalizedPlanName(""), "")
    }

    func testZaiCapitalizedPlanName() {
        XCTAssertEqual(ZaiUsageProvider.capitalizedPlanName("max"), "Max")
        XCTAssertEqual(ZaiUsageProvider.capitalizedPlanName("pro"), "Pro")
        XCTAssertEqual(ZaiUsageProvider.capitalizedPlanName(""), "")
    }

    func testSanitizedTokenForSavingRejectsMaskedPlaceholder() {
        XCTAssertNil(SettingsView.sanitizedTokenForSaving("*****"))
        XCTAssertNil(SettingsView.sanitizedTokenForSaving("   ******   "))
        XCTAssertEqual(SettingsView.sanitizedTokenForSaving("  ghp_valid_token  "), "ghp_valid_token")
    }

    func testSaveAPIKeyResultRejectsWhitespaceAndSkipsSave() {
        var didAttemptSave = false

        let result = SettingsView.saveAPIKeyResult("   ", account: "copilot-account") { _, _ in
            didAttemptSave = true
        }

        XCTAssertFalse(didAttemptSave)
        if case .failure(let message) = result {
            XCTAssertEqual(message, "Please enter a valid token before saving.")
        } else {
            XCTFail("Expected failure for whitespace token")
        }
    }

    func testSaveAPIKeyResultSavesTrimmedToken() {
        var savedKey: String?
        var savedAccount: String?

        let result = SettingsView.saveAPIKeyResult("  ghp_valid_token  ", account: "copilot-account") { key, account in
            savedKey = key
            savedAccount = account
        }

        if case .failure(let message) = result {
            XCTFail("Expected success, got failure: \(message)")
        }
        XCTAssertEqual(savedKey, "ghp_valid_token")
        XCTAssertEqual(savedAccount, "copilot-account")
    }

    func testSaveAPIKeyResultReturnsFailureWhenSaveThrows() {
        let result = SettingsView.saveAPIKeyResult("ghp_valid_token", account: "copilot-account") { _, _ in
            throw StubSaveError.keychainUnavailable
        }

        if case .failure(let message) = result {
            XCTAssertEqual(message, "Keychain unavailable")
        } else {
            XCTFail("Expected failure when keychain save throws")
        }
    }

    func testSaveAPIKeyResultReturnsFallbackFailureMessageWhenErrorDescriptionIsBlank() {
        let result = SettingsView.saveAPIKeyResult("ghp_valid_token", account: "copilot-account") { _, _ in
            throw NSError(
                domain: "AgentBarTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "   \n\t"]
            )
        }

        if case .failure(let message) = result {
            XCTAssertEqual(message, "Failed to save token to Keychain.")
        } else {
            XCTFail("Expected fallback failure message when error description is blank")
        }
    }

    func testTokenSaveUIOutcomeOnSuccessMarksSavedAndShowsSuccessAlert() {
        var savedKey: String?
        var savedAccount: String?

        let outcome = SettingsView.tokenSaveUIOutcome(
            currentToken: "  zai_live_key  ",
            hasSavedToken: false,
            account: ServiceType.zai.keychainAccount
        ) { key, account in
            savedKey = key
            savedAccount = account
        }

        XCTAssertTrue(outcome.didSave)
        XCTAssertTrue(outcome.hasSavedToken)
        XCTAssertEqual(outcome.tokenFieldValue, "")
        XCTAssertTrue(outcome.showSavedAlert)
        XCTAssertFalse(outcome.showSaveErrorAlert)
        XCTAssertEqual(outcome.saveErrorMessage, "")
        XCTAssertEqual(savedKey, "zai_live_key")
        XCTAssertEqual(savedAccount, ServiceType.zai.keychainAccount)
    }

    func testTokenSaveUIOutcomeOnFailurePreservesTokenAndShowsErrorAlert() {
        let outcome = SettingsView.tokenSaveUIOutcome(
            currentToken: "ghp_valid_token",
            hasSavedToken: false,
            account: ServiceType.copilot.keychainAccount
        ) { _, _ in
            throw StubSaveError.keychainUnavailable
        }

        XCTAssertFalse(outcome.didSave)
        XCTAssertFalse(outcome.hasSavedToken)
        XCTAssertEqual(outcome.tokenFieldValue, "ghp_valid_token")
        XCTAssertFalse(outcome.showSavedAlert)
        XCTAssertTrue(outcome.showSaveErrorAlert)
        XCTAssertEqual(outcome.saveErrorMessage, "Keychain unavailable")
    }

    func testKeychainSaveStoresInDataProtectionAndCleansLegacyOnSuccess() throws {
        let account = "tests.save.primary"
        let securityAPI = MockKeychainSecurityAPI(
            legacyItems: [account: Data("legacy-token".utf8)]
        )

        try KeychainManager.save(
            key: "new-token",
            account: account,
            securityAPI: securityAPI
        )

        XCTAssertEqual(securityAPI.dataProtectionItems[account], Data("new-token".utf8))
        XCTAssertNil(securityAPI.legacyItems[account])
    }

    func testKeychainSaveUpdatesExistingDataProtectionItemOnDuplicateAdd() throws {
        let account = "tests.save.upsert_update"
        let securityAPI = MockKeychainSecurityAPI(
            dataProtectionItems: [account: Data("original-token".utf8)]
        )

        try KeychainManager.save(
            key: "updated-token",
            account: account,
            securityAPI: securityAPI
        )

        XCTAssertEqual(securityAPI.dataProtectionItems[account], Data("updated-token".utf8))
    }

    func testKeychainSaveFallsBackToLegacyWhenDataProtectionMissingEntitlement() throws {
        let account = "tests.save.fallback"
        let securityAPI = MockKeychainSecurityAPI()
        securityAPI.addStatusByStore[.dataProtection] = errSecMissingEntitlement

        try KeychainManager.save(
            key: "fallback-token",
            account: account,
            securityAPI: securityAPI
        )

        XCTAssertNil(securityAPI.dataProtectionItems[account])
        XCTAssertEqual(securityAPI.legacyItems[account], Data("fallback-token".utf8))
    }

    func testKeychainSaveFailureDoesNotMutateLegacyWhenDataProtectionWriteFails() {
        let account = "tests.save.legacy_non_destructive"
        let legacyValue = Data("legacy-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: legacyValue])
        securityAPI.addStatusByStore[.dataProtection] = errSecInteractionNotAllowed

        XCTAssertThrowsError(
            try KeychainManager.save(
                key: "replacement-token",
                account: account,
                securityAPI: securityAPI
            )
        ) { error in
            guard case KeychainError.saveFailed(let status) = error else {
                return XCTFail("Expected KeychainError.saveFailed")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
        XCTAssertEqual(securityAPI.legacyItems[account], legacyValue)
        XCTAssertNil(securityAPI.dataProtectionItems[account])
    }

    func testKeychainSavePreservesExistingDataProtectionItemWhenUpdateFails() {
        let account = "tests.save.non_destructive"
        let original = Data("original-token".utf8)
        let securityAPI = MockKeychainSecurityAPI(
            dataProtectionItems: [account: original]
        )
        securityAPI.updateStatusByStore[.dataProtection] = errSecInteractionNotAllowed

        XCTAssertThrowsError(
            try KeychainManager.save(
                key: "replacement-token",
                account: account,
                securityAPI: securityAPI
            )
        ) { error in
            guard case KeychainError.saveFailed(let status) = error else {
                return XCTFail("Expected KeychainError.saveFailed")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
        XCTAssertEqual(securityAPI.dataProtectionItems[account], original)
    }

    func testKeychainLoadMigrationBehavior() {
        let account = "tests.migration"
        let tokenData = Data("legacy-token".utf8)

        let successAPI = MockKeychainSecurityAPI(legacyItems: [account: tokenData])
        let loadedSuccess = KeychainManager.load(account: account, securityAPI: successAPI)
        XCTAssertEqual(loadedSuccess, "legacy-token")
        XCTAssertEqual(successAPI.dataProtectionItems[account], tokenData)
        XCTAssertNil(successAPI.legacyItems[account])

        let failAPI = MockKeychainSecurityAPI(legacyItems: [account: tokenData])
        failAPI.addStatusByStore[.dataProtection] = errSecInteractionNotAllowed
        let loadedFail = KeychainManager.load(account: account, securityAPI: failAPI)
        XCTAssertEqual(loadedFail, "legacy-token")
        XCTAssertNil(failAPI.dataProtectionItems[account])
        XCTAssertEqual(failAPI.legacyItems[account], tokenData)
    }

    func testKeychainInProcessCacheCachesStableNotFoundResult() {
        KeychainManager.resetInProcessStateForTesting()
        let account = "tests.cache.notfound.\(UUID().uuidString)"
        let securityAPI = MockKeychainSecurityAPI()

        let first = KeychainManager.load(
            account: account,
            securityAPI: securityAPI,
            useInProcessCache: true
        )
        XCTAssertNil(first)

        securityAPI.legacyItems[account] = Data("late-token".utf8)
        let second = KeychainManager.load(
            account: account,
            securityAPI: securityAPI,
            useInProcessCache: true
        )

        XCTAssertNil(second, "Stable item-not-found should be cached for this process.")
    }

    func testKeychainInProcessCacheSkipsTransientFailures() {
        KeychainManager.resetInProcessStateForTesting()
        let account = "tests.cache.transient.\(UUID().uuidString)"
        let securityAPI = MockKeychainSecurityAPI()
        securityAPI.copyStatusByStore[.dataProtection] = errSecInteractionNotAllowed

        let first = KeychainManager.load(
            account: account,
            securityAPI: securityAPI,
            useInProcessCache: true
        )
        XCTAssertNil(first)

        securityAPI.copyStatusByStore[.dataProtection] = errSecItemNotFound
        securityAPI.legacyItems[account] = Data("available-now".utf8)

        let second = KeychainManager.load(
            account: account,
            securityAPI: securityAPI,
            useInProcessCache: true
        )
        XCTAssertEqual(second, "available-now")
    }

    func testKeychainDeleteRemovesDataProtectionAndLegacyItems() throws {
        let account = "tests.delete.cleanup"
        let tokenData = Data("token".utf8)
        let securityAPI = MockKeychainSecurityAPI(
            dataProtectionItems: [account: tokenData],
            legacyItems: [account: tokenData]
        )

        try KeychainManager.delete(account: account, securityAPI: securityAPI)

        XCTAssertNil(securityAPI.dataProtectionItems[account])
        XCTAssertNil(securityAPI.legacyItems[account])
    }

    func testKeychainDeleteThrowsForUnexpectedLegacyDeleteFailure() {
        let account = "tests.delete.failure"
        let securityAPI = MockKeychainSecurityAPI(legacyItems: [account: Data("token".utf8)])
        securityAPI.deleteStatusByStore[.legacy] = errSecInteractionNotAllowed

        XCTAssertThrowsError(try KeychainManager.delete(account: account, securityAPI: securityAPI)) { error in
            guard case KeychainError.deleteFailed(let status) = error else {
                return XCTFail("Expected KeychainError.deleteFailed")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
    }

    func testKeychainFallbackSaveWorksWithSystemSecurityAPI() throws {
        guard ProcessInfo.processInfo.environment["AGENTBAR_RUN_SYSTEM_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set AGENTBAR_RUN_SYSTEM_KEYCHAIN_TESTS=1 to run system Keychain integration tests.")
        }

        let account = "tests.integration.legacy.\(UUID().uuidString)"
        let token = "integration-token"
        let securityAPI = DataProtectionUnavailableSystemSecurityAPI()

        defer {
            try? KeychainManager.delete(account: account, securityAPI: securityAPI)
        }

        do {
            try KeychainManager.save(key: token, account: account, securityAPI: securityAPI)
        } catch KeychainError.saveFailed(let status)
            where Self.isSkippableSystemKeychainStatus(
                status,
                didAttemptLegacyFallback: securityAPI.legacyWriteAttemptCount > 0
            ) {
            throw XCTSkip("System keychain unavailable in this test environment (status: \(status))")
        }

        XCTAssertEqual(
            securityAPI.dataProtectionAddRejectionCount,
            1,
            "Expected the Data Protection write path to be attempted and rejected once before fallback"
        )
        XCTAssertEqual(
            securityAPI.legacyAddAttemptCount,
            1,
            "Expected exactly one legacy add attempt for a new account"
        )
        XCTAssertEqual(
            securityAPI.legacyUpdateAttemptCount,
            0,
            "Expected no legacy update attempt for a new account"
        )

        let loaded = KeychainManager.load(account: account, securityAPI: securityAPI)
        if loaded == nil {
            let fallbackCopyStatus = securityAPI.copyMatching([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.agentbar.apikeys",
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]).status
            if Self.isSkippableSystemKeychainStatus(
                fallbackCopyStatus,
                didAttemptLegacyFallback: securityAPI.legacyWriteAttemptCount > 0
            ) {
                throw XCTSkip("System keychain unavailable in this test environment (status: \(fallbackCopyStatus))")
            }
        }

        XCTAssertEqual(loaded, token)
    }

    private static func isSkippableSystemKeychainStatus(
        _ status: OSStatus,
        didAttemptLegacyFallback: Bool = false
    ) -> Bool {
        switch status {
        case errSecNotAvailable,
             errSecInteractionNotAllowed,
             errSecAuthFailed,
             errSecNoSuchKeychain:
            true
        case errSecMissingEntitlement:
            didAttemptLegacyFallback
        default:
            false
        }
    }

}

private enum StubSaveError: LocalizedError {
    case keychainUnavailable

    var errorDescription: String? {
        switch self {
        case .keychainUnavailable:
            return "Keychain unavailable"
        }
    }
}

private final class MockKeychainSecurityAPI: KeychainManager.SecurityAPI {
    private let expectedService = "com.agentbar.apikeys"

    enum Store {
        case dataProtection
        case legacy
    }

    var dataProtectionItems: [String: Data]
    var legacyItems: [String: Data]
    var addStatusByStore: [Store: OSStatus] = [:]
    var updateStatusByStore: [Store: OSStatus] = [:]
    var copyStatusByStore: [Store: OSStatus] = [:]
    var deleteStatusByStore: [Store: OSStatus] = [:]

    init(
        dataProtectionItems: [String: Data] = [:],
        legacyItems: [String: Data] = [:]
    ) {
        self.dataProtectionItems = dataProtectionItems
        self.legacyItems = legacyItems
    }

    func add(_ query: [String : Any]) -> OSStatus {
        guard let (store, account) = parse(query) else {
            return errSecParam
        }
        if let compatibilityError = validateAddQueryCompatibility(query, store: store) {
            return compatibilityError
        }
        if let forced = addStatusByStore[store], forced != errSecSuccess {
            return forced
        }
        guard let data = query[kSecValueData as String] as? Data else {
            return errSecParam
        }

        switch store {
        case .dataProtection:
            if dataProtectionItems[account] != nil {
                return errSecDuplicateItem
            }
            dataProtectionItems[account] = data
        case .legacy:
            if legacyItems[account] != nil {
                return errSecDuplicateItem
            }
            legacyItems[account] = data
        }
        return errSecSuccess
    }

    func update(_ query: [String : Any], attributes: [String : Any]) -> OSStatus {
        guard let (store, account) = parse(query) else {
            return errSecParam
        }
        if let compatibilityError = validateUpdateQueryCompatibility(query, attributes: attributes) {
            return compatibilityError
        }
        if let forced = updateStatusByStore[store], forced != errSecSuccess {
            return forced
        }
        guard let data = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }

        switch store {
        case .dataProtection:
            guard dataProtectionItems[account] != nil else {
                return errSecItemNotFound
            }
            dataProtectionItems[account] = data
        case .legacy:
            guard legacyItems[account] != nil else {
                return errSecItemNotFound
            }
            legacyItems[account] = data
        }
        return errSecSuccess
    }

    func copyMatching(_ query: [String : Any]) -> (status: OSStatus, data: Data?) {
        guard let (store, account) = parse(query) else {
            return (errSecParam, nil)
        }
        if let compatibilityError = validateCopyQueryCompatibility(query) {
            return (compatibilityError, nil)
        }
        if let forced = copyStatusByStore[store], forced != errSecSuccess {
            return (forced, nil)
        }

        switch store {
        case .dataProtection:
            guard let data = dataProtectionItems[account] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data)
        case .legacy:
            guard let data = legacyItems[account] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data)
        }
    }

    func delete(_ query: [String : Any]) -> OSStatus {
        guard let (store, account) = parse(query) else {
            return errSecParam
        }
        if let compatibilityError = validateDeleteQueryCompatibility(query) {
            return compatibilityError
        }
        if let forced = deleteStatusByStore[store], forced != errSecSuccess {
            return forced
        }

        switch store {
        case .dataProtection:
            guard dataProtectionItems.removeValue(forKey: account) != nil else {
                return errSecItemNotFound
            }
        case .legacy:
            guard legacyItems.removeValue(forKey: account) != nil else {
                return errSecItemNotFound
            }
        }
        return errSecSuccess
    }

    private func parse(_ query: [String: Any]) -> (Store, String)? {
        guard isSecConstant(
            query[kSecClass as String],
            expected: kSecClassGenericPassword
        ) else {
            return nil
        }
        guard let service = query[kSecAttrService as String] as? String,
              service == expectedService else {
            return nil
        }
        guard let account = query[kSecAttrAccount as String] as? String,
              !account.isEmpty else {
            return nil
        }
        if let dataProtectionFlag = query[kSecUseDataProtectionKeychain as String] {
            guard let enabled = dataProtectionFlag as? Bool, enabled else {
                return nil
            }
            return (.dataProtection, account)
        }
        return (.legacy, account)
    }

    private func validateAddQueryCompatibility(_ query: [String: Any], store: Store) -> OSStatus? {
        let allowedKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String,
            kSecValueData as String,
            kSecAttrAccessible as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedKeys) else {
            return errSecParam
        }
        guard query[kSecValueData as String] is Data else {
            return errSecParam
        }

        if store == .legacy {
            if query[kSecAttrAccessible as String] != nil {
                return errSecParam
            }
            return nil
        }

        guard isSecConstant(
            query[kSecAttrAccessible as String],
            expected: kSecAttrAccessibleWhenUnlocked
        ) else {
            return errSecParam
        }
        return nil
    }

    private func validateUpdateQueryCompatibility(
        _ query: [String: Any],
        attributes: [String: Any]
    ) -> OSStatus? {
        let allowedQueryKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedQueryKeys) else {
            return errSecParam
        }

        let expectedAttributeKeys: Set<String> = [kSecValueData as String]
        guard Set(attributes.keys) == expectedAttributeKeys,
              attributes[kSecValueData as String] is Data else {
            return errSecParam
        }

        return nil
    }

    private func validateCopyQueryCompatibility(_ query: [String: Any]) -> OSStatus? {
        let allowedKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String,
            kSecReturnData as String,
            kSecMatchLimit as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedKeys) else {
            return errSecParam
        }
        guard (query[kSecReturnData as String] as? Bool) == true else {
            return errSecParam
        }
        guard isSecConstant(
            query[kSecMatchLimit as String],
            expected: kSecMatchLimitOne
        ) else {
            return errSecParam
        }
        return nil
    }

    private func validateDeleteQueryCompatibility(_ query: [String: Any]) -> OSStatus? {
        let allowedKeys: Set<String> = [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String
        ]
        guard hasOnlyAllowedKeys(query, allowed: allowedKeys) else {
            return errSecParam
        }
        return nil
    }

    private func hasOnlyAllowedKeys(_ query: [String: Any], allowed: Set<String>) -> Bool {
        Set(query.keys).isSubset(of: allowed)
    }

    private func isSecConstant(_ value: Any?, expected: CFString) -> Bool {
        guard let value else {
            return false
        }
        return String(describing: value) == expected as String
    }
}

private final class DataProtectionUnavailableSystemSecurityAPI: KeychainManager.SecurityAPI {
    private let systemAPI = KeychainManager.SystemSecurityAPI()
    private(set) var dataProtectionAddRejectionCount = 0
    private(set) var legacyAddAttemptCount = 0
    private(set) var legacyUpdateAttemptCount = 0

    var legacyWriteAttemptCount: Int {
        legacyAddAttemptCount + legacyUpdateAttemptCount
    }

    func add(_ query: [String : Any]) -> OSStatus {
        if (query[kSecUseDataProtectionKeychain as String] as? Bool) == true {
            dataProtectionAddRejectionCount += 1
            return errSecMissingEntitlement
        }
        legacyAddAttemptCount += 1
        return systemAPI.add(query)
    }

    func update(_ query: [String : Any], attributes: [String : Any]) -> OSStatus {
        if (query[kSecUseDataProtectionKeychain as String] as? Bool) != true {
            legacyUpdateAttemptCount += 1
        }
        return systemAPI.update(query, attributes: attributes)
    }

    func copyMatching(_ query: [String : Any]) -> (status: OSStatus, data: Data?) {
        systemAPI.copyMatching(query)
    }

    func delete(_ query: [String : Any]) -> OSStatus {
        systemAPI.delete(query)
    }
}

private actor HistoryRecordingStoreSpy: UsageHistoryStoreProtocol {
    private var snapshots: [[UsageData]] = []

    func record(samples: [UsageData], recordedAt: Date) async {
        snapshots.append(samples)
    }

    func dayRecords(for service: ServiceType, since: Date, until: Date) async -> [UsageHistoryDayRecord] {
        []
    }

    func secondarySamples(for service: ServiceType, since: Date, until: Date) async -> [UsageHistorySecondarySample] {
        []
    }

    func availableServices(since: Date, until: Date) async -> [ServiceType] {
        []
    }

    func recordedSnapshots() async -> [[UsageData]] {
        snapshots
    }
}
