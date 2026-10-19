import Foundation

struct UsageData: Identifiable, Sendable {
    let id = UUID()
    let service: ServiceType
    let fiveHourUsage: UsageMetric
    let weeklyUsage: UsageMetric?
    let lastUpdated: Date
    let isAvailable: Bool
    let planName: String?
    let showsFiveHourUsage: Bool
    let primaryLabel: String?
    let secondaryLabel: String?
    let resetCredits: UsageResetCredits?
    let statusMessage: String?
    /// Account name shown when a service has several accounts (e.g. two Claude logins).
    let accountLabel: String?
    /// Position among the service's accounts; nil when the service has one account.
    let accountIndex: Int?

    init(
        service: ServiceType,
        fiveHourUsage: UsageMetric,
        weeklyUsage: UsageMetric?,
        lastUpdated: Date,
        isAvailable: Bool,
        planName: String? = nil,
        showsFiveHourUsage: Bool = true,
        primaryLabel: String? = nil,
        secondaryLabel: String? = nil,
        resetCredits: UsageResetCredits? = nil,
        statusMessage: String? = nil,
        accountLabel: String? = nil,
        accountIndex: Int? = nil
    ) {
        self.service = service
        self.fiveHourUsage = fiveHourUsage
        self.weeklyUsage = weeklyUsage
        self.lastUpdated = lastUpdated
        self.isAvailable = isAvailable
        self.planName = planName
        self.showsFiveHourUsage = showsFiveHourUsage
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.resetCredits = resetCredits
        self.statusMessage = statusMessage
        self.accountLabel = accountLabel
        self.accountIndex = accountIndex
    }

    /// Menu bar tag, numbered from the second account on (CC, CC2, ...).
    var shortName: String {
        guard let accountIndex, accountIndex > 0 else { return service.shortName }
        return "\(service.shortName)\(accountIndex + 1)"
    }

    /// Orders rows of the same service by account position.
    var accountSortIndex: Int { accountIndex ?? 0 }
}

struct UsageResetCredits: Decodable, Sendable {
    let availableCount: Int
    let credits: [UsageResetCredit]?
}

struct UsageResetCredit: Decodable, Identifiable, Sendable {
    let id: String
    let status: String
    let expiresAt: Double?
    let title: String?
}

struct UsageMetric: Sendable {
    let used: Double
    let total: Double
    let unit: UsageUnit
    let resetTime: Date?

    var percentage: Double {
        guard total > 0 else { return 0 }
        return min(used / total, 1.0)
    }

    static let zero = UsageMetric(used: 0, total: 0, unit: .tokens, resetTime: nil)
}

enum UsageUnit: String, Sendable {
    case tokens = "tokens"
    case requests = "requests"
    case dollars = "USD"
    case percent = "%"
}
