import Foundation

/// What we read from characteristic 1520.
nonisolated struct BandInfo: Equatable {
    /// For example "2.40JP".
    let firmwareName: String
    let serialNumber: Int32
}

/// Turns raw bytes from the band into Swift values (spec section 4).
///
/// These functions only look at bytes and never touch Bluetooth,
/// so they can be checked with unit tests without a band.
nonisolated enum BandInfoParser {

    /// Characteristic 1520: bytes 0-7 are the ASCII firmware name,
    /// bytes 8-11 are the serial number (int32, little-endian).
    /// Returns nil if the data is too short.
    static func parseInfo(_ data: Data) -> BandInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return nil }

        // The name may be padded with zero bytes, so stop at the first zero.
        let nameBytes = bytes[0..<8].prefix { $0 != 0 }
        let firmwareName = String(decoding: nameBytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)

        // Little-endian means the lowest byte comes first.
        let rawSerial = UInt32(bytes[8])
            | UInt32(bytes[9]) << 8
            | UInt32(bytes[10]) << 16
            | UInt32(bytes[11]) << 24

        return BandInfo(firmwareName: firmwareName,
                        serialNumber: Int32(bitPattern: rawSerial))
    }

    /// Characteristic 1521: byte 0 is the battery percentage.
    /// Returns nil if there is no data. Any further bytes are ignored.
    static func parseBattery(_ data: Data) -> Int? {
        guard let first = data.first else { return nil }
        // The spec treats this byte as signed, so keep the result within 0-100.
        let percent = Int(Int8(bitPattern: first))
        return min(max(percent, 0), 100)
    }
}
