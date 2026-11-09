import Foundation
import Testing
@testable import MyApp

/// Checks where an automatic activity sync starts.
struct ActivityWindowTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 60 * 60

    @Test func neverSavedAsksForTheLastDay() {
        #expect(ActivityWindow.start(lastSaved: nil, now: now) == now.addingTimeInterval(-24 * hour))
    }

    @Test func recentSaveStartsOneHourEarlier() {
        let lastSaved = now.addingTimeInterval(-30 * 60)
        #expect(ActivityWindow.start(lastSaved: lastSaved, now: now) == lastSaved.addingTimeInterval(-hour))
    }

    @Test func oldSaveIsCappedAtOneDay() {
        let lastSaved = now.addingTimeInterval(-3 * 24 * hour)
        #expect(ActivityWindow.start(lastSaved: lastSaved, now: now) == now.addingTimeInterval(-24 * hour))
    }

    @Test func saveJustUnderADayAgoIsStillCapped() {
        // 23.5 h ago minus the 1 h overlap would be 24.5 h: capped to 24 h.
        let lastSaved = now.addingTimeInterval(-23.5 * hour)
        #expect(ActivityWindow.start(lastSaved: lastSaved, now: now) == now.addingTimeInterval(-24 * hour))
    }
}

/// Checks when an automatic activity sync is due (every 2 hours).
struct ActivityOnOpenTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func dueWhenNeverSaved() {
        #expect(ActivityWindow.isDue(lastSaved: nil, now: now))
    }

    @Test func notDueNinetyMinutesLater() {
        #expect(!ActivityWindow.isDue(lastSaved: now.addingTimeInterval(-90 * 60), now: now))
    }

    @Test func dueAfterTwoHours() {
        #expect(ActivityWindow.isDue(lastSaved: now.addingTimeInterval(-2 * 60 * 60), now: now))
    }
}
