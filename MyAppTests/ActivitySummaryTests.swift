import Foundation
import Testing
@testable import MyApp

struct ActivitySummaryTests {

    private func utc(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    /// A calendar fixed to UTC, so "today" doesn't depend on where the tests run.
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func summarisesStepsAndHeartRate() throws {
        let now = try utc("2026-01-02T00:30:00Z")
        let samples = [
            ActivitySample(type: .steps, date: try utc("2026-01-01T00:00:00Z"), value: 100),   // over 24 h ago
            ActivitySample(type: .steps, date: try utc("2026-01-01T23:50:00Z"), value: 10),    // yesterday
            ActivitySample(type: .steps, date: try utc("2026-01-02T00:10:00Z"), value: 20),    // today
            ActivitySample(type: .heartRate, date: try utc("2026-01-02T00:05:00Z"), value: 60),
            ActivitySample(type: .heartRate, date: try utc("2026-01-02T00:20:00Z"), value: 70),
        ]
        let summary = ActivitySummary(samples: samples, now: now, calendar: utcCalendar)

        #expect(summary.stepsToday == 20)
        #expect(summary.stepsLast24Hours == 30)
        #expect(summary.latestHeartRate == 70)
        #expect(summary.latestHeartRateAt == (try utc("2026-01-02T00:20:00Z")))
        #expect(summary.heartRateMin == 60)
        #expect(summary.heartRateMax == 70)
        #expect(summary.newestSampleAt == (try utc("2026-01-02T00:20:00Z")))
        #expect(summary.newestSampleMinutesAgo == 10)
        #expect(summary.stepMinuteCount == 3)
        #expect(summary.heartRateCount == 2)
    }

    @Test func noSamples() throws {
        let summary = ActivitySummary(samples: [], now: try utc("2026-01-02T00:30:00Z"), calendar: utcCalendar)
        #expect(summary.stepsToday == 0)
        #expect(summary.latestHeartRate == nil)
        #expect(summary.newestSampleAt == nil)
        #expect(summary.newestSampleMinutesAgo == nil)
    }
}
