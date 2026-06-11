import Foundation
import Testing
@testable import AIPace

struct LocalizationAndFormattingTests {
    @Test
    func localizationMapsWindowLabelsAndLoadingMessages() {
        let korean = Loc(lang: .korean)

        #expect(korean.windowLabel(.fiveHour) == "5시간")
        #expect(korean.windowLabel(.weekly) == "주간")
        #expect(korean.displayMessage("Loading…") == "로딩 중…")
        #expect(korean.colors == "색상")
        #expect(korean.reset == "재설정")
        #expect(korean.claudeColor == "Claude 색상")
        #expect(korean.claudeName == "Claude 이름")
        #expect(korean.launchAtStartup == "시동 시 실행")
    }

    @Test
    func localizationBuildsInsightAndStatusInstructions() {
        let english = Loc(lang: .english)
        let status = AgentStatus(provider: .codex, availability: .notInstalled, message: nil)

        #expect(english.insightMessage(delta: -11) == "11% over pace")
        #expect(english.insightMessage(delta: 9) == "9% to spare")
        #expect(english.statusTitle(status) == "Not installed")
        #expect(english.statusInstruction(status) == "Install the Codex CLI and make sure `codex` is on PATH.")

        let rateLimitMessage = "Claude usage endpoint returned HTTP 429. Retry after 2m."
        let rateLimited = AgentStatus(provider: .claude, availability: .rateLimited, message: rateLimitMessage)
        #expect(english.statusInstruction(rateLimited) == rateLimitMessage)
    }

    @Test
    func themeFallbackAndStatusItemFormatting() {
        let snapshot = makeSnapshot(.claude, fiveHourUsed: 12.4, weeklyUsed: 76.6)
        let insightSnapshot = makeSnapshot(
            .codex,
            fiveHourUsed: 5,
            weeklyUsed: 40,
            weeklyReset: Date().addingTimeInterval(3.5 * 24 * 60 * 60)
        )

        #expect(AppTheme.find("missing-theme").id == AppTheme.defaultTheme.id)
        #expect(StatusItemFormatter.text(prefix: "Cl", snapshot: snapshot, mode: .usage) == "Cl 12/77")
        #expect(StatusItemFormatter.text(prefix: "Cl", snapshot: snapshot, mode: .remaining) == "Cl 88/23")
        #expect(StatusItemFormatter.text(prefix: "Cx", snapshot: insightSnapshot, mode: .insight) == "Cx +10%")
        #expect(StatusItemFormatter.text(prefix: "Cx", snapshot: insightSnapshot, mode: .usageAndInsight) == "Cx 5/40 +10%")
        #expect(StatusItemFormatter.text(prefix: "Cx", snapshot: insightSnapshot, mode: .remainingAndInsight) == "Cx 95/60 +10%")
    }

    @Test
    func statusItemRemainingWithResetFormatsTimeUntilSoonestReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        // Both windows have data; the 5h window resets soonest (in 8h 30m -> "8h").
        let snapshot = makeSnapshot(
            .claude,
            fiveHourUsed: 12,
            weeklyUsed: 76.6,
            fiveHourReset: now.addingTimeInterval(8 * 3600 + 30 * 60),
            weeklyReset: now.addingTimeInterval(3 * 24 * 3600)
        )
        #expect(
            StatusItemFormatter.text(prefix: "Cl", snapshot: snapshot, mode: .remainingWithReset, now: now)
                == "Cl 88/23/8h"
        )

        // Under an hour falls back to whole minutes, rounded down (13m 50s -> "13m").
        let soon = makeSnapshot(
            .codex,
            fiveHourUsed: 40,
            weeklyUsed: 5,
            fiveHourReset: now.addingTimeInterval(13 * 60 + 50),
            weeklyReset: now.addingTimeInterval(6 * 24 * 3600)
        )
        #expect(
            StatusItemFormatter.text(prefix: "Cx", snapshot: soon, mode: .remainingWithReset, now: now)
                == "Cx 60/95/13m"
        )

        // No reset timestamps -> "--" for the reset segment.
        let noReset = makeSnapshot(.claude, fiveHourUsed: 12, weeklyUsed: 76.6)
        #expect(
            StatusItemFormatter.text(prefix: "Cl", snapshot: noReset, mode: .remainingWithReset, now: now)
                == "Cl 88/23/--"
        )
    }

    @Test
    func menuBarTextSurfacesAuthStatesInsteadOfHiding() {
        let loc = Loc(lang: .english)
        let snapshot = makeSnapshot(.claude, fiveHourUsed: 12, weeklyUsed: 77)

        // Available providers still render usage.
        let available = AgentStatus(provider: .claude, availability: .available, message: nil)
        #expect(
            StatusItemFormatter.menuBarText(prefix: "Cl", snapshot: snapshot, status: available, mode: .remaining, loc: loc)
                == "Cl 88/23"
        )

        // Auth problems show a "Login" pill rather than vanishing.
        for availability in [AgentAvailability.missingAuth, .accessDenied, .sessionExpired, .notLoggedIn] {
            let status = AgentStatus(provider: .claude, availability: availability, message: "x")
            #expect(
                StatusItemFormatter.menuBarText(prefix: "Cl", snapshot: snapshot, status: status, mode: .remaining, loc: loc)
                    == "Cl Login"
            )
        }

        let rateLimited = AgentStatus(provider: .claude, availability: .rateLimited, message: "HTTP 429")
        #expect(
            StatusItemFormatter.menuBarText(prefix: "Cl", snapshot: snapshot, status: rateLimited, mode: .remaining, loc: loc)
                == "Cl Wait"
        )

        let rateLimitedWithRetry = AgentStatus(
            provider: .claude,
            availability: .rateLimited,
            message: "Claude usage endpoint returned HTTP 429. Retry after 40m."
        )
        #expect(
            StatusItemFormatter.menuBarText(prefix: "Cl", snapshot: snapshot, status: rateLimitedWithRetry, mode: .remaining, loc: loc)
                == "Cl 0/40m"
        )

        // A generic error is surfaced too.
        let error = AgentStatus(provider: .claude, availability: .error("boom"), message: "boom")
        #expect(
            StatusItemFormatter.menuBarText(prefix: "Cl", snapshot: snapshot, status: error, mode: .remaining, loc: loc)
                == "Cl Error"
        )

        // A not-installed provider stays hidden (nil) so unused CLIs aren't noise.
        let notInstalled = AgentStatus(provider: .codex, availability: .notInstalled, message: "x")
        #expect(
            StatusItemFormatter.menuBarText(prefix: "Cx", snapshot: snapshot, status: notInstalled, mode: .remaining, loc: loc) == nil
        )
    }

    @Test
    func menuBarStatusLabelLocalizesLogin() {
        let status = AgentStatus(provider: .claude, availability: .missingAuth, message: nil)
        #expect(Loc(lang: .english).menuBarStatusLabel(status) == "Login")
        #expect(Loc(lang: .japanese).menuBarStatusLabel(status) == "ログイン")
        #expect(Loc(lang: .german).menuBarStatusLabel(status) == "Anmelden")
        #expect(Loc(lang: .english).menuBarStatusLabel(AgentStatus(provider: .claude, availability: .rateLimited, message: nil)) == "Wait")
        #expect(Loc(lang: .english).menuBarStatusLabel(AgentStatus(provider: .codex, availability: .notInstalled, message: nil)) == nil)
        #expect(Loc(lang: .english).menuBarStatusLabel(AgentStatus(provider: .claude, availability: .available, message: nil)) == nil)
    }

    @Test
    func compactResetValueHandlesBoundaries() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        func reset(_ seconds: TimeInterval) -> UsageWindow {
            makeWindow(.fiveHour, resetsAt: now.addingTimeInterval(seconds))
        }

        #expect(StatusItemFormatter.compactResetValue(for: reset(130 * 3600), now: now) == "5d")
        #expect(StatusItemFormatter.compactResetValue(for: reset(48 * 3600), now: now) == "2d")
        #expect(StatusItemFormatter.compactResetValue(for: reset(86400), now: now) == "1d")
        #expect(StatusItemFormatter.compactResetValue(for: reset(86399), now: now) == "23h")
        #expect(StatusItemFormatter.compactResetValue(for: reset(8 * 3600), now: now) == "8h")
        #expect(StatusItemFormatter.compactResetValue(for: reset(3601), now: now) == "1h")
        #expect(StatusItemFormatter.compactResetValue(for: reset(3600), now: now) == "60m")
        #expect(StatusItemFormatter.compactResetValue(for: reset(59 * 60 + 59), now: now) == "59m")
        #expect(StatusItemFormatter.compactResetValue(for: reset(-30), now: now) == "0m")
        #expect(StatusItemFormatter.compactResetValue(for: makeWindow(.fiveHour), now: now) == "--")
    }

    @Test
    func customAccentHexOverridesSelectedTheme() {
        let suiteName = "AIPaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("#123ABC", forKey: AppTheme.customClaudeAccentDefaultsKey)

        let theme = AppTheme.resolvedTheme(themeID: AppTheme.sunset.id, userDefaults: defaults)

        #expect(AppColorHex.normalized("f60") == "#FF6600")
        #expect(AppColorHex.string(from: theme.claudeAccent) == "#123ABC")
        #expect(AppColorHex.string(from: theme.codexAccent) == AppColorHex.string(from: AppTheme.sunset.codexAccent))
    }

    @Test
    func customProviderNamesAreTrimmedAndCapped() {
        let suiteName = "AIPaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("  SonnetPro  ", forKey: ProviderDisplayName.customClaudeNameDefaultsKey)
        defaults.set("  ", forKey: ProviderDisplayName.customCodexNameDefaultsKey)

        #expect(ProviderDisplayName.maxLength == 7)
        #expect(ProviderDisplayName.sanitizedInput("CodeRunner") == "CodeRun")
        #expect(ProviderDisplayName.displayName(for: .claude, userDefaults: defaults) == "SonnetP")
        #expect(ProviderDisplayName.displayName(for: .codex, userDefaults: defaults) == "Cx")
    }
}
