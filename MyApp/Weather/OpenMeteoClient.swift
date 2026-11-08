import Foundation

/// One day of forecast from Open-Meteo.
nonisolated struct DailyForecast: Equatable {
    /// The day, as Open-Meteo sends it, for example "2026-11-08".
    let day: String
    let weatherCode: Int
    let minCelsius: Double
    let maxCelsius: Double

    /// Converts this day into what the band needs.
    var wenaDay: WenaWeatherDay {
        let condition = WenaWeather.condition(forOpenMeteoCode: weatherCode)
        return WenaWeatherDay(main: condition.main, sub: condition.sub,
                              minCelsius: minCelsius, maxCelsius: maxCelsius)
    }
}

/// Gets a 5-day forecast from Open-Meteo (open-meteo.com).
/// Free for non-commercial use, no API key, so nothing secret is in the repo.
nonisolated enum OpenMeteoClient {

    enum FetchError: LocalizedError {
        case badResponse
        case notEnoughDays

        var errorDescription: String? {
            switch self {
            case .badResponse: "The weather service sent an unexpected reply."
            case .notEnoughDays: "The weather service didn't return 5 days of forecast."
            }
        }
    }

    /// Builds the request URL. Coordinates are rounded to 2 decimal places (about 1 km),
    /// so your exact position is never sent.
    static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5"),
        ]
        return components.url!
    }

    /// The parts of Open-Meteo's JSON reply we use. `Codable` fills these in automatically;
    /// CodingKeys maps the JSON names (with underscores) onto Swift names.
    private struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int]
            let maxCelsius: [Double]
            let minCelsius: [Double]

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case maxCelsius = "temperature_2m_max"
                case minCelsius = "temperature_2m_min"
            }
        }
        let daily: Daily
    }

    /// Turns Open-Meteo's JSON into forecast days, today first.
    static func decode(_ data: Data) throws -> [DailyForecast] {
        let daily = try JSONDecoder().decode(Response.self, from: data).daily
        let count = [daily.time.count, daily.weatherCode.count,
                     daily.maxCelsius.count, daily.minCelsius.count].min() ?? 0
        return (0..<count).map { index in
            DailyForecast(day: daily.time[index],
                          weatherCode: daily.weatherCode[index],
                          minCelsius: daily.minCelsius[index],
                          maxCelsius: daily.maxCelsius[index])
        }
    }

    /// Downloads the forecast. `async` means the app keeps running while this waits for the network.
    static func fetchForecast(latitude: Double, longitude: Double) async throws -> [DailyForecast] {
        let url = forecastURL(latitude: latitude, longitude: longitude)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badResponse
        }
        let days = try decode(data)
        guard days.count >= 5 else { throw FetchError.notEnoughDays }
        return Array(days.prefix(5))
    }
}
