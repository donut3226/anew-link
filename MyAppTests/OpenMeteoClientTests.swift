import Foundation
import Testing
@testable import MyApp

/// Checks the Open-Meteo request and reply handling, with made-up data and no network.
struct OpenMeteoClientTests {

    @Test func urlHasRoundedCoordinatesAndParameters() throws {
        let url = OpenMeteoClient.forecastURL(latitude: -34.928_499, longitude: 138.600_746)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.host() == "api.open-meteo.com")
        #expect(query["latitude"] == "-34.93")
        #expect(query["longitude"] == "138.60")
        #expect(query["daily"] == "weather_code,temperature_2m_max,temperature_2m_min")
        #expect(query["timezone"] == "auto")
        #expect(query["forecast_days"] == "5")
    }

    @Test func decodesDailyForecast() throws {
        let json = """
        {
          "latitude": -34.9,
          "daily_units": { "temperature_2m_max": "°C" },
          "daily": {
            "time": ["2026-01-01", "2026-01-02"],
            "weather_code": [3, 61],
            "temperature_2m_max": [21.4, 18.0],
            "temperature_2m_min": [12.1, 9.5]
          }
        }
        """
        let days = try OpenMeteoClient.decode(Data(json.utf8))
        #expect(days == [
            DailyForecast(day: "2026-01-01", weatherCode: 3, minCelsius: 12.1, maxCelsius: 21.4),
            DailyForecast(day: "2026-01-02", weatherCode: 61, minCelsius: 9.5, maxCelsius: 18.0),
        ])
    }

    @Test func forecastDayConvertsToBandDay() {
        let day = DailyForecast(day: "2026-01-01", weatherCode: 2, minCelsius: 12, maxCelsius: 21)
        #expect(day.wenaDay == WenaWeatherDay(main: .sunny, sub: .cloudy, minCelsius: 12, maxCelsius: 21))
    }

    @Test func badJSONThrows() {
        #expect(throws: (any Error).self) {
            try OpenMeteoClient.decode(Data("not json".utf8))
        }
    }
}
