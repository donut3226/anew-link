import Foundation

/// The 5 weather types the band knows (spec section 5).
nonisolated enum WenaCondition: UInt8, CaseIterable {
    case sunny = 0
    case cloudy = 1
    case rain = 2
    case heavyRain = 3
    case snow = 4
}

/// One day of forecast, in the form the band needs.
nonisolated struct WenaWeatherDay: Equatable {
    var main: WenaCondition
    var sub: WenaCondition
    var minCelsius: Double
    var maxCelsius: Double
}

nonisolated enum WenaWeather {

    /// Condition byte = (main << 3) | sub.
    /// "<< 3" shifts the main value 3 bits to the left, leaving room for sub in the lowest 3 bits.
    static func conditionByte(main: WenaCondition, sub: WenaCondition) -> UInt8 {
        (main.rawValue << 3) | sub.rawValue
    }

    /// Maps an Open-Meteo (WMO) weather code onto the band's main and sub conditions,
    /// following the rules in spec section 5.
    static func condition(forOpenMeteoCode code: Int) -> (main: WenaCondition, sub: WenaCondition) {
        switch code {
        case 0:
            return (.sunny, .sunny)                  // clear sky
        case 1, 2, 45, 48:
            return (.sunny, .cloudy)                 // partly cloudy, fog (haze or mist)
        case 3:
            return (.cloudy, .cloudy)                // overcast
        case 51...57, 61, 63, 80, 81:
            return (.rain, .rain)                    // drizzle, rain, showers
        case 65, 82, 95...99:
            return (.heavyRain, .heavyRain)          // heavy rain, violent showers, thunderstorms
        case 66, 67:
            return (.rain, .snow)                    // freezing rain (sleet)
        case 71...77, 85, 86:
            return (.snow, .snow)                    // snow
        default:
            return (.cloudy, .cloudy)                // unknown code: the safest neutral choice
        }
    }

    /// Temperatures go on the wire in Fahrenheit, rounded, plus 100.
    /// Kept within 0-255 so extreme values can't overflow the byte.
    static func temperatureByte(celsius: Double) -> UInt8 {
        let fahrenheit = (celsius * 9 / 5 + 32).rounded()
        return UInt8(min(max(fahrenheit + 100, 0), 255))
    }
}

nonisolated extension WenaPackets {

    /// Weather, 21 bytes: 0x03, then 5 days (today first) of
    /// day condition, night condition, min temp, max temp.
    /// Written to characteristic 4002. Returns nil unless exactly 5 days are given.
    static func weather(days: [WenaWeatherDay]) -> Data? {
        guard days.count == 5 else { return nil }
        var data = Data([0x03])
        for day in days {
            let condition = WenaWeather.conditionByte(main: day.main, sub: day.sub)
            data.append(condition)   // day
            data.append(condition)   // night: same value, as Gadgetbridge does
            data.append(WenaWeather.temperatureByte(celsius: day.minCelsius))
            data.append(WenaWeather.temperatureByte(celsius: day.maxCelsius))
        }
        return data
    }

    /// A fixed, made-up 5-day forecast for the debug test button.
    /// Each day uses a different condition, so you can check every icon and the day order.
    static let testWeatherDays: [WenaWeatherDay] = [
        WenaWeatherDay(main: .sunny, sub: .sunny, minCelsius: 15, maxCelsius: 25),
        WenaWeatherDay(main: .cloudy, sub: .cloudy, minCelsius: 10, maxCelsius: 20),
        WenaWeatherDay(main: .rain, sub: .rain, minCelsius: 5, maxCelsius: 15),
        WenaWeatherDay(main: .heavyRain, sub: .heavyRain, minCelsius: 0, maxCelsius: 10),
        WenaWeatherDay(main: .snow, sub: .snow, minCelsius: -5, maxCelsius: 0),
    ]
}
