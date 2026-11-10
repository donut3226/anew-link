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
        #expect(opcodes == [0x08, 0x09, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C])
        // Never the packets we don't send (body details only once entered).
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

/// The test notification follows the "Try this notification pattern" packet Sony's app sent.
struct WenaTestNotificationTests {

    @Test func headerMatchesSonysTryPacket() {
        // Sony (Gmail set to red, siren, 3 times): 00 01 03 08 03 14 13 01 00 00 | id | time | texts.
        // Ours: white, basic, once, with our own texts.
        let date = WenaPackets.epoch.addingTimeInterval(216_459_349)
        let packet = [UInt8](WenaTestNotification.packet(id: 9, date: date))
        #expect(Array(packet.prefix(10)) == [0x00, 0x07, 0x03, 0x02, 0x01, 9, 14, 0x01, 0x00, 0x00])
        #expect(Array(packet[10..<14]) == [0x09, 0x00, 0x00, 0x00])
        #expect(Array(packet[14..<18]) == [0x55, 0xE8, 0xE6, 0x0C])   // same timestamp bytes as Sony's
        #expect(String(decoding: packet[18..<27], as: UTF8.self) == "Anew Link")
        #expect(String(decoding: packet[27...], as: UTF8.self) == "Vibration test")
    }
}

/// Status page (`0x18`) and tool menu (`0x19`) order (spec 15.2, 15.5).
struct WenaPageOrderTests {

    private func bytes(_ data: Data) -> [UInt8] { [UInt8](data) }

    @Test func defaultsMatchSonyRewrite() {
        let s = BandSettings()
        #expect(bytes(WenaSettings.statusPages(s)) == [0x18, 0x01, 0x03, 0x07, 0x04, 0x05, 0x02, 0x06])
        #expect(bytes(WenaSettings.menu(s)) == [0x19, 0x07, 0x02, 0x01, 0x03, 0x09, 0x08, 0x04, 0x06, 0x05, 0x00])
    }

    @Test func reorderedListIsSentInOrder() {
        var s = BandSettings()
        var pages = s.statusOrder
        pages.insert(pages.remove(at: 5), at: 0)             // Sleep first
        s.statusOrder = pages
        #expect(bytes(WenaSettings.statusPages(s)) == [0x18, 0x02, 0x01, 0x03, 0x07, 0x04, 0x05, 0x06])
    }

    @Test func incompleteOrRepeatedListsAreCompleted() {
        var s = BandSettings()
        s.menuOrder = [.music, .music, .weather]
        #expect(s.menuOrder.count == 10)
        #expect(Array(s.menuOrder.prefix(2)) == [.music, .weather])
        #expect(Set(s.menuOrder) == Set(MenuItem.allCases))
    }

    @Test func sendAllFollowsSonysOrder() {
        let opcodes = WenaSettings.allPackets(BandSettings()).map { [UInt8]($0)[0] }
        #expect(opcodes == [0x08, 0x09, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C])
    }

    /// Settings saved by builds before the page order existed still load.
    @Test func oldSavedSettingsStillDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BandSettings())) as! [String: Any]
        json.removeValue(forKey: "statusOrderStored")
        json.removeValue(forKey: "menuOrderStored")
        json["stepGoal"] = 8000
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(BandSettings.self, from: data)
        #expect(decoded.stepGoal == 8000)
        #expect(decoded.statusOrder == StatusPage.sonyDefault)
    }
}

/// Body details (`0x1D`): layout from spec 4, order confirmed by Sony's capture (15.2). Values made up.
struct WenaBodyDetailsTests {

    @Test func layoutHeightThenWeightTimesTen() {
        let body = BodyDetails(sex: .male, birthYear: 1985, birthMonth: 7, birthDay: 21, heightCm: 172, weightKg: 68.5)
        #expect([UInt8](WenaSettings.bodyDetails(body)) == [0x1D, 0x01, 0xC1, 0x07, 7, 21, 0xB8, 0x06, 0xAD, 0x02])
    }

    /// Sony's capture sent `01` while Sony's screen showed Male (10 Nov 2026).
    @Test func sexByteMaleIsOne() {
        #expect(BodyDetails.Sex.male.rawValue == 0x01)
        #expect([UInt8](WenaSettings.bodyDetails(BodyDetails(sex: .male)))[1] == 0x01)
        #expect([UInt8](WenaSettings.bodyDetails(BodyDetails(sex: .female)))[1] == 0x00)
    }

    @Test func notSentUntilEntered() {
        var s = BandSettings()
        #expect(WenaSettings.packets(for: .bodyDetails, s).isEmpty)
        #expect(!WenaSettings.allPackets(s).contains { $0.first == 0x1D })
        s.body = BodyDetails()
        #expect(WenaSettings.allPackets(s).last?.first == 0x1D)
    }
}
