import Foundation
import Testing
@testable import AIPace

struct CodexProbeTests {
    @Test
    func numericValueParsesCommonJSONRepresentations() {
        let probe = CodexProbe()

        #expect(probe.numericValue(12) == 12)
        #expect(probe.numericValue("12.5") == 12.5)
        #expect(probe.numericValue(NSNumber(value: 7.25)) == 7.25)
        #expect(probe.numericValue("nope") == nil)
    }

    @Test
    func parseWindowRequiresUsedPercentAndParsesResetTimestamp() {
        let probe = CodexProbe()
        let window = probe.parseWindow([
            "usedPercent": "62.5",
            "resetsAt": 1_710_000_000,
            "windowDurationMins": 10_080,
        ])

        #expect(window?.usedPercent == 62.5)
        #expect(window?.resetsAt == Date(timeIntervalSince1970: 1_710_000_000))
        #expect(window?.windowDurationMins == 10_080)
        #expect(probe.parseWindow(["resetsAt": 1_710_000_000]) == nil)
        #expect(probe.parseWindow(["usedPercent": 5])?.windowDurationMins == nil)
    }

    @Test
    func classifiedWindowsSortsByDurationRegardlessOfPosition() {
        let probe = CodexProbe()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fiveHour = CodexRateLimitWindow(usedPercent: 10, resetsAt: now.addingTimeInterval(3600), windowDurationMins: 300)
        let weekly = CodexRateLimitWindow(usedPercent: 68, resetsAt: now.addingTimeInterval(5 * 86_400), windowDurationMins: 10_080)

        let normal = probe.classifiedWindows(primary: fiveHour, secondary: weekly, now: now)
        #expect(normal.fiveHour == fiveHour)
        #expect(normal.weekly == weekly)

        let swapped = probe.classifiedWindows(primary: weekly, secondary: fiveHour, now: now)
        #expect(swapped.fiveHour == fiveHour)
        #expect(swapped.weekly == weekly)
    }

    @Test
    func classifiedWindowsPutsSoloWeeklyPrimaryInWeeklySlot() {
        // prolite-style payload: a single primary window that is a 7-day window.
        let probe = CodexProbe()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let weekly = CodexRateLimitWindow(usedPercent: 68, resetsAt: now.addingTimeInterval(5 * 86_400), windowDurationMins: 10_080)

        let classified = probe.classifiedWindows(primary: weekly, secondary: nil, now: now)
        #expect(classified.fiveHour == nil)
        #expect(classified.weekly == weekly)
    }

    @Test
    func classifiedWindowsFallsBackToPositionWithoutDurations() {
        let probe = CodexProbe()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let primary = CodexRateLimitWindow(usedPercent: 10, resetsAt: now.addingTimeInterval(3600))
        let secondary = CodexRateLimitWindow(usedPercent: 20, resetsAt: now.addingTimeInterval(7200))

        let classified = probe.classifiedWindows(primary: primary, secondary: secondary, now: now)
        #expect(classified.fiveHour == primary)
        #expect(classified.weekly == secondary)

        // A reset more than 24h out proves a multi-day window even without a duration.
        let longReset = CodexRateLimitWindow(usedPercent: 30, resetsAt: now.addingTimeInterval(3 * 86_400))
        let solo = probe.classifiedWindows(primary: longReset, secondary: nil, now: now)
        #expect(solo.fiveHour == nil)
        #expect(solo.weekly == longReset)
    }

    @Test
    func readResponseReturnsMatchingPayload() async throws {
        let stream = AsyncStream<String> { continuation in
            continuation.yield("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ignored\":true}}")
            continuation.yield("not json")
            continuation.yield("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"rateLimits\":{}}}")
            continuation.finish()
        }

        let payload = try await readResponse(withID: 2, from: stream)

        #expect(payload["id"] as? Int == 2)
        #expect((payload["result"] as? [String: Any]) != nil)
    }

    @Test
    func readResponseThrowsMatchingServerError() async {
        let stream = AsyncStream<String> { continuation in
            continuation.yield("{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"message\":\"No session\"}}")
            continuation.finish()
        }

        do {
            _ = try await readResponse(withID: 2, from: stream)
            Issue.record("Expected invalid response error")
        } catch let error as ProcessRunnerError {
            guard case .invalidResponse(let message) = error else {
                Issue.record("Unexpected error type: \(error)")
                return
            }
            #expect(message == "No session")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
