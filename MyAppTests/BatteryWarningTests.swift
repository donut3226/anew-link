import Foundation
import Testing
@testable import MyApp

struct BatteryWarningTests {

    @Test func warnsOnceWhenLow() {
        #expect(BatteryWarningRule.next(percent: 20, alreadyWarned: false) == (true, true))
        #expect(BatteryWarningRule.next(percent: 15, alreadyWarned: true) == (false, true))
    }

    @Test func noWarningAboveLow() {
        #expect(BatteryWarningRule.next(percent: 25, alreadyWarned: false) == (false, false))
    }

    @Test func chargingRearms() {
        #expect(BatteryWarningRule.next(percent: 25, alreadyWarned: true) == (false, true))
        #expect(BatteryWarningRule.next(percent: 31, alreadyWarned: true) == (false, false))
    }

    /// Focus sync: all-day do not disturb on, then back to the user's own setting.
    @Test func focusDoNotDisturbPackets() {
        var s = BandSettings()
        s.doNotDisturbOn = true
        s.doNotDisturbStart = BandClockTime(hour: 22, minute: 30)
        #expect([UInt8](WenaSettings.focusDoNotDisturb(on: true, s)) == [0x14, 0x01, 0, 0, 23, 59])
        #expect([UInt8](WenaSettings.focusDoNotDisturb(on: false, s)) == [0x14, 0x01, 22, 30, 6, 0])
    }
}
