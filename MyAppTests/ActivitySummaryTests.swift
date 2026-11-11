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

    @Test func otherTypesInSummary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let midnight = calendar.startOfDay(for: now)
        let samples = [
            ActivitySample(type: .bodyEnergy, date: now.addingTimeInterval(-120), value: 60),
            ActivitySample(type: .bodyEnergy, date: now.addingTimeInterval(-60), value: 59),
            ActivitySample(type: .vo2, date: midnight.addingTimeInterval(-86_400), value: 43),
            ActivitySample(type: .calories, date: midnight.addingTimeInterval(60), value: 1000),
            ActivitySample(type: .calories, date: midnight.addingTimeInterval(120), value: 1500),
            ActivitySample(type: .calories, date: midnight.addingTimeInterval(-60), value: 9999),
        ]
        let summary = ActivitySummary(samples: samples, now: now, calendar: calendar)
        #expect(summary.latestBodyEnergy == 59)
        #expect(summary.vo2Max == 43)
        #expect(summary.latestStress == nil)
        #expect(summary.caloriesToday == 3)       // 2500 / 1000, rounded
        #expect(summary.calorieMinutes == 2)
        #expect(summary.caloriesFrom == midnight.addingTimeInterval(60))
        #expect(summary.caloriesTo == midnight.addingTimeInterval(120))
    }
}
