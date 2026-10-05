import Foundation

/// Open-Meteo's two endpoints: the request URLs, and their responses read into plain values.
enum PersonalWeatherFeed {
    private static let forecastEndpoint = "https://api.open-meteo.com/v1/forecast"
    private static let geocodingEndpoint = "https://geocoding-api.open-meteo.com/v1/search"
    /// Three days, so the hours ahead run past tomorrow's midnight at any time today.
    private static let forecastDays = 3

    // MARK: Requests

    static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: forecastEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,"
                    + "relative_humidity_2m"),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]
        return components.url!
    }

    /// `language` is an ISO 639-1 code; place names come back in it, nil leaves the API's English.
    static func geocodingURL(for query: PersonalWeatherPlaceQuery, language: String?) -> URL {
        var components = URLComponents(string: geocodingEndpoint)!
        let name = query.name.addingPercentEncoding(withAllowedCharacters: .queryValue) ?? ""
        var items = [
            "name=\(name)",
            "count=\(query.candidateCount)",
            "format=json",
        ]
        if let language { items.append("language=\(language)") }
        components.percentEncodedQuery = items.joined(separator: "&")
        return components.url!
    }

    // MARK: Responses

    static func forecast(from data: Data) throws(PersonalWeatherFailure) -> PersonalWeatherForecast {
        let wire: ForecastWire
        do {
            wire = try JSONDecoder().decode(ForecastWire.self, from: data)
        } catch {
            throw .malformed
        }
        guard let zone = wire.timeZone, let temperature = wire.current.temperature else {
            throw .malformed
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let current = PersonalWeatherForecast.Current(
            temperature: temperature,
            apparentTemperature: wire.current.apparentTemperature,
            weatherCode: wire.current.weatherCode,
            isDay: wire.current.isDay.map { $0 != 0 } ?? true,
            windSpeed: wire.current.windSpeed,
            humidity: wire.current.humidity.map { Int($0.rounded()) })
        let range = wire.daily?.range(on: String(wire.current.time.prefix(Self.dateLength)))
        return PersonalWeatherForecast(
            current: current,
            hours: wire.hourly?.hours(in: calendar) ?? [],
            todayHigh: range?.high,
            todayLow: range?.low,
            timeZone: zone)
    }

    /// Candidates in the API's own ranking. A response with no `results` is how it says "no match".
    static func places(from data: Data) throws(PersonalWeatherFailure) -> [PersonalWeatherPlace] {
        let wire: GeocodingWire
        do {
            wire = try JSONDecoder().decode(GeocodingWire.self, from: data)
        } catch {
            throw .malformed
        }
        return (wire.results ?? []).compactMap { $0.value?.place }.filter(\.hasValidCoordinates)
    }

    /// "2026-10-05T06:45" read as wall-clock time in the calendar's zone; nil for anything else.
    static func localTime(_ text: String, in calendar: Calendar) -> Date? {
        let halves = text.split(separator: "T", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let day = halves[0].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        let clock = halves[1].split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard day.count == 3, (2...3).contains(clock.count),
            let year = day[0], let month = day[1], let dayOfMonth = day[2],
            let hour = clock[0], let minute = clock[1],
            (1...12).contains(month), (1...31).contains(dayOfMonth),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        let components = DateComponents(
            year: year, month: month, day: dayOfMonth, hour: hour, minute: minute)
        return calendar.date(from: components)
    }

    private static let dateLength = "2026-10-05".count
}

// MARK: - Wire shapes

private struct ForecastWire: Decodable {
    let timeZone: TimeZone?
    let current: Current
    let hourly: Hourly?
    let daily: Daily?

    private enum CodingKeys: String, CodingKey {
        case timezone, current, hourly, daily
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    /// Hourly and daily are extras: a damaged one empties itself and leaves the current reading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try? container.decodeIfPresent(String.self, forKey: .timezone)
        let offset = try? container.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds)
        timeZone =
            name.flatMap { TimeZone(identifier: $0) } ?? offset.flatMap { TimeZone(secondsFromGMT: $0) }
        current = try container.decode(Current.self, forKey: .current)
        hourly = try? container.decodeIfPresent(Hourly.self, forKey: .hourly)
        daily = try? container.decodeIfPresent(Daily.self, forKey: .daily)
    }

    struct Current: Decodable {
        let time: String
        let temperature: Double?
        let apparentTemperature: Double?
        let weatherCode: Int?
        let isDay: Int?
        let windSpeed: Double?
        let humidity: Double?

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case isDay = "is_day"
            case windSpeed = "wind_speed_10m"
            case humidity = "relative_humidity_2m"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double?]?
        let weatherCode: [Int?]?
        let precipitationChance: [Double?]?
        let isDay: [Int?]?

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationChance = "precipitation_probability"
            case isDay = "is_day"
        }

        /// An hour with no readable time or temperature is dropped; the rest keep their order.
        func hours(in calendar: Calendar) -> [PersonalWeatherForecast.Hour] {
            time.enumerated().compactMap { index, text in
                guard let date = PersonalWeatherFeed.localTime(text, in: calendar),
                    let temperature = Self.value(temperature, index)
                else { return nil }
                return PersonalWeatherForecast.Hour(
                    time: date,
                    temperature: temperature,
                    weatherCode: Self.value(weatherCode, index),
                    isDay: Self.value(isDay, index).map { $0 != 0 },
                    precipitationChance: Self.value(precipitationChance, index).map {
                        Int($0.rounded())
                    })
            }.sorted { $0.time < $1.time }
        }

        private static func value<T>(_ array: [T?]?, _ index: Int) -> T? {
            guard let array, array.indices.contains(index) else { return nil }
            return array[index]
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let high: [Double?]?
        let low: [Double?]?

        private enum CodingKeys: String, CodingKey {
            case time
            case high = "temperature_2m_max"
            case low = "temperature_2m_min"
        }

        /// The day whose date is `date` ("2026-10-05"); nil when the response has no such day.
        func range(on date: String) -> (high: Double?, low: Double?)? {
            guard let index = time.firstIndex(of: date) else { return nil }
            return (
                high?.indices.contains(index) == true ? high?[index] : nil,
                low?.indices.contains(index) == true ? low?[index] : nil
            )
        }
    }
}

private struct GeocodingWire: Decodable {
    let results: [Lossy<Result>]?

    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let admin1: String?
        let country: String?
        let countryCode: String?

        private enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, admin1, country
            case countryCode = "country_code"
        }

        var place: PersonalWeatherPlace {
            PersonalWeatherPlace(
                name: name, admin1: admin1, country: country, countryCode: countryCode,
                latitude: latitude, longitude: longitude)
        }
    }

    /// One unreadable candidate must not hide the readable ones around it.
    struct Lossy<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}

private extension CharacterSet {
    /// Unreserved characters only, so "+" and "&" in a city name are escaped, not read as syntax.
    static let queryValue = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
}
