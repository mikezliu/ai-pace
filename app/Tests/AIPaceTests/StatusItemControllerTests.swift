import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AIPace

struct StatusItemControllerTests {
    @Test
    @MainActor
    func popoverHeightBucketsMatchVisibleAgentCounts() {
        #expect(StatusItemController.popoverHeight(forVisibleSnapshotCount: 0) == 220)
        #expect(StatusItemController.popoverHeight(forVisibleSnapshotCount: 1) == 250)
        #expect(StatusItemController.popoverHeight(forVisibleSnapshotCount: 2) == 380)
        #expect(StatusItemController.popoverHeight(forVisibleSnapshotCount: 5) == 380)
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
