import Foundation
import Testing
@testable import MyApp

/// Checks when automatic weather (and time) updates are due.
struct AutoSyncTests {

    private func at(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    /// A calendar fixed to Adelaide, so "a new day" doesn't depend on where the tests run.
    private var adelaide: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Adelaide")!
        return calendar
    }

    private let summerOffset = 10 * 3600 + 1800   // +10:30
    private let winterOffset = 9 * 3600 + 1800    // +9:30

    @Test func dueWhenNeverRun() throws {
        #expect(WeatherSchedule.isDue(lastSent: nil, lastOffset: nil,
                                      now: try at("2026-11-08T03:00:00Z"),
                                      currentOffset: summerOffset, calendar: adelaide))
    }

    @Test func notDueTwoHoursLaterSameDay() throws {
        // 13:30 and 15:30 in Adelaide.
        #expect(!WeatherSchedule.isDue(lastSent: try at("2026-11-08T03:00:00Z"), lastOffset: summerOffset,
                                       now: try at("2026-11-08T05:00:00Z"),
                                       currentOffset: summerOffset, calendar: adelaide))
    }

    @Test func dueAfterThreeHoursAndAMinute() throws {
        #expect(WeatherSchedule.isDue(lastSent: try at("2026-11-08T03:00:00Z"), lastOffset: summerOffset,
                                      now: try at("2026-11-08T06:01:00Z"),
                                      currentOffset: summerOffset, calendar: adelaide))
    }

    @Test func dueAcrossMidnightEvenAfterTenMinutes() throws {
        // 23:55 on the 8th, then 00:05 on the 9th, Adelaide time (+10:30).
        #expect(WeatherSchedule.isDue(lastSent: try at("2026-11-08T13:25:00Z"), lastOffset: summerOffset,
                                      now: try at("2026-11-08T13:35:00Z"),
                                      currentOffset: summerOffset, calendar: adelaide))
    }

    @Test func dueWhenTimeZoneOffsetChanges() throws {
        // Daylight saving starts: +9:30 becomes +10:30, only 30 minutes later.
        #expect(WeatherSchedule.isDue(lastSent: try at("2026-11-08T03:00:00Z"), lastOffset: winterOffset,
                                      now: try at("2026-11-08T03:30:00Z"),
                                      currentOffset: summerOffset, calendar: adelaide))
    }
}
