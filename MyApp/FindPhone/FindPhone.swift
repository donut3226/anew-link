import AudioToolbox
import AVFoundation
import Foundation
import Observation
import UIKit
import UserNotifications

/// Rings the phone when the band asks for it (request type 2, "Locate phone").
///
/// - App on screen: plays `FindPhone.wav` on a loop and vibrates, until "Found it" is tapped
///   or 30 seconds pass. The sound ignores the silent switch but follows the media volume
///   (the volume buttons), so at volume zero only the vibration is felt.
/// - App in the background or phone locked: shows a notification with the same chime.
///   iOS mutes notification sounds when the silent switch is on; only apps Apple approves
///   for "critical alerts" can get around that.
///
/// Off until the user switches it on, which is also when notification permission is asked.
@Observable
final class FindPhone {

    /// The settings key for the switch (also used by `@AppStorage` in the screen).
    static let enabledKey = "findPhoneEnabled"
    static let soundFile = "FindPhone.wav"
    private static let maxRinging: Duration = .seconds(30)

    private(set) var isRinging = false
    /// When the band last asked (shown on screen), this launch only.
    private(set) var lastRequest: Date?
    private(set) var permissionDenied = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var vibrateTask: Task<Void, Never>?

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    /// Called when the switch changes: asks for notification permission the first time.
    func enabledChanged() async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        permissionDenied = !granted
    }

    /// The band asked to find the phone. Returns a short line for the log.
    func bandAsked() async -> String {
        lastRequest = Date()
        guard isEnabled else { return "Locate phone not answered: switched off" }
        if UIApplication.shared.applicationState == .active {
            return startRinging() ? "Rang the phone (sound)" : "Locate phone: couldn't play the sound"
        }
        return await notify() ? "Rang the phone (notification)" : "Locate phone: notification not allowed"
    }

    /// "Found it": stops the sound.
    func stop() {
        stopTask?.cancel()
        stopTask = nil
        vibrateTask?.cancel()
        vibrateTask = nil
        player?.stop()
        player = nil
        isRinging = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func startRinging() -> Bool {
        guard !isRinging else { return true }
        guard let url = Bundle.main.url(forResource: Self.soundFile, withExtension: nil) else { return false }
        do {
            // "Playback" plays even with the silent switch on (like an alarm or a video).
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // until stopped
            player.volume = 1
            player.play()
            self.player = player
        } catch {
            return false
        }
        isRinging = true
        // Vibrate every 1.5 seconds as well: vibration works in silent mode and at any volume.
        vibrateTask = Task {
            while !Task.isCancelled {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.maxRinging)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        return true
    }

    private func notify() async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Your band is looking for this phone"
        content.body = "Here it is!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(Self.soundFile))
        // A fixed identifier, so repeated presses replace the notification instead of piling up.
        let request = UNNotificationRequest(identifier: "findPhone", content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
