import CoreBluetooth
import Testing
@testable import MyApp

/// Finding the notification list characteristic by its position after 1514 (spec 15.1).
struct WenaGATTTests {

    private func item(_ id: String, writable: Bool) -> WenaGATT.FoundCharacteristic {
        .init(uuid: WenaGATT.uuid(id), writable: writable)
    }

    @Test func listIsTheWritableOneAfter1514() {
        let found = [item("1503", writable: false), item("1520", writable: false), item("1521", writable: false),
                     item("1514", writable: true), item("1530", writable: true)]
        #expect(WenaGATT.notificationListCharacteristic(in: found) == WenaGATT.uuid("1530"))
    }

    @Test func skipsReadOnlyAndKnownCharacteristics() {
        let found = [item("1514", writable: true), item("1503", writable: true), item("1531", writable: false),
                     item("1532", writable: true)]
        #expect(WenaGATT.notificationListCharacteristic(in: found) == WenaGATT.uuid("1532"))
    }

    @Test func nothingWhen1514IsLastOrMissing() {
        #expect(WenaGATT.notificationListCharacteristic(in: [item("1530", writable: true), item("1514", writable: true)]) == nil)
        #expect(WenaGATT.notificationListCharacteristic(in: [item("1530", writable: true)]) == nil)
    }

    @Test func describeUsesShortIds() {
        let found = [item("1520", writable: false), item("1514", writable: true), item("1530", writable: true)]
        let line = WenaGATT.describe(found, list: WenaGATT.uuid("1530"))
        #expect(line == "1501 characteristics: 1520, 1514 (write), 1530 (write); list = 1530")
        #expect(WenaGATT.shortID(CBUUID(string: "180F")) == nil)
    }
}
