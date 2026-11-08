import Foundation
import Testing
@testable import MyApp

/// Checks the CRC-16 against the published check value for CRC-16/CMS
/// (poly 0x8005, init 0xFFFF, no reflection, no final XOR), as described in spec section 7.
struct WenaCRC16Tests {

    @Test func standardCheckValue() {
        #expect(WenaCRC16.checksum(Array("123456789".utf8)) == 0xAEE7)
    }

    @Test func emptyInputIsStartValue() {
        #expect(WenaCRC16.checksum([UInt8]()) == 0xFFFF)
    }

    @Test func changingOneByteChangesTheCRC() {
        #expect(WenaCRC16.checksum([0x01, 0x02, 0x03]) != WenaCRC16.checksum([0x01, 0x02, 0x04]))
    }
}
