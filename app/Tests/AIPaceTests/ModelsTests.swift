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

        // lowestRemaining is the smaller of the two windows' (100 - used).
        #expect(makeSnapshot(.claude, fiveHourUsed: 75, weeklyUsed: 40).lowestRemaining == 25)
        #expect(makeSnapshot(.claude, fiveHourUsed: 95).lowestRemaining == 5)
        #expect(makeSnapshot(.claude).lowestRemaining == nil)
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
    }

    @Test
    func agentAvailabilityPopoverVisibilityMatchesExpectedStates() {
        #expect(AgentAvailability.loading.showsInPopover)
        #expect(AgentAvailability.available.showsInPopover)
        #expect(!AgentAvailability.notInstalled.showsInPopover)
        #expect(!AgentAvailability.error("boom").showsInPopover)
    }

    @Test
    func autoRefreshDefaults() {
        #expect(AutoRefreshInterval.defaultValue == .oneMinute)
        #expect(AutoRefreshInterval.manual.label == "Manual")
        #expect(AutoRefreshInterval.tenMinutes.label == "10 minutes")
        #expect(AutoRefreshInterval.thirtyMinutes.duration == 1800)
    }
}
