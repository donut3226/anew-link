import Foundation

/// The text shown on the band's music screen (spec section 5).
nonisolated enum MusicText {

    /// Gadgetbridge cuts the text to 99 characters.
    static let maxCharacters = 99
    /// The length goes in one byte, so the UTF-8 text can't be longer than 255 bytes.
    static let maxBytes = 255

    /// "Song / Artist", just "Song" if there's no artist, or "" if nothing is playing.
    static func format(title: String?, artist: String?) -> String {
        let song = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let singer = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !song.isEmpty else { return "" }
        return singer.isEmpty ? song : "\(song) / \(singer)"
    }

    /// Cuts the text to fit both limits. Swift's `Character` is a whole visible character
    /// (an emoji or accented letter can be several bytes), so cutting by Character never splits one.
    static func limited(_ text: String) -> String {
        var result = String(text.prefix(maxCharacters))
        while result.utf8.count > maxBytes {
            result.removeLast()
        }
        return result
    }
}

nonisolated extension WenaPackets {

    /// Music text: 0x05, length (number of UTF-8 bytes), then the text. Written to 4002.
    /// Empty text clears the band's music screen.
    static func musicText(_ text: String) -> Data {
        let bytes = Array(MusicText.limited(text).utf8)
        return Data([0x05, UInt8(bytes.count)] + bytes)
    }
}
