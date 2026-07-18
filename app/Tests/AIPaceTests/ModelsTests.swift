import Foundation
import SwiftUI
import Testing
@testable import AIPace

struct ModelsTests {
    @Test
    func dynamicThemeIsDefaultAndUsesUsageDrivenLevels() {
        #expect(AppTheme.defaultTheme.id == "dynamic")
        #expect(AppTheme.dynamic.isDynamic)
        #expect(AppTheme.find("dynamic").isDynamic)
        #expect(AppTheme.sunset.isDynamic == false)
        #expect(AppTheme.all.contains { $0.id == "dynamic" })

        // Thresholds: < 30 caution, < 20 warning, < 10 critical (boundaries inclusive of higher band).
        #expect(DynamicThemeLevel.level(forRemaining: nil) == .normal)
        #expect(DynamicThemeLevel.level(forRemaining: 30) == .normal)
        #expect(DynamicThemeLevel.level(forRemaining: 29) == .caution)
        #expect(DynamicThemeLevel.level(forRemaining: 20) == .caution)
        #expect(DynamicThemeLevel.level(forRemaining: 19) == .warning)
        #expect(DynamicThemeLevel.level(forRemaining: 10) == .warning)
        #expect(DynamicThemeLevel.level(forRemaining: 9) == .critical)
        #expect(DynamicThemeLevel.level(forRemaining: 0) == .critical)
    }

    @Test
    func dynamicPillStyleAndLowestRemaining() {
        // Style picks the right background + a high-contrast foreground per level.
        #expect(DynamicTheme.pillStyle(forRemaining: 5, isDark: false).background == DynamicTheme.criticalBackground)
        #expect(DynamicTheme.pillStyle(forRemaining: 5, isDark: false).foreground == Color.white)
        #expect(DynamicTheme.pillStyle(forRemaining: 15, isDark: false).background == DynamicTheme.warningBackground)
        #expect(DynamicTheme.pillStyle(forRemaining: 15, isDark: false).foreground == Color.black)
        #expect(DynamicTheme.pillStyle(forRemaining: 25, isDark: false).background == DynamicTheme.cautionBackground)

        // lowestRemaining is the smallest (100 - used) across all windows,
        // including model-scoped weeklies, so a nearly-exhausted Fable limit
        // escalates the pill even when the shared windows are healthy.
        #expect(makeSnapshot(.claude, fiveHourUsed: 75, weeklyUsed: 40).lowestRemaining == 25)
        #expect(makeSnapshot(.claude, fiveHourUsed: 95).lowestRemaining == 5)
        #expect(makeSnapshot(.claude).lowestRemaining == nil)
        let fable = makeWindow(.weekly, used: 92, scopeLabel: "Fable")
        #expect(makeSnapshot(.claude, fiveHourUsed: 40, weeklyUsed: 40, modelWeeklies: [fable]).lowestRemaining == 8)
        #expect(makeSnapshot(.claude, modelWeeklies: [fable]).lowestRemaining == 8)
    }

    @Test
    func weeklyPacingCalculatesDeltaAndFormattedValue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(3.5 * 24 * 60 * 60)
        let window = makeWindow(.weekly, used: 40, resetsAt: reset)

        #expect(abs((WeeklyPacing.delta(for: window, now: now) ?? 0) - 10) < 0.001)
        #expect(WeeklyPacing.formattedDelta(for: window, now: now) == "+10%")
    }

    @Test
    func weeklyPacingReturnsNilForNonWeeklyWindows() {
        let window = makeWindow(.fiveHour, used: 50, resetsAt: Date())

        #expect(WeeklyPacing.delta(for: window) == nil)
        #expect(WeeklyPacing.formattedDelta(for: window) == nil)
    }

    @Test
    func usageWindowKeyBuildsStableStorageKey() {
        let key = UsageWindowKey(provider: .codex, kind: .weekly)
        #expect(key.storageKey == "codex-week")
        #expect(key.displayLabel == "Week")

        let scopedKey = UsageWindowKey(provider: .claude, kind: .weekly, scope: "Fable")
        #expect(scopedKey.storageKey == "claude-week-fable")
        #expect(scopedKey.displayLabel == "Fable")
    }

    @Test
    func snapshotRowCountAndUsageDataCoverModelWeekliesAndAbsentWindows() {
        let fable = makeWindow(.weekly, used: 74, scopeLabel: "Fable")

        let withFable = makeSnapshot(.claude, fiveHourUsed: 10, weeklyUsed: 20, modelWeeklies: [fable])
        #expect(withFable.visibleRowCount == 3)
        #expect(withFable.hasUsageData)

        let weeklyOnly = makeSnapshot(.codex, weeklyUsed: 68, fiveHourAbsent: true)
        #expect(weeklyOnly.visibleRowCount == 1)
        #expect(weeklyOnly.hasUsageData)

        let scopedDataOnly = makeSnapshot(.claude, modelWeeklies: [fable])
        #expect(scopedDataOnly.hasUsageData)
        #expect(!makeSnapshot(.claude).hasUsageData)

        // Scoped windows get a distinct identity so SwiftUI rows don't collide.
        #expect(fable.id != makeWindow(.weekly, used: 20).id)
    }

    @Test
    func agentAvailabilityPopoverVisibilityMatchesExpectedStates() {
        #expect(AgentAvailability.loading.showsInPopover)
        #expect(AgentAvailability.available.showsInPopover)
        // Rate limiting is transient: the card stays visible in the popover,
        // but the menu bar still shows the "Wait" pill, not usage numbers.
        #expect(AgentAvailability.rateLimited.showsInPopover)
        #expect(!AgentAvailability.rateLimited.showsUsageText)
        #expect(!AgentAvailability.notInstalled.showsInPopover)
        #expect(!AgentAvailability.error("boom").showsInPopover)
        #expect(AgentAvailability.loading.showsUsageText)
        #expect(AgentAvailability.available.showsUsageText)
        #expect(!AgentAvailability.error("boom").showsUsageText)
    }

    @Test
    func autoRefreshDefaults() {
        #expect(AutoRefreshInterval.defaultValue == .oneMinute)
        #expect(AutoRefreshInterval.manual.label == "Manual")
        #expect(AutoRefreshInterval.tenMinutes.label == "10 minutes")
        #expect(AutoRefreshInterval.thirtyMinutes.duration == 1800)
    }
}
