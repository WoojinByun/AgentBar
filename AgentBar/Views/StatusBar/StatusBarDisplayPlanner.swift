import Foundation
import CoreGraphics

enum StatusBarDisplayPlanner {
    static let visibleRowCount = 3
    static let rowSpacing: CGFloat = 1
    static let viewportHeight: CGFloat = 20
    /// Row height of the full (3-row) layout; kept for callers that assume it.
    static let rowHeight: CGFloat = rowLayout(forVisibleRowCount: visibleRowCount).rowHeight

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

    /// Per-row metrics for the number of rows that are visible at once.
    struct RowLayout: Equatable {
        let rowCount: Int
        let rowHeight: CGFloat
        let spacing: CGFloat
        let labelFontSize: CGFloat
        let labelWidth: CGFloat
        let cornerRadius: CGFloat

        /// Distance between the tops of two consecutive rows.
        var rowStride: CGFloat { rowHeight + spacing }
    }

    /// Rows are stretched so that they always fill `viewportHeight` top to bottom:
    /// 1 row = 20pt, 2 rows = 9.5pt each, 3 rows = 6pt each (the original look).
    static func rowLayout(forVisibleRowCount count: Int) -> RowLayout {
        let rows = min(max(count, 1), visibleRowCount)
        let height = (viewportHeight - rowSpacing * CGFloat(rows - 1)) / CGFloat(rows)
        switch rows {
        case 1:
            return RowLayout(rowCount: 1, rowHeight: height, spacing: rowSpacing,
                             labelFontSize: 11, labelWidth: 20, cornerRadius: 3)
        case 2:
            return RowLayout(rowCount: 2, rowHeight: height, spacing: rowSpacing,
                             labelFontSize: 8, labelWidth: 16, cornerRadius: 2)
        default:
            return RowLayout(rowCount: rows, rowHeight: height, spacing: rowSpacing,
                             labelFontSize: 6, labelWidth: 14, cornerRadius: 1.5)
        }
    }

    /// Frames (x = 0, width supplied by caller) of each visible row inside the viewport.
    static func rowFrames(forVisibleRowCount count: Int, width: CGFloat = 1) -> [CGRect] {
        let layout = rowLayout(forVisibleRowCount: count)
        return (0..<layout.rowCount).map { index in
            CGRect(x: 0, y: CGFloat(index) * layout.rowStride, width: width, height: layout.rowHeight)
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
