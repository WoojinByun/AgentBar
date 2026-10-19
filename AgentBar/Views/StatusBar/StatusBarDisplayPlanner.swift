import Foundation
import CoreGraphics

enum StatusBarDisplayPlanner {
    static let visibleRowCount = 3
    static let rowHeight: CGFloat = 6
    static let rowSpacing: CGFloat = 1
    static let viewportHeight: CGFloat = 20

    static let topPriorityHoldSeconds: TimeInterval = 8
    static let scrollStepHoldSeconds: TimeInterval = 3
    static let scrollTransitionSeconds: TimeInterval = 1.2

    private static let serviceOrder: [ServiceType] = [.claude, .codex, .gemini, .copilot, .cursor, .opencode, .zai]

    static func rankedServices(from services: [UsageData]) -> [UsageData] {
        services
            .filter(\.isAvailable)
            .sorted { lhs, rhs in
                let lhsScore = usageScore(lhs)
                let rhsScore = usageScore(rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                let lhsRank = serviceOrder.firstIndex(of: lhs.service) ?? serviceOrder.count
                let rhsRank = serviceOrder.firstIndex(of: rhs.service) ?? serviceOrder.count
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.accountSortIndex < rhs.accountSortIndex
            }
    }

    static func maxScrollIndex(for rankedServices: [UsageData]) -> Int {
        max(0, rankedServices.count - visibleRowCount)
    }

    private static func usageScore(_ data: UsageData) -> Double {
        let weekly = data.weeklyUsage?.percentage ?? 0
        return max(data.fiveHourUsage.percentage, weekly)
    }
}
