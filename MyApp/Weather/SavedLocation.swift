import Foundation

/// The last place a forecast was fetched for, kept on the iPhone so weather can be sent
/// while the app is in the background.
///
/// Why: when the band asks for weather with the phone locked, iOS wakes the app for a few
/// seconds, but with "While Using the App" permission it won't hand out a fresh location.
/// So we reuse the last one. It's rounded to 2 decimals (about 1 km), the same as what's
/// sent to Open-Meteo, and it never leaves the phone except as part of that forecast request.
nonisolated struct SavedLocation: Equatable {

    static let latitudeKey = "weather.savedLatitude"
    static let longitudeKey = "weather.savedLongitude"

    let latitude: Double
    let longitude: Double

    /// Rounds to 2 decimal places.
    init(latitude: Double, longitude: Double) {
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }

    /// The saved location, or nil if none has been saved yet.
    static func load(from defaults: UserDefaults = .standard) -> SavedLocation? {
        guard let latitude = defaults.object(forKey: latitudeKey) as? Double,
              let longitude = defaults.object(forKey: longitudeKey) as? Double else { return nil }
        return SavedLocation(latitude: latitude, longitude: longitude)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(latitude, forKey: Self.latitudeKey)
        defaults.set(longitude, forKey: Self.longitudeKey)
    }
}
