import Foundation
import Testing
@testable import MyApp

/// Checks the settings packets byte for byte against what Sony's app sent (spec 15.2 and 15.5).
struct WenaSettingsTests {

    private func bytes(_ data: Data) -> [UInt8] { [UInt8](data) }

    /// The defaults reproduce Sony's "Rewrite settings" packets for these groups.
    @Test func defaultsMatchSonyRewrite() {
        let s = BandSettings()
        #expect(bytes(WenaSettings.vibration(s)) == [0x08, 0x00, 0x00])
        #expect(bytes(WenaSettings.disconnectAlert(s)) == [0x09, 0x00])
        #expect(bytes(WenaSettings.doNotDisturb(s)) == [0x14, 0x00, 0x00, 0x00, 0x06, 0x00])
        #expect(bytes(WenaSettings.dayStart(s)) == [0x16, 0x00])
        #expect(bytes(WenaSettings.stepGoal(s)) == [0x17, 0x01, 0x70, 0x17, 0x00, 0x00])
        #expect(bytes(WenaSettings.display(s)) == [0x1A, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x07])
        #expect(bytes(WenaSettings.homeIcons(s)) == [0x1B, 0x00, 0x0E, 0x00, 0x0C, 0x00, 0x0A])
        #expect(bytes(WenaSettings.buttons(s)) == [0x1C, 0x07, 0x00, 0x06, 0x00])
    }

    @Test func vibrationStrengthAndStopAtRest() {
        var s = BandSettings()
        s.vibration = .strong
        #expect(bytes(WenaSettings.vibration(s)) == [0x08, 0x02, 0x00])
        s.vibration = .weak
        #expect(bytes(WenaSettings.vibration(s)) == [0x08, 0x01, 0x00])
        s.vibration = .normal
        s.stopVibratingAtRest = true
        #expect(bytes(WenaSettings.vibration(s)) == [0x08, 0x00, 0x01])
    }

    @Test func disconnectAlertInFiveSecondSteps() {
        var s = BandSettings()
        s.disconnectAlertOn = true
        s.disconnectAlertSeconds = 5
        #expect(bytes(WenaSettings.disconnectAlert(s)) == [0x09, 0x01])
        s.disconnectAlertSeconds = 120
        #expect(bytes(WenaSettings.disconnectAlert(s)) == [0x09, 0x18])
        s.disconnectAlertOn = false
        #expect(bytes(WenaSettings.disconnectAlert(s)) == [0x09, 0x00])
    }

    @Test func autoPowerOffWindow() {
        var s = BandSettings()
        s.autoPowerOffOn = true
        #expect(bytes(WenaSettings.autoPowerOff(s)) == [0x15, 0x01, 0x16, 0x00, 0x08, 0x00])
        s.autoPowerOffOn = false
        #expect(bytes(WenaSettings.autoPowerOff(s)) == [0x15, 0x00, 0x16, 0x00, 0x08, 0x00])
    }

    @Test func doNotDisturbOn() {
        var s = BandSettings()
        s.doNotDisturbOn = true
        #expect(bytes(WenaSettings.doNotDisturb(s)) == [0x14, 0x01, 0x00, 0x00, 0x06, 0x00])
    }

    @Test func buttonActionsSeenInSonysApp() {
        var s = BandSettings()
        s.longPress = .musicPrevious
        s.doublePress = .findPhone
        #expect(bytes(WenaSettings.buttons(s)) == [0x1C, 0x10, 0x03, 0x03, 0x00])
        s.longPress = .none
        s.doublePress = .musicScreen
        #expect(bytes(WenaSettings.buttons(s)) == [0x1C, 0x00, 0x00, 0x10, 0x00])
    }

    @Test func homeIconsAreSentAfterTheDisplayPacket() {
        var s = BandSettings()
        s.homeLeft = .sleep
        let packets = WenaSettings.packets(for: .homeIcons, s).map(bytes)
        #expect(packets == [[0x1A, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x07],
                            [0x1B, 0x00, 0x0B, 0x00, 0x0C, 0x00, 0x0A]])
    }

    @Test func sendAllCoversEveryOpcodeOnce() {
        let opcodes = WenaSettings.allPackets(BandSettings()).compactMap(\.first)
        #expect(opcodes == [0x08, 0x09, 0x14, 0x15, 0x16, 0x17, 0x1A, 0x1B, 0x1C])
        // Never the packets we don't send.
        #expect(!opcodes.contains(0x12))
        #expect(!opcodes.contains(0x1D))
        #expect(!opcodes.contains(0xC0))
    }

    @Test func stepGoalLittleEndian() {
        var s = BandSettings()
        s.stepGoal = 10_000
        s.goalNotification = false
        #expect(bytes(WenaSettings.stepGoal(s)) == [0x17, 0x00, 0x10, 0x27, 0x00, 0x00])
    }
}
