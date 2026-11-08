import Foundation

/// Decides when the band needs fresh weather (and the time, which is sent with it).
/// Pure, so the rule can be unit-tested.
nonisolated enum WeatherSchedule {

    /// How old the last update can be before it's refreshed.
    static let maxAge: TimeInterval = 3 * 60 * 60

    /// - Parameters:
    ///   - lastSent: when the last successful automatic update happened (nil if never).
    ///   - lastOffset: the iPhone's time-zone offset (seconds from GMT) at that update.
    ///   - currentOffset: the offset now. A change means travel or daylight saving.
    static func isDue(lastSent: Date?, lastOffset: Int?, now: Date, currentOffset: Int,
                      calendar: Calendar = .current) -> Bool {
        guard let lastSent, let lastOffset else { return true }   // never run
        if lastOffset != currentOffset { return true }            // time zone changed
        if !calendar.isDate(lastSent, inSameDayAs: now) { return true }   // a new day
        return now.timeIntervalSince(lastSent) > maxAge           // too old
    }
}

/// Sends time and weather by itself when the app connects or comes back to the screen,
/// but only when `WeatherSchedule` says it's due, and only if the user's switch is on.
final class AutoSync {

    /// The settings key for the on/off switch (also used by `@AppStorage` in the screen).
    static let enabledKey = "autoUpdateWeatherAndTime"
    private static let lastSentKey = "autoSync.lastSent"
    private static let lastOffsetKey = "autoSync.lastOffset"

    private let defaults = UserDefaults.standard
    private var isRunning = false

    /// On unless the user has switched it off.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func runIfDue(connection: BandConnection, weather: WeatherSync) async {
        guard isEnabled, !isRunning,
              connection.state == .connected,
              !connection.isSending, !connection.activity.inProgress, !weather.isBusy else { return }

        let now = Date()
        let offset = TimeZone.current.secondsFromGMT(for: now)
        guard WeatherSchedule.isDue(lastSent: defaults.object(forKey: Self.lastSentKey) as? Date,
                                    lastOffset: defaults.object(forKey: Self.lastOffsetKey) as? Int,
                                    now: now,
                                    currentOffset: offset) else { return }

        isRunning = true
        defer { isRunning = false }

        // Time first, then weather. If time fails (for example the band disconnected), stop
        // and try again next time.
        guard await connection.syncTime(automatic: true) else { return }

        // Never pop up the location permission automatically: only send weather if
        // the user has already allowed it (by tapping Send weather once).
        if weather.canUseLocation {
            guard await weather.sendForecast(using: connection, automatic: true) else { return }
        }

        // Only a successful update counts, so a failure is retried next time.
        defaults.set(now, forKey: Self.lastSentKey)
        defaults.set(offset, forKey: Self.lastOffsetKey)
    }
}
