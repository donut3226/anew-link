import Foundation
import MediaPlayer
import Observation

/// Shows the song playing in Apple Music on the band's music screen.
///
/// The band asks with a type 11 "Music info" request when its music screen opens, and we answer
/// with "Song / Artist" (the 0x05 packet). While the app is running, a song change is sent too.
@Observable
final class NowPlayingSync {

    /// The settings key for the "Show song title on band" switch.
    static let enabledKey = "showSongTitleOnBand"

    enum Status: Equatable {
        case idle
        /// `text` is what the band was sent ("" means the screen was cleared).
        case sent(text: String, at: Date)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var authorization = MPMediaLibrary.authorizationStatus()

    @ObservationIgnored private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private weak var connection: BandConnection?
    @ObservationIgnored private var songChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var lastSentText: String?

    /// Off until the user switches it on (which is also when we ask for permission).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    var permissionDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Hooks into the band's requests. Called once when the screen appears.
    func attach(to connection: BandConnection) {
        self.connection = connection
        connection.onBandRequest = { [weak self] request in
            guard request.type == 11 else { return }   // "Music info"
            Task { await self?.send(force: true) }
        }
        updateSongWatching()
    }

    /// Called when the switch changes.
    func enabledChanged() async {
        if isEnabled && authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        updateSongWatching()
        if isEnabled {
            await send(force: true)
        }
    }

    /// Debug only: sends a fixed text, to check how the band shows it.
    func sendTest() async {
        #if DEBUG
        await deliver("Buckle Link test / Music")
        #endif
    }

    /// Sends the current song. `force` sends even if it's the same as last time
    /// (the band asked, so it wants an answer).
    private func send(force: Bool) async {
        guard isEnabled, authorization == .authorized,
              let connection, connection.state == .connected else { return }
        let item = player.nowPlayingItem
        let text = MusicText.format(title: item?.title, artist: item?.artist)
        guard force || text != lastSentText else { return }
        await deliver(text)
    }

    private func deliver(_ text: String) async {
        guard let connection else { return }
        let limited = MusicText.limited(text)
        if let error = await connection.sendMusicText(WenaPackets.musicText(limited)) {
            status = .failed(error)
            return
        }
        lastSentText = text
        status = .sent(text: limited, at: Date())
        // The log notes the length only, not the song.
        connection.events.add(BandEvent(date: Date(), kind: .info,
                                        detail: "Answered music info (\(limited.count) characters)"))
    }

    /// Watches Apple Music for song changes while the switch is on and permission is granted.
    private func updateSongWatching() {
        let shouldWatch = isEnabled && authorization == .authorized
        if shouldWatch, songChangeObserver == nil {
            player.beginGeneratingPlaybackNotifications()
            songChangeObserver = NotificationCenter.default.addObserver(
                forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.send(force: false) }
            }
        } else if !shouldWatch, let observer = songChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            player.endGeneratingPlaybackNotifications()
            songChangeObserver = nil
        }
    }
}
