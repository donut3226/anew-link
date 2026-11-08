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
}
