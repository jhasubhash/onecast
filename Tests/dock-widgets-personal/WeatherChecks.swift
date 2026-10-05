import AppKit
import Foundation

/// Real Open-Meteo responses, trimmed: one forecast request (two hourly cuts) and two searches.
private enum WeatherFixture {
    static let london = #"""
        {"latitude":51.51147,"longitude":-0.13078308,"utc_offset_seconds":3600,
        "timezone":"Europe/London","timezone_abbreviation":"GMT+1","elevation":16.0,
        "current":{"time":"2026-10-05T15:00","interval":900,"temperature_2m":20.9,
        "apparent_temperature":19.6,"weather_code":0,"is_day":1,"wind_speed_10m":13.0,
        "relative_humidity_2m":57},"hourly":{"time":["2026-10-05T14:00","2026-10-05T15:00",
        "2026-10-05T16:00","2026-10-05T17:00","2026-10-05T18:00","2026-10-05T19:00","2026-10-05T20:00",
        "2026-10-05T21:00","2026-10-05T22:00","2026-10-05T23:00","2026-10-06T00:00","2026-10-06T01:00",
        "2026-10-06T02:00","2026-10-06T03:00","2026-10-06T04:00","2026-10-06T05:00","2026-10-06T06:00",
        "2026-10-06T07:00","2026-10-06T08:00","2026-10-06T09:00"],"temperature_2m":[20.1,20.9,21.2,21.1,
        20.5,19.9,19.4,18.8,18.3,17.9,17.7,17.3,16.8,16.6,16.2,15.8,15.5,15.2,15.3,15.8],
        "weather_code":[0,0,1,1,1,1,0,0,0,2,3,2,0,2,1,1,2,3,2,3],"precipitation_probability":[0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"is_day":[1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1]},
        "daily":{"time":["2026-10-05","2026-10-06","2026-10-07"],"temperature_2m_max":[21.2,21.1,18.6],
        "temperature_2m_min":[13.8,15.2,10.8]}}
        """#

    static let rain = #"""
        {"latitude":51.51147,"longitude":-0.13078308,"utc_offset_seconds":3600,
        "timezone":"Europe/London","timezone_abbreviation":"GMT+1","elevation":16.0,
        "current":{"time":"2026-10-05T15:00","interval":900,"temperature_2m":20.9,
        "apparent_temperature":19.6,"weather_code":0,"is_day":1,"wind_speed_10m":13.0,
        "relative_humidity_2m":57},"hourly":{"time":["2026-10-07T01:00","2026-10-07T02:00",
        "2026-10-07T03:00","2026-10-07T04:00","2026-10-07T05:00","2026-10-07T06:00","2026-10-07T07:00",
        "2026-10-07T08:00"],"temperature_2m":[18.4,18.3,17.9,17.4,17.0,16.7,16.6,16.5],
        "weather_code":[3,3,51,53,53,51,51,51],"precipitation_probability":[12,15,19,24,30,37,43,48],
        "is_day":[0,0,0,0,0,0,0,1]},"daily":{"time":["2026-10-05","2026-10-06","2026-10-07"],
        "temperature_2m_max":[21.2,21.1,18.6],"temperature_2m_min":[13.8,15.2,10.8]}}
        """#

    static let paris = #"""
        {"results":[{"name":"Paris","latitude":48.85341,"longitude":2.3488,"country_code":"FR",
        "timezone":"Europe/Paris","country":"France","admin1":"Île-de-France Region",
        "admin2":"Paris Department"},{"name":"Paris","latitude":33.66094,"longitude":-95.55551,
        "country_code":"US","timezone":"America/Chicago","country":"United States","admin1":"Texas",
        "admin2":"Lamar"},{"name":"Paris","latitude":36.302,"longitude":-88.32671,"country_code":"US",
        "timezone":"America/Chicago","country":"United States","admin1":"Tennessee","admin2":"Henry"}]}
        """#

    static let cupertino = #"""
        {"results":[{"id":5341145,"name":"Cupertino","latitude":37.323,"longitude":-122.03218,
        "elevation":72.0,"feature_code":"PPL","country_code":"US","admin1_id":5332921,
        "admin2_id":5393021,"timezone":"America/Los_Angeles","population":60572,"postcodes":["95014",
        "95015"],"country_id":6252001,"country":"United States","admin1":"California",
        "admin2":"Santa Clara County"}],"generationtime_ms":0.3452301}
        """#

    /// What the geocoder answers when nothing matches: no `results` key at all.
    static let noMatch = #"{"generationtime_ms":0.487566}"#
}

@MainActor
enum WeatherChecks {
    private static let english = Locale(identifier: "en_US")
    private static let london = TimeZone(identifier: "Europe/London")!

    static func run() {
        conditionChecks()
        skyChecks()
        unitChecks()
        settingsChecks()
        queryChecks()
        requestChecks()
        forecastChecks()
        damagedForecastChecks()
        placeChecks()
        windowChecks()
        cacheChecks()
        failureAndScheduleChecks()
        formatChecks()
    }

    // MARK: Conditions and sky

    private static let documentedCodes = [
        0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85,
        86, 95, 96, 99,
    ]

    private static func conditionChecks() {
        let t = DockWidgetsPersonalTests.self
        t.expect(
            PersonalWeatherCondition.documentedCodes == documentedCodes,
            "the table covers exactly the documented WMO codes")
        for code in documentedCodes {
            for isDay in [true, false] {
                let condition = PersonalWeatherCondition(code: code, isDay: isDay)
                t.expect(condition != .unknown, "code \(code) is known (day: \(isDay))")
                t.expect(!condition.summary.isEmpty, "code \(code) has a description")
                t.expect(
                    NSImage(systemSymbolName: condition.symbol, accessibilityDescription: nil) != nil,
                    "code \(code) day \(isDay): \(condition.symbol) is a real SF Symbol")
            }
        }
        t.expect(
            NSImage(
                systemSymbolName: PersonalWeatherCondition.unknown.symbol,
                accessibilityDescription: nil) != nil,
            "the unknown fallback symbol exists")
        for code in [0, 1, 2, 80, 81] {
            t.expect(
                PersonalWeatherCondition(code: code, isDay: true).symbol
                    != PersonalWeatherCondition(code: code, isDay: false).symbol,
                "code \(code) shows the moon at night")
        }
        t.expect(
            PersonalWeatherCondition(code: 0, isDay: false).symbol == "moon.stars"
                && PersonalWeatherCondition(code: 0, isDay: true).symbol == "sun.max",
            "clear sky is the sun by day and the moon by night")
        t.expect(
            PersonalWeatherCondition(code: 63, isDay: true)
                == PersonalWeatherCondition(code: 63, isDay: false),
            "rain looks the same day and night")
        for code in [nil, 4, 100, -1, 9999] as [Int?] {
            t.expect(
                PersonalWeatherCondition(code: code, isDay: true) == .unknown,
                "\(String(describing: code)) falls back to the unknown condition")
        }
    }

    private static func skyChecks() {
        let t = DockWidgetsPersonalTests.self
        let kinds: [(code: Int?, kind: PersonalWeatherSky.Kind)] = [
            (0, .clear), (1, .clear), (2, .partlyCloudy), (3, .overcast), (45, .fog), (48, .fog),
            (51, .rain), (65, .rain), (66, .rain), (82, .rain), (71, .snow), (77, .snow),
            (86, .snow), (95, .storm), (99, .storm), (nil, .overcast), (4, .overcast),
        ]
        for (code, kind) in kinds {
            t.expect(
                PersonalWeatherSky(code: code, isDay: true).kind == kind,
                "code \(String(describing: code)) is a \(kind) sky")
        }
        for code in documentedCodes {
            let day = PersonalWeatherSky(code: code, isDay: true)
            let night = PersonalWeatherSky(code: code, isDay: false)
            t.expect(day.kind == night.kind, "code \(code) keeps its sky kind through the night")
            t.expect(
                day.colors.top != night.colors.top,
                "code \(code) has a different gradient at night")
        }
        let white = 1.05
        for kind in PersonalWeatherSky.Kind.allCases {
            for isDay in [true, false] {
                let stops = sky(of: kind, isDay: isDay).colors
                for stop in [stops.top, stops.bottom] {
                    t.expect(
                        white / (stop.luminance + 0.05) >= 3,
                        "white ink reads on the \(kind) \(isDay ? "day" : "night") gradient")
                }
            }
        }
    }

    private static func sky(of kind: PersonalWeatherSky.Kind, isDay: Bool) -> PersonalWeatherSky {
        let code: Int =
            switch kind {
            case .clear: 0
            case .partlyCloudy: 2
            case .overcast: 3
            case .fog: 45
            case .rain: 61
            case .snow: 71
            case .storm: 95
            }
        return PersonalWeatherSky(code: code, isDay: isDay)
    }

    // MARK: Units

    private static func unitChecks() {
        let t = DockWidgetsPersonalTests.self
        let f = PersonalWeatherUnit.fahrenheit
        let c = PersonalWeatherUnit.celsius
        t.expect(f.degrees(fromCelsius: 0) == 32, "0°C is 32°F")
        t.expect(f.degrees(fromCelsius: 100) == 212, "100°C is 212°F")
        t.expect(f.degrees(fromCelsius: -40) == -40, "-40 is the same on both scales")
        t.expect(c.degrees(fromCelsius: 21.5) == 21.5, "Celsius passes through unchanged")
        t.expect(f.roundedDegrees(fromCelsius: 22.5) == 73, "72.5°F rounds up to 73")
        t.expect(f.roundedDegrees(fromCelsius: 22.4) == 72, "72.32°F rounds down to 72")
        t.expect(c.roundedDegrees(fromCelsius: 21.5) == 22, "21.5°C rounds half up")
        t.expect(c.roundedDegrees(fromCelsius: -0.5) == -1, "-0.5°C rounds away from zero")
        t.expect(c.roundedDegrees(fromCelsius: -0.4) == 0, "-0.4°C rounds to zero")
        t.expect(
            c.temperature(fromCelsius: -0.4, locale: english) == "0°", "a rounded zero is never -0")
        t.expect(f.temperature(fromCelsius: 22, locale: english) == "72°", "22°C reads 72°")
        t.expect(f.temperature(fromCelsius: -20, locale: english) == "-4°", "-20°C reads -4°")
        t.expect(
            c.temperature(fromCelsius: 1234, locale: english) == "1234°",
            "a temperature is never grouped")
        t.expect(
            f.windSpeed(fromKilometersPerHour: 13, locale: english) == "8 mph",
            "13 km/h is 8 mph")
        t.expect(
            c.windSpeed(fromKilometersPerHour: 13.4, locale: english) == "13 km/h",
            "wind stays km/h on Celsius")
        t.expect(
            PersonalWeatherUnit.localeDefault(Locale(identifier: "en_US")) == .fahrenheit,
            "US defaults to Fahrenheit")
        t.expect(
            PersonalWeatherUnit.localeDefault(Locale(identifier: "en_GB")) == .celsius,
            "the UK defaults to Celsius")
        t.expect(
            PersonalWeatherUnit.localeDefault(Locale(identifier: "fr_FR")) == .celsius,
            "metric regions default to Celsius")
        t.expect(
            PersonalWeatherUnit(preference: "fahrenheit", locale: Locale(identifier: "fr_FR"))
                == .fahrenheit,
            "a stored unit beats the locale")
        for garbage in [nil, "", "kelvin"] as [String?] {
            t.expect(
                PersonalWeatherUnit(preference: garbage, locale: Locale(identifier: "en_US"))
                    == .fahrenheit,
                "\(String(describing: garbage)) falls back to the locale default")
        }
    }

    // MARK: Settings

    private static func settings(
        _ strings: [String: String] = [:], flags: Set<String> = [], locale: Locale? = nil
    ) -> PersonalWeatherSettings {
        PersonalWeatherSettings(
            string: { strings[$0] }, bool: { flags.contains($0) }, locale: locale ?? english)
    }

    private static func settingsChecks() {
        let t = DockWidgetsPersonalTests.self
        let fresh = settings()
        t.expect(fresh.display == .current, "display defaults to Current")
        t.expect(fresh.unit == .fahrenheit, "an unset unit follows the locale")
        t.expect(fresh.forecastHours == 4, "forecast hours default to 4")
        t.expect(fresh.background == .themed, "background defaults to Themed")
        t.expect(fresh.source == .unset, "no city and no location toggle is an unset source")
        let set = settings([
            "display": "hourly", "unit": "celsius", "forecastHours": "6", "background": "translucent",
        ])
        t.expect(
            set.display == .hourly && set.unit == .celsius && set.forecastHours == 6
                && set.background == .translucent,
            "stored values are read")
        let garbage = settings([
            "display": "radar", "unit": "kelvin", "forecastHours": "many", "background": "neon",
        ])
        t.expect(
            garbage.display == .current && garbage.unit == .fahrenheit && garbage.forecastHours == 4
                && garbage.background == .themed,
            "garbage falls back to the defaults")
        t.expect(settings(["forecastHours": "0"]).forecastHours == 1, "hours clamp up to 1")
        t.expect(settings(["forecastHours": "99"]).forecastHours == 6, "hours clamp down to 6")
        t.expect(settings(["forecastHours": " 5 "]).forecastHours == 5, "hours tolerate spaces")
        t.expect(
            settings(["forecastHours": "6"]).visibleHours(isVertical: false) == 6,
            "a bottom dock shows every chosen hour")
        t.expect(
            settings(["forecastHours": "6"]).visibleHours(isVertical: true) == 3,
            "a side dock shows at most 3 hours")
        t.expect(
            settings(["forecastHours": "2"]).visibleHours(isVertical: true) == 2,
            "a side dock still honours fewer hours")

        let paris = PersonalWeatherPlaceQuery("Paris, FR")!
        t.expect(
            settings(["location": "  Paris ,  fr "]).source == .city(paris),
            "a typed city is read through the query")
        t.expect(
            settings(["location": "   "]).source == .unset, "a blank city is an unset source")
        t.expect(
            settings(["location": "Paris, FR"], flags: ["useCurrentLocation"]).source == .current,
            "Use current location beats a typed city")
        t.expect(
            settings(["location": "Paris"]).source != settings(["location": "Paris, FR"]).source,
            "adding a qualifier changes the source")
        t.expect(
            settings(["location": "Paris"]).source == settings(["location": "paris "]).source,
            "case and trailing spaces do not change the source")
        t.expect(
            settings(["unit": "celsius"]).source == settings(["unit": "fahrenheit"]).source,
            "the unit is not part of the source")
    }

    // MARK: Place queries and requests

    private static func queryChecks() {
        let t = DockWidgetsPersonalTests.self
        t.expect(PersonalWeatherPlaceQuery("") == nil, "an empty query is nil")
        t.expect(PersonalWeatherPlaceQuery("   ") == nil, "a blank query is nil")
        t.expect(PersonalWeatherPlaceQuery(", FR") == nil, "a qualifier with no city is nil")
        let bare = PersonalWeatherPlaceQuery("Paris, ")!
        t.expect(bare.qualifier == nil && bare.name == "Paris", "a dangling comma means no qualifier")
        let spaced = PersonalWeatherPlaceQuery("  New   York ,  NY ")!
        t.expect(
            spaced.name == "New York" && spaced.qualifier == "NY",
            "spaces are trimmed and collapsed")
        t.expect(
            PersonalWeatherPlaceQuery("Zürich") == PersonalWeatherPlaceQuery("zurich"),
            "accents and case fold away")
        t.expect(
            PersonalWeatherPlaceQuery("Paris,FR") == PersonalWeatherPlaceQuery("Paris, FR"),
            "space after the comma is not significant")
        t.expect(PersonalWeatherPlaceQuery("Paris")!.candidateCount == 1, "a bare city asks for one match")
        t.expect(
            PersonalWeatherPlaceQuery("Paris, FR")!.candidateCount > 1,
            "a qualified city asks for enough matches to filter")
        t.expect(
            PersonalWeatherPlaceQuery("Paris, FR")!.displayText == "Paris, FR",
            "the display text keeps what the user typed")

        let candidates = (try? PersonalWeatherFeed.places(from: Data(WeatherFixture.paris.utf8))) ?? []
        func pick(_ text: String) -> PersonalWeatherPlace? {
            PersonalWeatherPlaceQuery(text)!.choose(from: candidates)
        }
        t.expect(pick("Paris")?.countryCode == "FR", "a bare city takes the API's first match")
        t.expect(pick("Paris, FR")?.countryCode == "FR", "a country code picks its Paris")
        t.expect(pick("paris, fr")?.countryCode == "FR", "the country code is case-insensitive")
        t.expect(pick("Paris, France")?.countryCode == "FR", "a country name picks its Paris")
        t.expect(pick("Paris, Texas")?.admin1 == "Texas", "a state name picks its Paris")
        t.expect(pick("Paris, US")?.admin1 == "Texas", "a country shared by several takes the first")
        t.expect(pick("Paris, Tennessee")?.latitude == 36.302, "the third candidate is reachable")
        t.expect(pick("Paris, Narnia") == nil, "a qualifier nothing matches finds no place")
        t.expect(
            PersonalWeatherPlaceQuery("Paris")!.choose(from: []) == nil, "no candidates find no place")
    }

    private static func requestChecks() {
        let t = DockWidgetsPersonalTests.self
        let url = PersonalWeatherFeed.forecastURL(latitude: 37.323, longitude: -122.03218)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        t.expect(
            components.host == "api.open-meteo.com" && components.path == "/v1/forecast",
            "the forecast request goes to the Open-Meteo forecast endpoint")
        t.expect(
            items["latitude"] == "37.323" && items["longitude"] == "-122.03218",
            "coordinates are sent as plain decimals")
        let current = Set((items["current"] ?? "").split(separator: ",").map(String.init))
        t.expect(
            current == [
                "temperature_2m", "apparent_temperature", "weather_code", "is_day",
                "wind_speed_10m", "relative_humidity_2m",
            ], "the current variables are exactly the ones the tile reads")
        let hourly = Set((items["hourly"] ?? "").split(separator: ",").map(String.init))
        t.expect(
            hourly == ["temperature_2m", "weather_code", "precipitation_probability", "is_day"],
            "the hourly variables include daylight for the night symbols")
        t.expect(
            items["daily"] == "temperature_2m_max,temperature_2m_min", "daily asks for the range")
        t.expect(items["timezone"] == "auto", "times come back in the place's own zone")
        t.expect(
            items["temperature_unit"] == "celsius" && items["wind_speed_unit"] == "kmh",
            "units are pinned to metric so parsed values are unit-independent")
        t.expect(
            (Int(items["forecast_days"] ?? "") ?? 0) >= 3,
            "the forecast covers past tomorrow's midnight from any hour today")

        let paris = PersonalWeatherFeed.geocodingURL(
            for: PersonalWeatherPlaceQuery("Paris, FR")!, language: "fr")
        let parisItems = URLComponents(url: paris, resolvingAgainstBaseURL: false)!.queryItems ?? []
        t.expect(
            paris.host == "geocoding-api.open-meteo.com" && paris.path == "/v1/search",
            "the geocoding request goes to the Open-Meteo search endpoint")
        t.expect(
            parisItems.first { $0.name == "name" }?.value == "Paris",
            "only the city part is searched")
        t.expect(
            parisItems.first { $0.name == "language" }?.value == "fr", "the language is passed on")
        let plain = PersonalWeatherFeed.geocodingURL(
            for: PersonalWeatherPlaceQuery("Paris")!, language: nil)
        t.expect(
            !plain.absoluteString.contains("language") && plain.absoluteString.contains("count=1"),
            "no language is sent unless there is one, and a bare city counts one")
        let tricky = PersonalWeatherFeed.geocodingURL(
            for: PersonalWeatherPlaceQuery("A&B+C d")!, language: nil
        ).absoluteString
        t.expect(
            tricky.contains("name=A%26B%2BC%20d&"),
            "& and + in a city name are escaped, not read as syntax")
        t.expect(
            PersonalWeatherFeed.geocodingURL(
                for: PersonalWeatherPlaceQuery("Zürich")!, language: nil
            ).absoluteString.contains("name=Z%C3%BCrich"),
            "non-ASCII names are percent-encoded")
    }

    // MARK: Parsing

    private static func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private static func parse(_ text: String) -> Result<PersonalWeatherForecast, PersonalWeatherFailure> {
        parse(Data(text.utf8))
    }

    private static func parse(_ data: Data) -> Result<PersonalWeatherForecast, PersonalWeatherFailure> {
        do throws(PersonalWeatherFailure) {
            return .success(try PersonalWeatherFeed.forecast(from: data))
        } catch {
            return .failure(error)
        }
    }

    /// The London fixture with one edit applied to its decoded JSON.
    private static func variant(_ edit: (inout [String: Any]) -> Void) -> Data {
        var root =
            (try? JSONSerialization.jsonObject(with: Data(WeatherFixture.london.utf8)))
            as? [String: Any] ?? [:]
        edit(&root)
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }

    private static func forecastChecks() {
        let t = DockWidgetsPersonalTests.self
        guard case .success(let forecast) = parse(WeatherFixture.london) else {
            t.expect(false, "the London fixture parses")
            return
        }
        let current = forecast.current
        t.expect(current.temperature == 20.9, "current temperature")
        t.expect(current.apparentTemperature == 19.6, "feels-like temperature")
        t.expect(current.weatherCode == 0 && current.isDay, "clear code in daylight")
        t.expect(current.windSpeed == 13.0, "wind in km/h")
        t.expect(current.humidity == 57, "humidity")
        t.expect(
            current.condition == PersonalWeatherCondition(code: 0, isDay: true),
            "the current condition is the code in daylight")
        t.expect(
            forecast.todayHigh == 21.2 && forecast.todayLow == 13.8,
            "today's range is the row for today")
        t.expect(forecast.timeZone.identifier == "Europe/London", "the place's own zone")
        t.expect(forecast.hours.count == 20, "every hour in the fixture is read")
        t.expect(
            forecast.hours.first?.time == utc("2026-10-05T13:00:00Z"),
            "14:00 London summer time is 13:00 UTC")
        t.expect(
            forecast.hours[1].temperature == 20.9 && forecast.hours[1].weatherCode == 0,
            "an hour's values")
        t.expect(forecast.hours[10].weatherCode == 3, "midnight reads overcast")
        t.expect(
            forecast.hours[4].isDay == true && forecast.hours[5].isDay == false,
            "daylight ends between 18:00 and 19:00")
        t.expect(forecast.hours[18].isDay == true, "daylight returns by 08:00 the next day")
        t.expect(
            forecast.hours[5].condition == PersonalWeatherCondition(code: 1, isDay: false),
            "an hour's condition uses its own daylight")
        t.expect(forecast.hours[5].precipitationChance == 0, "a zero chance is still a chance")
        t.expect(
            zip(forecast.hours, forecast.hours.dropFirst()).allSatisfy {
                $1.time.timeIntervalSince($0.time) == 3600
            }, "hours are consecutive")

        guard case .success(let wet) = parse(WeatherFixture.rain) else {
            t.expect(false, "the rain fixture parses")
            return
        }
        t.expect(
            wet.hours.map(\.precipitationChance) == [12, 15, 19, 24, 30, 37, 43, 48],
            "precipitation chances are read per hour")
        t.expect(
            wet.hours.map(\.weatherCode) == [3, 3, 51, 53, 53, 51, 51, 51], "rain codes are read per hour")
        t.expect(
            wet.hours[2].condition.summary == "Light drizzle" && wet.hours[2].isDay == false,
            "a night drizzle hour")
    }

    private static func damagedForecastChecks() {
        let t = DockWidgetsPersonalTests.self
        func forecast(_ data: Data) -> PersonalWeatherForecast? {
            if case .success(let value) = parse(data) { return value }
            return nil
        }
        func failure(_ data: Data) -> PersonalWeatherFailure? {
            if case .failure(let value) = parse(data) { return value }
            return nil
        }

        for garbage in ["", "{", "[]", "null", "42", "not json", #"{"error":true,"reason":"bad"}"#] {
            t.expect(failure(Data(garbage.utf8)) == .malformed, "\(garbage.prefix(12)) is malformed")
        }
        t.expect(
            failure(variant { $0["current"] = nil }) == .malformed, "no current block is malformed")
        t.expect(
            failure(variant { $0.edit("current") { $0["temperature_2m"] = NSNull() } }) == .malformed,
            "a null current temperature is malformed")
        t.expect(
            failure(variant { $0.edit("current") { $0["temperature_2m"] = "warm" } }) == .malformed,
            "a text temperature is malformed")
        t.expect(
            failure(variant { $0["timezone"] = nil; $0["utc_offset_seconds"] = nil }) == .malformed,
            "no timezone and no offset cannot anchor the times")

        let sparse = forecast(
            variant {
                $0.edit("current") {
                    $0["weather_code"] = NSNull()
                    $0["apparent_temperature"] = nil
                    $0["relative_humidity_2m"] = NSNull()
                    $0["wind_speed_10m"] = nil
                    $0["is_day"] = nil
                }
            })
        t.expect(sparse?.current.weatherCode == nil, "a null weather code stays nil")
        t.expect(sparse?.current.condition == .unknown, "a missing code draws the unknown condition")
        t.expect(
            sparse?.current.apparentTemperature == nil && sparse?.current.humidity == nil
                && sparse?.current.windSpeed == nil,
            "missing or null extras stay nil")
        t.expect(sparse?.current.isDay == true, "a missing is_day defaults to daylight")
        t.expect(sparse?.current.temperature == 20.9, "the temperature survives missing extras")

        let holes = forecast(
            variant {
                $0.edit("hourly") { hourly in
                    var temperatures = hourly.array("temperature_2m")
                    temperatures[3] = NSNull()
                    hourly["temperature_2m"] = temperatures
                    var chances = hourly.array("precipitation_probability")
                    chances[4] = NSNull()
                    hourly["precipitation_probability"] = chances
                    var times = hourly.array("time")
                    times[6] = "garbage"
                    hourly["time"] = times
                }
            })
        t.expect(holes?.hours.count == 18, "an hour with no temperature or no time is dropped")
        t.expect(
            holes?.hours.contains { $0.time == utc("2026-10-05T16:00:00Z") } == false,
            "the hour whose temperature is null is the one dropped")
        t.expect(
            holes?.hours.first { $0.time == utc("2026-10-05T17:00:00Z") }?.precipitationChance == nil,
            "a null chance stays nil on a kept hour")

        let short = forecast(
            variant {
                $0.edit("hourly") { $0["temperature_2m"] = Array($0.array("temperature_2m").prefix(5)) }
            })
        t.expect(short?.hours.count == 5, "hours past the end of a short array are dropped")

        let reversed = forecast(
            variant { $0.edit("hourly") { $0["time"] = Array($0.array("time").reversed()) } })
        t.expect(
            reversed.map { zip($0.hours, $0.hours.dropFirst()).allSatisfy { $0.time < $1.time } }
                == true,
            "hours come out ordered by time")

        let noHours = forecast(variant { $0["hourly"] = nil })
        t.expect(
            noHours?.hours.isEmpty == true && noHours?.current.temperature == 20.9,
            "a response with no hourly block still gives the current reading")
        let brokenHours = forecast(
            variant { $0.edit("hourly") { $0["temperature_2m"] = "hot" } })
        t.expect(
            brokenHours?.hours.isEmpty == true && brokenHours?.current.temperature == 20.9,
            "a damaged hourly block empties itself and keeps the current reading")
        let noDaily = forecast(variant { $0["daily"] = nil })
        t.expect(
            noDaily?.todayHigh == nil && noDaily?.todayLow == nil, "no daily block means no range")
        let wrongDay = forecast(
            variant { $0.edit("daily") { $0["time"] = ["2026-09-01", "2026-09-02", "2026-09-03"] } })
        t.expect(wrongDay?.todayHigh == nil, "no row for today means no range")
        let offsetOnly = forecast(
            variant { $0["timezone"] = nil; $0["utc_offset_seconds"] = 7200 })
        t.expect(
            offsetOnly?.hours.first?.time == utc("2026-10-05T12:00:00Z"),
            "a bare UTC offset anchors the local times when the zone name is missing")
    }

    private static func placeChecks() {
        let t = DockWidgetsPersonalTests.self
        let paris = try? PersonalWeatherFeed.places(from: Data(WeatherFixture.paris.utf8))
        t.expect(paris?.count == 3, "all three candidates are read")
        t.expect(
            paris?.first
                == PersonalWeatherPlace(
                    name: "Paris", admin1: "Île-de-France Region", country: "France",
                    countryCode: "FR", latitude: 48.85341, longitude: 2.3488),
            "a candidate carries its name, region, country and coordinates")
        t.expect(paris?.first?.region == "Île-de-France Region", "the region line prefers the state")
        let cupertino = try? PersonalWeatherFeed.places(from: Data(WeatherFixture.cupertino.utf8))
        t.expect(
            cupertino?.first?.name == "Cupertino" && cupertino?.first?.latitude == 37.323
                && cupertino?.first?.longitude == -122.03218,
            "unknown keys such as postcodes and ids are ignored")
        t.expect(
            (try? PersonalWeatherFeed.places(from: Data(WeatherFixture.noMatch.utf8)))?.isEmpty
                == true,
            "no results key is an empty list, not an error")
        t.expect(
            (try? PersonalWeatherFeed.places(from: Data(#"{"results":null}"#.utf8)))?.isEmpty == true,
            "null results is an empty list")
        t.expect(
            (try? PersonalWeatherFeed.places(from: Data("nope".utf8))) == nil,
            "a non-JSON geocoding body throws")
        let lossy = #"""
            {"results":[{"name":"Broken"},{"name":"Lost","latitude":95,"longitude":0},
            {"name":"Fine","latitude":1.5,"longitude":2.5}]}
            """#
        let kept = try? PersonalWeatherFeed.places(from: Data(lossy.utf8))
        t.expect(
            kept?.map(\.name) == ["Fine"],
            "a candidate with no coordinates or impossible ones is skipped, the rest kept")
        t.expect(
            PersonalWeatherPlace(name: "Edge", latitude: 90, longitude: -180).hasValidCoordinates,
            "the coordinate extremes are valid")
        t.expect(
            !PersonalWeatherPlace(name: "Far", latitude: 0, longitude: 181).hasValidCoordinates,
            "a longitude past 180 is invalid")
    }

    // MARK: The hourly window

    private static func windowChecks() {
        let t = DockWidgetsPersonalTests.self
        guard case .success(let forecast) = parse(WeatherFixture.london) else {
            t.expect(false, "the London fixture parses for the window checks")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        func hours(_ now: String, _ count: Int) -> [Int] {
            forecast.window(from: utc(now), count: count).map { calendar.component(.hour, from: $0.time) }
        }

        t.expect(
            hours("2026-10-05T14:40:00Z", 4) == [15, 16, 17, 18],
            "at 15:40 London the window starts with the 15:00 hour")
        t.expect(
            hours("2026-10-05T15:00:00Z", 2) == [16, 17],
            "on the hour, the hour just begun is the first")
        t.expect(
            hours("2026-10-05T14:59:59Z", 1) == [15], "one second before the hour is still the old hour")
        t.expect(
            hours("2026-10-05T22:40:00Z", 4) == [23, 0, 1, 2],
            "a window opened at 23:40 runs across midnight")
        let across = forecast.window(from: utc("2026-10-05T22:40:00Z"), count: 4)
        t.expect(
            across.map { calendar.component(.day, from: $0.time) } == [5, 6, 6, 6],
            "the hours after midnight fall on the next day")
        t.expect(
            zip(across, across.dropFirst()).allSatisfy { $1.time.timeIntervalSince($0.time) == 3600 },
            "the window has no gap at midnight")
        t.expect(
            hours("2026-10-06T07:30:00Z", 6) == [8, 9],
            "a window past the end of the data is as long as the data left")
        t.expect(hours("2026-10-07T00:00:00Z", 6).isEmpty, "no hours are left once the data has run out")
        t.expect(
            hours("2026-10-01T00:00:00Z", 2) == [14, 15],
            "a clock before the data starts at its first hour")
        t.expect(hours("2026-10-05T14:40:00Z", 0).isEmpty, "a zero count is an empty window")
        t.expect(hours("2026-10-05T14:40:00Z", -3).isEmpty, "a negative count is an empty window")
        t.expect(hours("2026-10-05T14:40:00Z", 24).count == 19, "a long window is cut at the data")
    }

    // MARK: Cache, failures, schedule, text

    private static func cacheChecks() {
        let t = DockWidgetsPersonalTests.self
        let place = PersonalWeatherPlace(
            name: "Paris", admin1: "Île-de-France Region", country: "France", countryCode: "FR",
            latitude: 48.85341, longitude: 2.3488)
        let query = PersonalWeatherPlaceQuery("Paris, FR")!
        let stored = PersonalWeatherPlaceCache.encode(place, for: query)
        t.expect(stored != nil, "an entry encodes")
        t.expect(
            PersonalWeatherPlaceCache.decode(stored, for: query) == place,
            "an entry decodes to the place it was made from")
        t.expect(
            PersonalWeatherPlaceCache.encode(place, for: query) == stored,
            "encoding is deterministic")
        t.expect(
            PersonalWeatherPlaceCache.decode(stored, for: PersonalWeatherPlaceQuery(" paris , fr ")!)
                == place,
            "another spelling of the same query hits the cache")
        t.expect(
            PersonalWeatherPlaceCache.decode(stored, for: PersonalWeatherPlaceQuery("Paris")!) == nil,
            "dropping the qualifier invalidates the cache")
        t.expect(
            PersonalWeatherPlaceCache.decode(stored, for: PersonalWeatherPlaceQuery("Lyon, FR")!) == nil,
            "a different city invalidates the cache")
        t.expect(
            PersonalWeatherPlaceCache.decode(stored, for: PersonalWeatherPlaceQuery("Paris, US")!) == nil,
            "a different qualifier invalidates the cache")
        for damaged in [nil, "", "{}", "not json", #"{"key":"paris,fr"}"#] as [String?] {
            t.expect(
                PersonalWeatherPlaceCache.decode(damaged, for: query) == nil,
                "a damaged entry \(String(describing: damaged)) decodes to nothing")
        }
        let impossible = PersonalWeatherPlace(name: "Nowhere", latitude: 123, longitude: 0)
        t.expect(
            PersonalWeatherPlaceCache.decode(
                PersonalWeatherPlaceCache.encode(impossible, for: query), for: query) == nil,
            "an entry with impossible coordinates is never trusted")
        t.expect(
            PersonalWeatherPlaceCache.preferenceKey == "resolvedLocation",
            "the cache lives under an undeclared preference key")
    }

    private static func failureAndScheduleChecks() {
        let t = DockWidgetsPersonalTests.self
        let all: [PersonalWeatherFailure] = [
            .noCity, .cityNotFound("Paris, TX"), .network, .service(503), .malformed, .locationDenied,
            .locationRestricted, .locationUnavailable, .locationTimedOut,
        ]
        t.expect(Set(all.map(\.message)).count == all.count, "every failure has its own message")
        t.expect(
            PersonalWeatherFailure.cityNotFound("Paris, TX").message.contains("Paris, TX"),
            "a not-found message names the query")
        t.expect(
            PersonalWeatherFailure.service(503).message.contains("503"),
            "a service error names the status")
        t.expect(PersonalWeatherFailure.noCity.remedy == .widgetSettings, "an unset city sends to settings")
        t.expect(
            PersonalWeatherFailure.cityNotFound("x").remedy == .widgetSettings,
            "an unknown city sends to settings")
        t.expect(
            PersonalWeatherFailure.locationDenied.remedy == .locationPrivacy,
            "denied location sends to Privacy settings")
        t.expect(PersonalWeatherFailure.network.remedy == nil, "a network error has no remedy to open")
        t.expect(!PersonalWeatherFailure.noCity.offersRetry, "retrying cannot supply a missing city")
        t.expect(PersonalWeatherFailure.network.offersRetry, "retrying can cure a network error")

        let start = Date(timeIntervalSince1970: 1_000_000)
        t.expect(
            PersonalWeatherSchedule.nextAttempt(after: start, retrying: false)
                == start.addingTimeInterval(1800),
            "a good refresh is followed by one 30 minutes later")
        t.expect(
            PersonalWeatherSchedule.nextAttempt(after: start, retrying: true)
                == start.addingTimeInterval(300),
            "a retryable failure is followed by an attempt 5 minutes later")
    }

    private static func formatChecks() {
        let t = DockWidgetsPersonalTests.self
        func plain(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{202F}", with: " ")
        }
        let instant = utc("2026-09-21T14:13:20Z")
        t.expect(
            plain(PersonalWeatherFormat.hour(instant, timeZone: london, locale: english)) == "3 PM",
            "14:13 UTC is 3 PM in London")
        t.expect(
            plain(
                PersonalWeatherFormat.hour(
                    instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!, locale: english))
                == "7 AM",
            "the hour is drawn in the place's zone, not the Mac's")
        t.expect(
            PersonalWeatherFormat.hour(
                instant, timeZone: london, locale: Locale(identifier: "en_GB")) == "15",
            "a 24-hour locale draws 24-hour hours")
        t.expect(
            PersonalWeatherFormat.updated(instant, now: instant.addingTimeInterval(30), locale: english)
                == "Updated just now",
            "under a minute is just now")
        t.expect(
            PersonalWeatherFormat.updated(instant, now: instant.addingTimeInterval(-30), locale: english)
                == "Updated just now",
            "a stamp in the future is just now")
        t.expect(
            PersonalWeatherFormat.updated(instant, now: instant.addingTimeInterval(180), locale: english)
                == "Updated 3 min. ago",
            "three minutes reads as relative minutes")
        t.expect(
            PersonalWeatherFormat.updated(instant, now: instant.addingTimeInterval(7200), locale: english)
                == "Updated 2 hr. ago",
            "two hours reads as relative hours")
        t.expect(PersonalWeatherFormat.percent(69, locale: english) == "69%", "a percent")
    }
}

private extension Dictionary where Key == String, Value == Any {
    /// Edits the nested object under `key` in place.
    mutating func edit(_ key: String, _ change: (inout [String: Any]) -> Void) {
        var nested = self[key] as? [String: Any] ?? [:]
        change(&nested)
        self[key] = nested
    }

    func array(_ key: String) -> [Any] {
        self[key] as? [Any] ?? []
    }
}
