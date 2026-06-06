import Foundation

enum StatusItemFormatter {
    static func compactValue(for window: UsageWindow) -> String {
        guard let used = window.usedPercentage else {
            return "--"
        }
        return String(Int(used.rounded()))
    }

    static func compactRemainingValue(for window: UsageWindow) -> String {
        guard let used = window.usedPercentage else {
            return "--"
        }
        let remaining = max(0, 100 - used)
        return String(Int(remaining.rounded()))
    }

    /// Time until `window` resets, as whole hours ("8h") when more than an hour
    /// away, otherwise whole minutes ("13m"). Both round down. Returns "--" when
    /// no reset time is known and "0m" once the window is due to reset.
    static func compactResetValue(for window: UsageWindow, now: Date = .now) -> String {
        guard let resetsAt = window.resetsAt else {
            return "--"
        }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else {
            return "0m"
        }
        if seconds > 3600 {
            return "\(Int(seconds / 3600))h"
        }
        return "\(Int(seconds / 60))m"
    }

    /// The window (5h or weekly) that resets soonest, preferring resets still in
    /// the future so a stale, already-elapsed reset doesn't mask an upcoming one.
    static func nextResetWindow(for snapshot: ProviderSnapshot, now: Date = .now) -> UsageWindow? {
        let candidates = [snapshot.fiveHour, snapshot.weekly].filter { $0.resetsAt != nil }
        guard !candidates.isEmpty else {
            return nil
        }
        let upcoming = candidates.filter { ($0.resetsAt ?? .distantPast) > now }
        let pool = upcoming.isEmpty ? candidates : upcoming
        return pool.min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }

    static func compactResetValue(for snapshot: ProviderSnapshot, now: Date = .now) -> String {
        guard let window = nextResetWindow(for: snapshot, now: now) else {
            return "--"
        }
        return compactResetValue(for: window, now: now)
    }

    /// Menu-bar text for a provider: its usage when available, otherwise a short
    /// status label (e.g. "Login"). Returns `nil` only when the provider should
    /// be hidden entirely (e.g. an uninstalled CLI).
    static func menuBarText(
        prefix: String,
        snapshot: ProviderSnapshot,
        status: AgentStatus,
        mode: MenuBarDisplayMode,
        loc: Loc,
        now: Date = .now
    ) -> String? {
        if status.availability.showsInPopover {
            return text(prefix: prefix, snapshot: snapshot, mode: mode, now: now)
        }
        guard let label = loc.menuBarStatusLabel(status) else {
            return nil
        }
        return "\(prefix) \(label)"
    }

    static func text(prefix: String, snapshot: ProviderSnapshot, mode: MenuBarDisplayMode, now: Date = .now) -> String {
        switch mode {
        case .usage:
            return "\(prefix) \(compactValue(for: snapshot.fiveHour))/\(compactValue(for: snapshot.weekly))"
        case .remaining:
            return "\(prefix) \(compactRemainingValue(for: snapshot.fiveHour))/\(compactRemainingValue(for: snapshot.weekly))"
        case .remainingWithReset:
            let remaining = "\(compactRemainingValue(for: snapshot.fiveHour))/\(compactRemainingValue(for: snapshot.weekly))"
            return "\(prefix) \(remaining)/\(compactResetValue(for: snapshot, now: now))"
        case .insight:
            let insight = WeeklyPacing.formattedDelta(for: snapshot.weekly) ?? "--"
            return "\(prefix) \(insight)"
        case .usageAndInsight:
            let usage = "\(compactValue(for: snapshot.fiveHour))/\(compactValue(for: snapshot.weekly))"
            let insight = WeeklyPacing.formattedDelta(for: snapshot.weekly) ?? "--"
            return "\(prefix) \(usage) \(insight)"
        case .remainingAndInsight:
            let remaining = "\(compactRemainingValue(for: snapshot.fiveHour))/\(compactRemainingValue(for: snapshot.weekly))"
            let insight = WeeklyPacing.formattedDelta(for: snapshot.weekly) ?? "--"
            return "\(prefix) \(remaining) \(insight)"
        }
    }
}
