import Foundation

/// Builds packets to send to the band (spec section 4).
///
/// Like BandInfoParser, these functions only make bytes and never touch Bluetooth,
/// so unit tests can check them against the spec without a band.
/// Only packets the spec has verified belong here.
nonisolated enum WenaPackets {

    /// The Wena clock starts at 2020-01-01 00:00:00 UTC (1,577,836,800 seconds after 1970).
    static let epoch = Date(timeIntervalSince1970: 1_577_836_800)

    /// Seconds since the Wena epoch, as the signed 32-bit number the band expects.
    static func wenaTimestamp(for date: Date) -> Int32 {
        let seconds = date.timeIntervalSince(epoch).rounded(.down)
        return Int32(clamping: Int64(seconds))
    }

    /// Set time, 5 bytes: 0x10, then the Wena timestamp (int32, little-endian).
    /// Written to control characteristic 1514.
    static func setTime(_ date: Date) -> Data {
        var data = Data([0x10])
        // withUnsafeBytes hands us the raw bytes of the number;
        // .littleEndian makes sure the lowest byte comes first.
        withUnsafeBytes(of: wenaTimestamp(for: date).littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// Set time zone, 3 bytes: 0x11, signed hour offset, minute offset.
    /// Written to control characteristic 1514.
    ///
    /// Returns nil for negative zones that aren't whole hours (for example -3:30),
    /// because the spec marks that case as UNVERIFIED and we only send verified packets.
    static func setTimeZone(secondsFromGMT: Int) -> Data? {
        let hours = secondsFromGMT / 3600
        let minutes = (abs(secondsFromGMT) % 3600) / 60
        if secondsFromGMT < 0 && minutes != 0 {
            return nil
        }
        return Data([0x11, UInt8(bitPattern: Int8(clamping: hours)), UInt8(minutes)])
    }
}
