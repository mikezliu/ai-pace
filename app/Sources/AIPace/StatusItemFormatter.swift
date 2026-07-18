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

    /// Time until `window` resets, as whole days ("5d") when a day or more away,
    /// whole hours ("8h") when more than an hour away, otherwise whole minutes
    /// ("13m"). All round down. Returns "--" when no reset time is known and "0m"
    /// once the window is due to reset.
    static func compactResetValue(for window: UsageWindow, now: Date = .now) -> String {
        guard let resetsAt = window.resetsAt else {
            return "--"
        }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else {
            return "0m"
        }
        if seconds >= 86400 {
            return "\(Int(seconds / 86400))d"
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
        if status.availability.showsUsageText {
            return text(prefix: prefix, snapshot: snapshot, mode: mode, now: now)
        }
        if case .rateLimited = status.availability,
           let retryLabel = rateLimitRetryLabel(from: status.message) {
            return "\(prefix) 0/\(retryLabel)"
        }
        guard let label = loc.menuBarStatusLabel(status) else {
            return nil
        }
        return "\(prefix) \(label)"
    }

    /// Joined 5h/weekly values for the menu bar, dropping windows the provider
    /// affirmatively reported as nonexistent (e.g. Codex plans with only a
    /// weekly limit render "Cx 32" instead of "Cx --/32"). Model-scoped weekly
    /// values (e.g. the Fable cap) follow the weekly value in brackets, as in
    /// "31/54(20)".
    private static func joinedValue(for snapshot: ProviderSnapshot, transform: (UsageWindow) -> String) -> String {
        let scopedValues = snapshot.modelWeeklies
            .filter { $0.usedPercentage != nil }
            .map(transform)
        let scopedSuffix = scopedValues.isEmpty ? "" : "(\(scopedValues.joined(separator: "/")))"

        var components: [String] = []
        if !snapshot.fiveHour.isAbsent {
            components.append(transform(snapshot.fiveHour))
        }
        if !snapshot.weekly.isAbsent {
            components.append(transform(snapshot.weekly) + scopedSuffix)
        } else if !scopedSuffix.isEmpty {
            components.append(scopedSuffix)
        }
        if components.isEmpty {
            components = [snapshot.fiveHour, snapshot.weekly].map(transform)
        }
        return components.joined(separator: "/")
    }

    static func text(prefix: String, snapshot: ProviderSnapshot, mode: MenuBarDisplayMode, now: Date = .now) -> String {
        switch mode {
        case .usage:
            return "\(prefix) \(joinedValue(for: snapshot, transform: compactValue(for:)))"
        case .remaining:
            return "\(prefix) \(joinedValue(for: snapshot, transform: compactRemainingValue(for:)))"
        case .remainingWithReset:
            let remaining = joinedValue(for: snapshot, transform: compactRemainingValue(for:))
            return "\(prefix) \(remaining)/\(compactResetValue(for: snapshot, now: now))"
        case .insight:
            let insight = WeeklyPacing.formattedDelta(for: snapshot.weekly, now: now) ?? "--"
            return "\(prefix) \(insight)"
        case .usageAndInsight:
            let usage = joinedValue(for: snapshot, transform: compactValue(for:))
            let insight = WeeklyPacing.formattedDelta(for: snapshot.weekly, now: now) ?? "--"
            return "\(prefix) \(usage) \(insight)"
        case .remainingAndInsight:
            let remaining = joinedValue(for: snapshot, transform: compactRemainingValue(for:))
            let insight = WeeklyPacing.formattedDelta(for: snapshot.weekly, now: now) ?? "--"
            return "\(prefix) \(remaining) \(insight)"
        }
    }

    private static func rateLimitRetryLabel(from message: String?) -> String? {
        guard let message else {
            return nil
        }

        let pattern = #"(?i)\bretry after\s+([0-9]+\s*[smhd])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let labelRange = Range(match.range(at: 1), in: message) else {
            return nil
        }

        let label = message[labelRange].replacingOccurrences(of: " ", with: "").lowercased()
        guard !label.isEmpty else {
            return nil
        }
        // A zero retry hint ("Retry after 0s") would render as the nonsense
        // pill "0/0s"; fall back to the generic "Wait" label instead.
        if Int(label.prefix(while: \.isNumber)) == 0 {
            return nil
        }
        return label
    }
}
