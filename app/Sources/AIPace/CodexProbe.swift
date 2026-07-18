import Foundation

struct CodexProbe: Sendable {
    func fetch() async -> ProviderSnapshot {
        do {
            let limits = try await fetchRateLimits()
            let windows = classifiedWindows(primary: limits.primary, secondary: limits.secondary)
            return ProviderSnapshot(
                provider: .codex,
                fiveHour: UsageWindow(
                    kind: .fiveHour,
                    usedPercentage: windows.fiveHour?.usedPercent,
                    resetsAt: windows.fiveHour?.resetsAt,
                    message: windows.fiveHour == nil ? "No 5h limit returned." : nil,
                    isAbsent: windows.fiveHour == nil
                ),
                weekly: UsageWindow(
                    kind: .weekly,
                    usedPercentage: windows.weekly?.usedPercent,
                    resetsAt: windows.weekly?.resetsAt,
                    message: windows.weekly == nil ? "No weekly limit returned." : nil,
                    isAbsent: windows.weekly == nil
                ),
                detail: limits.planType.map { "Plan: \($0)" }
            )
        } catch {
            return ProviderSnapshot(
                provider: .codex,
                fiveHour: UsageWindow(kind: .fiveHour, usedPercentage: nil, resetsAt: nil, message: error.localizedDescription),
                weekly: UsageWindow(kind: .weekly, usedPercentage: nil, resetsAt: nil, message: error.localizedDescription),
                detail: nil
            )
        }
    }

    private func fetchRateLimits() async throws -> CodexRateLimits {
        guard let executable = ProcessRunner.which("codex") else {
            throw ProcessRunnerError.executableNotFound("codex")
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = ProcessRunner.environment()

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try writeJSONLine([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "aipace",
                    "version": "0.1.0",
                ],
            ],
        ], to: stdin.fileHandleForWriting)

        _ = try await readResponse(
            withID: 1,
            from: stdout.fileHandleForReading.bytes.lines
        )

        try writeJSONLine([
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:],
        ], to: stdin.fileHandleForWriting)

        try writeJSONLine([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "account/rateLimits/read",
            "params": [:],
        ], to: stdin.fileHandleForWriting)

        let payload = try await readResponse(
            withID: 2,
            from: stdout.fileHandleForReading.bytes.lines
        )
        guard
            let result = payload["result"] as? [String: Any],
            let rateLimits = result["rateLimits"] as? [String: Any]
        else {
            throw ProcessRunnerError.invalidResponse("Codex rate limit response was missing result.rateLimits.")
        }

        return CodexRateLimits(
            primary: parseWindow(rateLimits["primary"]),
            secondary: parseWindow(rateLimits["secondary"]),
            planType: rateLimits["planType"] as? String
        )
    }

    func parseWindow(_ value: Any?) -> CodexRateLimitWindow? {
        guard let window = value as? [String: Any] else {
            return nil
        }
        guard let usedPercent = numericValue(window["usedPercent"]) else {
            return nil
        }
        let resetsAt = numericValue(window["resetsAt"]).map(Date.init(timeIntervalSince1970:))
        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            windowDurationMins: numericValue(window["windowDurationMins"])
        )
    }

    /// Sorts the primary/secondary windows into the 5h and weekly slots by
    /// their actual duration. Some plans (e.g. prolite) return a single
    /// `primary` window that is a 7-day window, so position alone is not a
    /// reliable signal.
    func classifiedWindows(
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?,
        now: Date = .now
    ) -> (fiveHour: CodexRateLimitWindow?, weekly: CodexRateLimitWindow?) {
        var fiveHour: CodexRateLimitWindow?
        var weekly: CodexRateLimitWindow?

        // When a window's duration is unknown, fall back to its historical
        // position: primary was the 5h window, secondary the weekly one.
        let candidates: [(window: CodexRateLimitWindow?, prefersWeekly: Bool)] = [
            (primary, false),
            (secondary, true),
        ]
        for (window, prefersWeekly) in candidates {
            guard let window else {
                continue
            }
            switch window.span(now: now) {
            case .short:
                if fiveHour == nil { fiveHour = window }
            case .long:
                if weekly == nil { weekly = window }
            case .unknown:
                if prefersWeekly {
                    if weekly == nil { weekly = window } else if fiveHour == nil { fiveHour = window }
                } else {
                    if fiveHour == nil { fiveHour = window } else if weekly == nil { weekly = window }
                }
            }
        }
        return (fiveHour, weekly)
    }

    func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}

struct CodexRateLimits {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?
}

struct CodexRateLimitWindow: Sendable, Equatable {
    let usedPercent: Double
    let resetsAt: Date?
    var windowDurationMins: Double? = nil

    enum Span {
        case short
        case long
        case unknown
    }

    /// Whether this is a short (≤ 24h, i.e. the "5h"-style session window) or
    /// long (multi-day, i.e. weekly) window. Without an explicit duration, a
    /// reset more than 24h away still proves the window spans multiple days —
    /// a window can never have more time left than its total duration.
    func span(now: Date) -> Span {
        if let windowDurationMins {
            return windowDurationMins > 24 * 60 ? .long : .short
        }
        if let resetsAt, resetsAt.timeIntervalSince(now) > 24 * 60 * 60 {
            return .long
        }
        return .unknown
    }
}

func writeJSONLine(_ object: [String: Any], to handle: FileHandle) throws {
    let data = try JSONSerialization.data(withJSONObject: object)
    handle.write(data)
    handle.write(Data([0x0A]))
}

func readResponse<S: AsyncSequence>(
    withID id: Int,
    from lines: S
) async throws -> [String: Any] where S.Element == String {
    for try await line in lines {
        guard !line.isEmpty, let data = line.data(using: .utf8) else {
            continue
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            continue
        }

        guard let lineID = integerValue(json["id"]), lineID == id else {
            continue
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ProcessRunnerError.invalidResponse(message)
        }
        return json
    }
    throw ProcessRunnerError.invalidResponse("Codex app-server closed before returning response id \(id).")
}

func integerValue(_ value: Any?) -> Int? {
    switch value {
    case let number as Int:
        return number
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        return Int(string)
    default:
        return nil
    }
}
