import Foundation

/// The app's long-lived objects: the Bluetooth connection and everything that sends to the band.
///
/// They're created when the app launches, not when the screen appears, because iOS can relaunch
/// the app in the background for the band (state restoration) without ever showing the screen.
/// The screen just borrows them.
final class AppServices {
    let connection = BandConnection()
    let weatherSync = WeatherSync()
    let autoSync = AutoSync()
    let activityAutoSync = ActivityAutoSync()
    let healthSync = HealthSync()
    let nowPlaying = NowPlayingSync()
    let findPhone = FindPhone()

    /// Called once, at launch.
    func start() {
        nowPlaying.attach(to: connection)

        // The band's requests (spec section 6). Only these four are answered.
        connection.onBandRequest = { [weak self] request in
            guard let self else { return }
            switch request.type {
            case 0:  // Sync tick, every 30 minutes
                Task { await self.activityAutoSync.answerSyncTick(connection: self.connection, health: self.healthSync) }
            case 2:  // Locate phone
                Task {
                    let outcome = await self.findPhone.bandAsked()
                    self.connection.events.add(BandEvent(date: Date(), kind: .info, detail: outcome))
                }
            case 3:  // Get weather
                Task { await self.autoSync.answerWeatherRequest(connection: self.connection, weather: self.weatherSync) }
            case 11: // Music info
                Task { await self.nowPlaying.answerMusicRequest() }
            default:
                break
            }
        }

        connection.start()
    }
}
