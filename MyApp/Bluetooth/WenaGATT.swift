import CoreBluetooth

/// Bluetooth identifiers for the Wena 3 band, from Docs/wena3-protocol-spec.md section 1.
///
/// "GATT" is the Bluetooth name for how a device organises its data:
/// services (folders) that contain characteristics (individual values you can read or write).
/// Every Wena UUID follows the pattern 4EFDxxxx-A6C1-16F0-062F-F196CF496695,
/// where xxxx is a short id such as 1501.
nonisolated enum WenaGATT {
    /// The name the band advertises over Bluetooth.
    static let advertisedName = "WNW-21A"

    /// Builds a full Wena UUID from its 4-digit short id.
    static func uuid(_ shortID: String) -> CBUUID {
        CBUUID(string: "4EFD\(shortID)-A6C1-16F0-062F-F196CF496695")
    }

    /// Service 1501: the "common" service that holds device info and battery.
    static let commonService = uuid("1501")

    /// Characteristic 1514 (write): device settings, including time and time zone.
    static let controlCharacteristic = uuid("1514")

    /// Characteristic 1520 (read): firmware name and serial number.
    static let infoCharacteristic = uuid("1520")

    /// Characteristic 1521 (read): battery level.
    static let stateCharacteristic = uuid("1521")

    /// Service 4001: the "notification" service, used for weather, calendar and music text.
    static let notificationService = uuid("4001")

    /// Characteristic 4002 (write): weather and other data shown on the band.
    static let notificationCharacteristic = uuid("4002")

    /// Service 3001: the activity log service.
    static let activityService = uuid("3001")

    /// Characteristic 3002 (write requests, notify data stream): activity sync.
    static let activityCharacteristic = uuid("3002")

    /// Characteristic 1503 (mode). Not used, but known, so it's never mistaken for the list.
    static let modeCharacteristic = uuid("1503")

    /// A characteristic found in service 1501, reduced to what the list search needs.
    struct FoundCharacteristic: Equatable {
        let uuid: CBUUID
        let writable: Bool
    }

    /// The per-app notification list characteristic (spec 15.3): handle `0x102B` in our capture,
    /// the next characteristic after 1514 in service 1501. Its UUID wasn't in the capture, so it's
    /// found by position: the first writable characteristic after 1514 that isn't one we know.
    /// `found` is in the order iOS discovered them (the band's handle order).
    static func notificationListCharacteristic(in found: [FoundCharacteristic]) -> CBUUID? {
        let known: Set<CBUUID> = [controlCharacteristic, infoCharacteristic, stateCharacteristic, modeCharacteristic]
        guard let control = found.firstIndex(where: { $0.uuid == controlCharacteristic }) else { return nil }
        return found[(control + 1)...].first { $0.writable && !known.contains($0.uuid) }?.uuid
    }

    /// A line for the event log listing 1501's characteristics, so the list UUID gets recorded.
    static func describe(_ found: [FoundCharacteristic], list: CBUUID?) -> String {
        let names = found.map { item in
            let id = shortID(item.uuid) ?? item.uuid.uuidString
            return item.writable ? "\(id) (write)" : id
        }
        let listText = list.map { "list = \(shortID($0) ?? $0.uuidString)" } ?? "list not found"
        return "1501 characteristics: \(names.joined(separator: ", ")); \(listText)"
    }

    /// The 4-digit short id of a Wena UUID, or nil for other UUIDs.
    static func shortID(_ uuid: CBUUID) -> String? {
        let text = uuid.uuidString.uppercased()
        guard text.count == 36, text.hasPrefix("4EFD"), text.hasSuffix("-A6C1-16F0-062F-F196CF496695") else { return nil }
        return String(text.dropFirst(4).prefix(4))
    }
}
