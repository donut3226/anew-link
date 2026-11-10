import Foundation
import Testing
@testable import MyApp

/// Checks the notification list writes against Sony's captured bytes (spec 15.3 and 15.5).
struct WenaNotificationListTests {

    private func bytes(_ data: Data) -> [UInt8] { [UInt8](data) }

    /// Sony's Save for Gmail at position 4: `00 0E 00 05 Gmail 01 03 08 03 01 04 00`.
    @Test func gmailRecordMatchesSonysSave() {
        let gmail = NotifyApp(name: "Gmail", colour: .red, pattern: .siren, count: .threeTimes)
        let writes = WenaNotificationList.fragments(WenaNotificationList.record(gmail, index: 4))
        #expect(writes.count == 1)
        #expect(bytes(writes[0]) == [0x00, 0x0E, 0x00, 0x05] + Array("Gmail".utf8) + [0x01, 0x03, 0x08, 0x03, 0x01, 0x04, 0x00])
    }

    /// Calls: kind 01, name "phone", white, call pattern, repeat (`07 03 01 00 01`), position 0.
    @Test func callRecord() {
        let record = bytes(WenaNotificationList.record(.call(), index: 0))
        #expect(record == [0x01, 0x05] + Array("phone".utf8) + [0x07, 0x03, 0x01, 0x00, 0x01, 0x00, 0x00])
    }

    @Test func offAppHasZeroEnabledByte() {
        var app = NotifyApp(name: "Mail")
        app.isOn = false
        let record = bytes(WenaNotificationList.record(app, index: 1))
        #expect(record[record.count - 3] == 0x00)
    }

    /// A record over 18 bytes continues in fragment 01.
    @Test func longRecordSplitsIntoFragments() {
        let app = NotifyApp(name: "Google Calendar")       // 2 + 15 + 5 + 2 = 24 bytes
        let record = WenaNotificationList.record(app, index: 2)
        #expect(record.count == 24)
        let writes = WenaNotificationList.fragments(record).map(bytes)
        #expect(writes.count == 2)
        #expect(writes[0].count == 20)
        #expect(Array(writes[0].prefix(2)) == [0x00, 18])
        #expect(Array(writes[1].prefix(2)) == [0x01, 6])
        #expect(Array(writes[0].dropFirst(2) + writes[1].dropFirst(2)) == bytes(record))
    }

    /// A record of exactly 18 bytes is followed by an empty `01 00`.
    @Test func exactly18BytesGetsEmptyFragment() {
        let app = NotifyApp(name: "ProtonMai")             // 2 + 9 + 5 + 2 = 18 bytes
        let writes = WenaNotificationList.fragments(WenaNotificationList.record(app, index: 1)).map(bytes)
        #expect(writes.count == 2)
        #expect(writes[0].count == 20)
        #expect(writes[1] == [0x01, 0x00])
    }

    /// Positions count down to 0, calls always last at 0, and the list ends with a lone `04`.
    @Test func wholeListOrderAndEnd() {
        let list = [NotifyApp.call(), NotifyApp(name: "Mail"), NotifyApp(name: "LINE")]
        let writes = WenaNotificationList.packets(for: list).map(bytes)
        #expect(writes.count == 4)
        #expect(Array(writes[0][4..<8]) == Array("Mail".utf8))
        #expect(Array(writes[0].suffix(2)) == [0x02, 0x00])
        #expect(Array(writes[1][4..<8]) == Array("LINE".utf8))
        #expect(Array(writes[1].suffix(2)) == [0x01, 0x00])
        #expect(writes[2][2] == 0x01)                      // kind: call
        #expect(Array(writes[2].suffix(2)) == [0x00, 0x00])
        #expect(writes[3] == [0x04])
    }

    @Test func longNamesAreCutAtACharacterBoundary() {
        let name = String(repeating: "é", count: 20)        // 40 bytes in UTF-8
        let cut = WenaNotificationList.nameBytes(name)
        #expect(cut.count == 30)
        #expect(String(bytes: cut, encoding: .utf8) == String(repeating: "é", count: 15))
    }

    @Test func listIsCappedAndKeepsOneCall() {
        let many = (0..<30).map { NotifyApp(name: "App \($0)") } + [NotifyApp.call(), NotifyApp.call()]
        let ordered = WenaNotificationList.ordered(many)
        #expect(ordered.count == WenaNotificationList.maxApps + 1)
        #expect(ordered.last?.kind == .call)
    }

    @Test func defaultListEndsWithCall() {
        let list = WenaNotificationList.defaultList()
        #expect(list.last?.kind == .call)
        #expect(list.contains { $0.name == "Messages" })
    }

    /// The "Try it" packet carries the app's colour, pattern and count, as Sony's does.
    @Test func tryPacketUsesAppSettings() {
        let packet = bytes(WenaTestNotification.packet(id: 1, date: Date(), colour: 0x01, pattern: 0x08, count: 0x03))
        #expect(Array(packet.prefix(5)) == [0x00, 0x01, 0x03, 0x08, 0x03])
    }
}
