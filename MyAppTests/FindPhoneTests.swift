import AVFoundation
import Foundation
import Testing
@testable import MyApp

/// Checks the find-my-phone chime is bundled and fits iOS's notification sound limit.
struct FindPhoneTests {

    @Test func chimeIsInTheAppAndUnder30Seconds() throws {
        let url = try #require(Bundle.main.url(forResource: FindPhone.soundFile, withExtension: nil))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 1)
        #expect(player.duration < 30)   // iOS plays the default sound instead of longer ones
    }
}
