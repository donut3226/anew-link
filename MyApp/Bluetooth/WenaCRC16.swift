/// The CRC-16 the band uses to protect activity packets (spec section 7).
///
/// A CRC is a short "fingerprint" of some bytes. The band sends one with each packet;
/// we work it out again from the bytes we received, and if the two differ, the packet got damaged.
///
/// This variant (known as CRC-16/CMS): polynomial 0x8005, start value 0xFFFF,
/// bits processed most-significant first, no final XOR.
nonisolated enum WenaCRC16 {

    static func checksum<Bytes: Sequence>(_ bytes: Bytes) -> UInt16 where Bytes.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                // If the top bit is set, shift and mix in the polynomial; otherwise just shift.
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x8005 : crc << 1
            }
        }
        return crc
    }
}
