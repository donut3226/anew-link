import Testing
@testable import MyApp

struct CalendarChoiceTests {

    @Test func untickingAddsToExclusions() {
        #expect(CalendarChoice.updatedExclusions([], id: "work", included: false) == ["work"])
    }

    @Test func tickingRemovesFromExclusions() {
        #expect(CalendarChoice.updatedExclusions(["work", "home"], id: "work", included: true) == ["home"])
    }

    @Test func countText() {
        let all = [CalendarChoice(id: "a", title: "A", account: "", isIncluded: true),
                   CalendarChoice(id: "b", title: "B", account: "", isIncluded: true)]
        #expect(BandStatusContent.calendarCountText(all) == "All")
        var some = all
        some[1].isIncluded = false
        #expect(BandStatusContent.calendarCountText(some) == "1 of 2")
    }
}
