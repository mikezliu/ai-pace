import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AIPace

struct StatusItemControllerTests {
    @Test
    @MainActor
    func popoverHeightGrowsWithVisibleRows() {
        // Legacy shapes keep their original heights.
        #expect(StatusItemController.popoverHeight(forVisibleRowCounts: []) == 220)
        #expect(StatusItemController.popoverHeight(forVisibleRowCounts: [2]) == 250)
        #expect(StatusItemController.popoverHeight(forVisibleRowCounts: [2, 2]) == 380)

        // A model-scoped weekly row adds one row; an absent 5h window removes one.
        #expect(StatusItemController.popoverHeight(forVisibleRowCounts: [3, 2]) == 424)
        #expect(StatusItemController.popoverHeight(forVisibleRowCounts: [3, 1]) == 380)
        #expect(StatusItemController.popoverHeight(forVisibleRowCounts: [0]) == StatusItemController.popoverHeight(forVisibleRowCounts: [1]))
    }

    @Test
    func statusItemLabelFallsBackWhenProviderTextsAreMissingOrBlank() {
        #expect(StatusItemLabelView.resolvedFallbackText(claudeText: nil, codexText: nil) == "AIPace")
        #expect(StatusItemLabelView.resolvedFallbackText(claudeText: " ", codexText: "\n") == "AIPace")
        #expect(StatusItemLabelView.resolvedFallbackText(claudeText: "Cl 12/34", codexText: nil) == nil)
        #expect(StatusItemLabelView.resolvedFallbackText(claudeText: nil, codexText: "Cx 56/78") == nil)
    }

    @Test
    @MainActor
    func statusItemLengthIsClampedToMinimumVisibleWidth() {
        #expect(StatusItemController.statusItemLength(forContentWidth: 0) == 32)
        #expect(StatusItemController.statusItemLength(forContentWidth: 10) == 32)
        #expect(StatusItemController.statusItemLength(forContentWidth: 40) == 52)
    }

    @Test
    @MainActor
    func rateLimitedStatusUsesCriticalPillStyle() {
        let snapshot = makeSnapshot(.claude, fiveHourUsed: 12, weeklyUsed: 40)
        let status = AgentStatus(
            provider: .claude,
            availability: .rateLimited,
            message: "Claude usage endpoint returned HTTP 429. Retry after 48m."
        )

        let style = StatusItemController.pillStyle(
            theme: .dynamic,
            provider: .claude,
            snapshot: snapshot,
            status: status,
            isDark: false
        )

        #expect(style.background == DynamicTheme.criticalBackground)
        #expect(style.foreground == Color.white)
    }
}
