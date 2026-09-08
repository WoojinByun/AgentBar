import SwiftUI

struct DetailPopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    static let popoverWidth: CGFloat = 350
    private var displayUsageData: [UsageData] {
        Self.sortedForDisplay(viewModel.usageData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("AgentBar")
                    .font(.headline)
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }

            Divider()

            if viewModel.usageData.isEmpty {
                Text("No usage data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(displayUsageData) { data in
                            ServiceDetailRow(data: data)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            // Footer
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let error = viewModel.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Last updated: \(relativeTimeString())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(Self.versionString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: Self.popoverWidth, height: 480)
    }

    private func openSettings() {
        PopoverController.shared.hide()
        SettingsWindowController.shared.show()
    }

    static func sortedForDisplay(_ usageData: [UsageData]) -> [UsageData] {
        let serviceOrder: [ServiceType] = [.claude, .codex, .gemini, .copilot, .cursor, .opencode, .zai]
        return usageData.sorted { lhs, rhs in
            let lhsScore = max(lhs.fiveHourUsage.percentage, lhs.weeklyUsage?.percentage ?? 0)
            let rhsScore = max(rhs.fiveHourUsage.percentage, rhs.weeklyUsage?.percentage ?? 0)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let lhsRank = serviceOrder.firstIndex(of: lhs.service) ?? serviceOrder.count
            let rhsRank = serviceOrder.firstIndex(of: rhs.service) ?? serviceOrder.count
            return lhsRank < rhsRank
        }
    }

    #if DEBUG
    func isBMCButtonVisibleForTesting() -> Bool {
        false
    }
    #endif

    static func resolvedVersionString(from info: [String: Any]?) -> String {
        if let tag = normalizedString(info?["GitVersionTag"] as? String) {
            return tag
        }
        if let hash = normalizedString(info?["GitCommitHash"] as? String) {
            return hash
        }
        if let shortVersion = normalizedString(info?["CFBundleShortVersionString"] as? String) {
            return shortVersion
        }
        return "unknown"
    }

    private static func normalizedString(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let versionString = resolvedVersionString(from: Bundle.main.infoDictionary)

    private func relativeTimeString() -> String {
        guard let latest = viewModel.usageData.map(\.lastUpdated).max() else {
            return "never"
        }
        let interval = Date().timeIntervalSince(latest)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        return "\(Int(interval / 60))m ago"
    }
}

struct ServiceDetailRow: View {
    let data: UsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(data.service.darkColor)
                    .frame(width: 8, height: 8)
                Text(data.service.rawValue)
                    .font(.subheadline.weight(.medium))
                if let planName = data.planName {
                    Text(planName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MiniBarView(data: data)
                    .frame(width: 60, height: 8)
            }

            if data.showsFiveHourUsage {
                MetricRow(
                    label: data.primaryLabel ?? data.service.fiveHourLabel,
                    metric: data.fiveHourUsage,
                    showsExactResetTime: (data.primaryLabel ?? data.service.fiveHourLabel) == "5h"
                )
            }
            if let weekly = data.weeklyUsage {
                MetricRow(label: data.secondaryLabel ?? data.service.weeklyLabel, metric: weekly)
            }
            if let credits = data.resetCredits {
                Text("Resets available: \(credits.availableCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(credits.credits?.filter { $0.status == "available" } ?? []) { credit in
                    HStack {
                        Text(credit.title ?? "Full reset")
                        Spacer()
                        if let expiresAt = credit.expiresAt {
                            Text("Expires \(MetricRow.resetTimestampText(for: Date(timeIntervalSince1970: expiresAt)))")
                        } else {
                            Text("Expiry unavailable")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            if let message = data.statusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                if data.showsFiveHourUsage || data.weeklyUsage != nil {
                    Text("Last success: \(MetricRow.resetTimestampText(for: data.lastUpdated))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MetricRow: View {
    let label: String
    let metric: UsageMetric
    let showsExactResetTime: Bool

    init(label: String, metric: UsageMetric, showsExactResetTime: Bool = false) {
        self.label = label
        self.metric = metric
        self.showsExactResetTime = showsExactResetTime
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            if metric.unit == .percent {
                Text(formatValue(metric.used, unit: metric.unit))
                    .font(.caption.monospacedDigit())
            } else {
                Text(formatValue(metric.used, unit: metric.unit))
                    .font(.caption.monospacedDigit())
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatValue(metric.total, unit: metric.unit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let reset = metric.resetTime {
                let remaining = reset.timeIntervalSinceNow
                if remaining > 0 {
                    if showsExactResetTime {
                        Text(Self.resetTimestampText(for: reset))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(formatDuration(remaining))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(Int(metric.percentage * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(metric.percentage > 0.8 ? .red : .primary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    static func resetTimestampText(for resetTime: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: resetTime)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            let days = hours / 24
            let remainHours = hours % 24
            return "\(days)d \(remainHours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatValue(_ value: Double, unit: UsageUnit) -> String {
        switch unit {
        case .dollars:
            return String(format: "$%.2f", value)
        case .tokens:
            if value >= 1_000_000 {
                return String(format: "%.1fM", value / 1_000_000)
            } else if value >= 1_000 {
                return String(format: "%.0fK", value / 1_000)
            }
            return String(format: "%.0f", value)
        case .requests:
            return String(format: "%.0f", value)
        case .percent:
            return String(format: "%.0f%%", value)
        }
    }
}

struct MiniBarView: View {
    let data: UsageData

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                if let weekly = data.weeklyUsage, weekly.percentage > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(data.service.lightColor)
                        .frame(width: geo.size.width * weekly.percentage)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(data.service.darkColor)
                    .frame(width: geo.size.width * data.fiveHourUsage.percentage)
            }
        }
    }
}
