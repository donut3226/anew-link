import CoreLocation
import Foundation
import Observation

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
        case done(today: DailyForecast?, at: Date)
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

    /// Gets the real 5-day forecast for where you are and sends it to the band.
    func sendForecast(using connection: BandConnection) async {
        guard !isBusy else { return }
        do {
            status = .locating
            let here = try await location.currentLocation()

            status = .fetching
            let days = try await OpenMeteoClient.fetchForecast(latitude: here.coordinate.latitude,
                                                               longitude: here.coordinate.longitude)
            guard let packet = WenaPackets.weather(days: days.map(\.wenaDay)) else {
                throw OpenMeteoClient.FetchError.notEnoughDays
            }
            send(packet, today: days.first, using: connection)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Debug only: sends the fixed made-up pattern in `WenaPackets.testWeatherDays`.
    func sendTestPattern(using connection: BandConnection) {
        guard !isBusy, let packet = WenaPackets.weather(days: WenaPackets.testWeatherDays) else { return }
        send(packet, today: nil, using: connection)
    }

    private func send(_ packet: Data, today: DailyForecast?, using connection: BandConnection) {
        status = .sending
        connection.sendWeather(packet) { [weak self] error in
            self?.status = error.map { .failed($0) } ?? .done(today: today, at: Date())
        }
    }
}
