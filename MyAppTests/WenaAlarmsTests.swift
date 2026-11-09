import Foundation
import Testing
@testable import MyApp

/// Checks the alarm packets against spec section 9. Made-up alarms only.
struct WenaAlarmsTests {

    @Test func weekdaysMask() {
        // Monday (2) to Friday (6) = bits 1-5.
        #expect(WenaAlarms.repeatMask([2, 3, 4, 5, 6]) == 0x3E)
        #expect(WenaAlarms.repeatMask([1]) == 0x01)        // Sunday
        #expect(WenaAlarms.repeatMask([7]) == 0x40)        // Saturday
        #expect(WenaAlarms.repeatMask([]) == 0x00)         // once
    }

    @Test func specExampleWeekdays0630() {
        let alarm = BandAlarm(isOn: true, hour: 6, minute: 30, repeatDays: [2, 3, 4, 5, 6], smartWakeupMinutes: 0)
        let packets = WenaAlarms.packets(for: [alarm])
        // Slot 0 on, weekdays, no smart margin, 06:30 = 00 02 3E 00 06 1E (spec section 9).
        #expect([UInt8](packets[0]) == [0x06,
                                        0x00, 0x02, 0x3E, 0x00, 0x06, 0x1E,
                                        0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
                                        0x02, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    @Test func alwaysThreePacketsCoveringNineSlots() {
        let packets = WenaAlarms.packets(for: [])
        #expect(packets.count == 3)
        #expect(packets.allSatisfy { $0.count == 19 && $0.first == 0x06 })
        // Slot indexes 0-8, at offsets 1, 7 and 13 of each packet.
        let indexes = packets.flatMap { p in [p[1], p[7], p[13]] }
        #expect(indexes == [0, 1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test func offAlarmAndSmartWakeup() {
        let alarm = BandAlarm(isOn: false, hour: 22, minute: 5, repeatDays: [1, 7], smartWakeupMinutes: 10)
        #expect(WenaAlarms.slotBytes(alarm) == [0x01, 0x41, 10, 22, 5])
    }

    @Test func extraAlarmsBeyondNineAreDropped() {
        let alarms = (0..<12).map { BandAlarm(hour: $0, minute: 0) }
        let packets = WenaAlarms.packets(for: alarms)
        #expect(packets[2][13 + 4] == 8)   // slot 8's hour is the ninth alarm's
    }
}

/// Checks the plain-words alarm labels.
struct AlarmTextTests {

    private var english: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_AU")
        calendar.firstWeekday = 2   // Monday first, as in Australia
        return calendar
    }

    @Test func namedPatterns() {
        #expect(AlarmText.days([], calendar: english) == "Once")
        #expect(AlarmText.days(Set(1...7), calendar: english) == "Every day")
        #expect(AlarmText.days([2, 3, 4, 5, 6], calendar: english) == "Weekdays")
        #expect(AlarmText.days([1, 7], calendar: english) == "Weekends")
    }

    @Test func otherDaysInWeekOrder() {
        #expect(AlarmText.days([1, 2, 4], calendar: english) == "Mon, Wed, Sun")
    }

    @Test func weekStartsOnTheUsersFirstDay() {
        #expect(AlarmText.orderedWeekdays(calendar: english) == [2, 3, 4, 5, 6, 7, 1])
    }
}
