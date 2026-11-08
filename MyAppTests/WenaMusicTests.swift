import Foundation
import Testing
@testable import MyApp

/// Checks the music text packet against spec section 5.
struct WenaMusicTests {

    // MARK: - Formatting

    @Test func songAndArtist() {
        #expect(MusicText.format(title: "Clair de Lune", artist: "Debussy") == "Clair de Lune / Debussy")
    }

    @Test func songOnly() {
        #expect(MusicText.format(title: "Clair de Lune", artist: nil) == "Clair de Lune")
        #expect(MusicText.format(title: "Clair de Lune", artist: "  ") == "Clair de Lune")
    }

    @Test func nothingPlayingIsEmpty() {
        #expect(MusicText.format(title: nil, artist: nil) == "")
        #expect(MusicText.format(title: "", artist: "Someone") == "")
    }

    @Test func spacesAreTrimmed() {
        #expect(MusicText.format(title: "  Song  ", artist: " Artist ") == "Song / Artist")
    }

    // MARK: - Packet

    @Test func asciiPacketBytes() {
        #expect(WenaPackets.musicText("Hi / Me") == Data([0x05, 0x07, 0x48, 0x69, 0x20, 0x2F, 0x20, 0x4D, 0x65]))
    }

    @Test func emptyClears() {
        #expect(WenaPackets.musicText("") == Data([0x05, 0x00]))
    }

    // MARK: - Limits

    @Test func longTextIsCutTo99Characters() {
        let packet = WenaPackets.musicText(String(repeating: "a", count: 150))
        #expect(packet[1] == 99)
        #expect(packet.count == 2 + 99)
    }

    @Test func multiByteTextStaysWithin255Bytes() throws {
        // 99 Japanese characters are 297 bytes in UTF-8: too many for the one-byte length.
        let packet = WenaPackets.musicText(String(repeating: "音", count: 99))
        #expect(Int(packet[1]) == packet.count - 2)
        #expect(packet.count - 2 <= 255)
        // What's left must still be valid UTF-8 made of whole characters.
        let text = try #require(String(data: packet.dropFirst(2), encoding: .utf8))
        #expect(text.allSatisfy { $0 == "音" })
    }

    @Test func emojiIsNeverSplit() throws {
        // 98 letters, then a 4-byte emoji at the cut point, then more.
        let packet = WenaPackets.musicText(String(repeating: "a", count: 98) + "🎵🎵🎵")
        let text = try #require(String(data: packet.dropFirst(2), encoding: .utf8))
        #expect(text == String(repeating: "a", count: 98) + "🎵")
        #expect(Int(packet[1]) == text.utf8.count)
    }
}
