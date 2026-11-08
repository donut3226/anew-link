import CoreLocation
import Foundation
import Observation
import UIKit

/// Runs the "Send weather" steps in order: location -> forecast -> packet -> band.
/// Kept separate from BandConnection so the Bluetooth code doesn't need to know about
/// location or the internet.
@Observable
final class WeatherSync {

    enum Status: Equatable {
        case idle
        case locating
        case fetching
        case sending
        /// `today` is the first forecast day (nil for the debug test pattern).
        /// `automatic` means AutoSync sent it, not a button.
        case done(today: DailyForecast?, at: Date, automatic: Bool)
        case failed(String)
    }

    private(set) var status: Status = .idle

    @ObservationIgnored private let location = LocationProvider()

    var isBusy: Bool {
        switch status {
        case .locating, .fetching, .sending: true
        default: false
        }
    }

    /// True if location permission is already granted, so no popup would appear.
    var canUseLocation: Bool {
        location.isAuthorized
    }

    /// Gets the real 5-day forecast for where you are and sends it to the band.
    /// Returns true if the band accepted it.
    @discardableResult
    func sendForecast(using connection: BandConnection, automatic: Bool = false) async -> Bool {
        guard !isBusy else { return false }
        do {
            let here = try await whereToForecast()

            status = .fetching
            let days = try await OpenMeteoClient.fetchForecast(latitude: here.latitude,
                                                               longitude: here.longitude)
            guard let packet = WenaPackets.weather(days: days.map(\.wenaDay)) else {
                throw OpenMeteoClient.FetchError.notEnoughDays
            }
            return await send(packet, today: days.first, automatic: automatic, using: connection)
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }
    }

    /// On screen: a fresh location (which is then saved). In the background: the saved one,
    /// because iOS doesn't give a fresh location to a background app with "While Using" permission.
    private func whereToForecast() async throws -> SavedLocation {
        if UIApplication.shared.applicationState == .active {
            status = .locating
            let fresh = try await location.currentLocation()
            let rounded = SavedLocation(latitude: fresh.coordinate.latitude,
                                        longitude: fresh.coordinate.longitude)
            rounded.save()
            return rounded
        }
        guard let saved = SavedLocation.load() else { throw WeatherError.noSavedLocation }
        return saved
    }

    enum WeatherError: LocalizedError {
        case noSavedLocation

        var errorDescription: String? {
            "No saved location yet. Open the app once so it can find where you are."
        }
    }

    /// Debug only: sends the fixed made-up pattern in `WenaPackets.testWeatherDays`.
    func sendTestPattern(using connection: BandConnection) async {
        guard !isBusy, let packet = WenaPackets.weather(days: WenaPackets.testWeatherDays) else { return }
        await send(packet, today: nil, automatic: false, using: connection)
    }

    @discardableResult
    private func send(_ packet: Data, today: DailyForecast?, automatic: Bool,
                      using connection: BandConnection) async -> Bool {
        status = .sending
        if let error = await connection.sendWeather(packet) {
            status = .failed(error)
            return false
        }
        status = .done(today: today, at: Date(), automatic: automatic)
        return true
    }
}
