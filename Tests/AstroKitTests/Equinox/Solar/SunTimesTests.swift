import XCTest
@testable import AstroKit

/// Tests for SolarCalculator sunrise/sunset calculations
/// Reference data: NOAA Solar Calculator (gml.noaa.gov/grad/solcalc)
final class SunTimesTests: XCTestCase {

    // MARK: - Standard Location Tests

    func test_sunTimes_stockholmSummerSolstice_matchesNOAA() {
        // Stockholm, June 21, 2025 (Summer Solstice)
        // NOAA reference: Sunrise ~03:31, Sunset ~22:08 (local CEST, UTC+2)
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: TestLocations.stockholm.tz)
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 3, minute: 31, timezone: TestLocations.stockholm.tz, toleranceMinutes: 3)
            assertTimeEquals(times.sunset, hour: 22, minute: 8, timezone: TestLocations.stockholm.tz, toleranceMinutes: 3)
        }
    }

    func test_sunTimes_stockholmWinterSolstice_matchesNOAA() {
        // Stockholm, December 21, 2025 (Winter Solstice)
        // NOAA reference: Sunrise ~08:43, Sunset ~14:48 (local CET, UTC+1)
        let date = TestDates.local(year: 2025, month: 12, day: 21, hour: 12, timezone: TestLocations.stockholm.tz)
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 8, minute: 43, timezone: TestLocations.stockholm.tz, toleranceMinutes: 3)
            assertTimeEquals(times.sunset, hour: 14, minute: 48, timezone: TestLocations.stockholm.tz, toleranceMinutes: 3)
        }
    }

    func test_sunTimes_newYorkMarch21_hasReasonableTimes() {
        // New York, March 21, 2025 (near equinox)
        // At equinox, daylight should be about 12 hours
        let date = TestDates.local(year: 2025, month: 3, day: 21, hour: 12, timezone: TestLocations.newYork.tz)
        let tz = TimeZone(identifier: TestLocations.newYork.tz)!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            // Near equinox, daylight should be approximately 12 hours (within 30 min)
            let daylightHours = times.daylightDuration / 3600
            XCTAssertEqual(daylightHours, 12.0, accuracy: 0.5)
        }
    }

    func test_sunTimes_newYorkSummerSolstice_matchesNOAA() {
        // New York, June 21, 2025 (Summer Solstice)
        // NOAA reference: Sunrise 05:25, Sunset 20:31 (EDT, UTC-4)
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: TestLocations.newYork.tz)
        let tz = TimeZone(identifier: TestLocations.newYork.tz)!
        let sunTimes = SolarCalculator.sunTimes(date: date, latitude: TestLocations.newYork.lat,
                                                longitude: TestLocations.newYork.lon, timeZone: tz)
        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 5, minute: 25, timezone: TestLocations.newYork.tz, toleranceMinutes: 3)
            assertTimeEquals(times.sunset,  hour: 20, minute: 31, timezone: TestLocations.newYork.tz, toleranceMinutes: 3)
        }
    }

    func test_sunTimes_newYorkWinterSolstice_matchesNOAA() {
        // New York, December 21, 2025 (Winter Solstice)
        // NOAA reference: Sunrise 07:16, Sunset 16:32 (EST, UTC-5)
        let date = TestDates.local(year: 2025, month: 12, day: 21, hour: 12, timezone: TestLocations.newYork.tz)
        let tz = TimeZone(identifier: TestLocations.newYork.tz)!
        let sunTimes = SolarCalculator.sunTimes(date: date, latitude: TestLocations.newYork.lat,
                                                longitude: TestLocations.newYork.lon, timeZone: tz)
        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 7, minute: 16, timezone: TestLocations.newYork.tz, toleranceMinutes: 3)
            assertTimeEquals(times.sunset,  hour: 16, minute: 32, timezone: TestLocations.newYork.tz, toleranceMinutes: 3)
        }
    }

    func test_sunTimes_tokyoSummerSolstice_matchesNOAA() {
        // Tokyo, June 21, 2025
        // NOAA reference: Sunrise 04:26, Sunset 19:01 (JST, UTC+9)
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: TestLocations.tokyo.tz)
        let tz = TimeZone(identifier: TestLocations.tokyo.tz)!
        let sunTimes = SolarCalculator.sunTimes(date: date, latitude: TestLocations.tokyo.lat,
                                                longitude: TestLocations.tokyo.lon, timeZone: tz)
        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 4, minute: 26, timezone: TestLocations.tokyo.tz, toleranceMinutes: 3)
            assertTimeEquals(times.sunset,  hour: 19, minute: 1,  timezone: TestLocations.tokyo.tz, toleranceMinutes: 3)
        }
    }

    func test_sunTimes_londonSummerSolstice_matchesNOAA() {
        // London, June 21, 2025
        // NOAA reference: Sunrise 04:43, Sunset 21:21 (BST, UTC+1)
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: "Europe/London")
        let tz = TimeZone(identifier: "Europe/London")!
        let sunTimes = SolarCalculator.sunTimes(date: date, latitude: 51.5074, longitude: -0.1278, timeZone: tz)
        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 4, minute: 43, timezone: "Europe/London", toleranceMinutes: 3)
            assertTimeEquals(times.sunset,  hour: 21, minute: 21, timezone: "Europe/London", toleranceMinutes: 3)
        }
    }

    func test_sunTimes_londonWinterSolstice_matchesNOAA() {
        // London, December 21, 2025
        // NOAA reference: Sunrise 08:03, Sunset 15:55 (GMT, UTC+0)
        let date = TestDates.local(year: 2025, month: 12, day: 21, hour: 12, timezone: "Europe/London")
        let tz = TimeZone(identifier: "Europe/London")!
        let sunTimes = SolarCalculator.sunTimes(date: date, latitude: 51.5074, longitude: -0.1278, timeZone: tz)
        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 8, minute: 3,  timezone: "Europe/London", toleranceMinutes: 3)
            assertTimeEquals(times.sunset,  hour: 15, minute: 55, timezone: "Europe/London", toleranceMinutes: 3)
        }
    }

    func test_sunTimes_sydneyDecember_southernHemisphere() {
        // Sydney, December 21, 2025 (Summer in southern hemisphere)
        // Expect long days (sunrise early, sunset late)
        let date = TestDates.local(year: 2025, month: 12, day: 21, hour: 12, timezone: TestLocations.sydney.tz)
        let tz = TimeZone(identifier: TestLocations.sydney.tz)!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.sydney.lat,
            longitude: TestLocations.sydney.lon,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            // Daylight should be long (14+ hours)
            let daylightHours = times.daylightDuration / 3600
            XCTAssertGreaterThan(daylightHours, 14)
        }
    }

    // MARK: - Equator Tests

    func test_sunTimes_equator_approximately12HourDays() {
        // At equator, day length is approximately 12 hours year-round
        let date = TestDates.utc(year: 2025, month: 6, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            let daylightHours = times.daylightDuration / 3600
            // Should be close to 12 hours (within 15 minutes)
            XCTAssertEqual(daylightHours, 12, accuracy: 0.25)
        }
    }

    // MARK: - Polar Region Tests (nil returns)

    func test_sunTimes_arcticMidnightSun_returnsNil() {
        // Svalbard (78°N), June 21 - 24-hour sun, no sunrise/sunset
        let date = TestDates.utc(year: 2025, month: 6, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.svalbard.lat,
            longitude: TestLocations.svalbard.lon,
            timeZone: tz
        )

        XCTAssertNil(sunTimes, "Should return nil during midnight sun period")
    }

    func test_sunTimes_arcticPolarNight_returnsNil() {
        // Svalbard (78°N), December 21 - polar night, no sunrise/sunset
        let date = TestDates.utc(year: 2025, month: 12, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.svalbard.lat,
            longitude: TestLocations.svalbard.lon,
            timeZone: tz
        )

        XCTAssertNil(sunTimes, "Should return nil during polar night")
    }

    func test_sunTimes_antarcticMidnightSun_returnsNil() {
        // McMurdo Station (78°S), December 21 - 24-hour sun
        let date = TestDates.utc(year: 2025, month: 12, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.mcmurdo.lat,
            longitude: TestLocations.mcmurdo.lon,
            timeZone: tz
        )

        XCTAssertNil(sunTimes, "Should return nil during Antarctic midnight sun")
    }

    func test_sunTimes_tromsoTransitionPeriod_mayHaveSunriseSunset() {
        // Tromso (69°N) in September should have normal sunrise/sunset
        let date = TestDates.utc(year: 2025, month: 9, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.tromso.lat,
            longitude: TestLocations.tromso.lon,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes, "Should have sunrise/sunset during equinox period")
    }

    // MARK: - Daylight Duration Tests

    func test_sunTimes_summerLongerThanWinter() {
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!

        let summerDate = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: TestLocations.stockholm.tz)
        let winterDate = TestDates.local(year: 2025, month: 12, day: 21, hour: 12, timezone: TestLocations.stockholm.tz)

        let summerTimes = SolarCalculator.sunTimes(
            date: summerDate,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        )

        let winterTimes = SolarCalculator.sunTimes(
            date: winterDate,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        )

        XCTAssertNotNil(summerTimes)
        XCTAssertNotNil(winterTimes)

        if let summer = summerTimes, let winter = winterTimes {
            XCTAssertGreaterThan(summer.daylightDuration, winter.daylightDuration)
            // Stockholm: Summer ~18.5 hours, Winter ~6 hours
            XCTAssertGreaterThan(summer.daylightDuration / 3600, 18)
            XCTAssertLessThan(winter.daylightDuration / 3600, 7)
        }
    }

    // MARK: - Solar Noon Tests

    func test_sunTimes_solarNoonBetweenSunriseAndSunset() {
        let date = TestDates.utc(year: 2025, month: 3, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            XCTAssertGreaterThan(times.solarNoon, times.sunrise)
            XCTAssertLessThan(times.solarNoon, times.sunset)
        }
    }

    // MARK: - Timezone Tests

    func test_sunTimes_utcTimezone_calculatesCorrectly() {
        let date = TestDates.utc(year: 2025, month: 6, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: 0,
            longitude: 0,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes)
    }

    func test_sunTimes_negativeTimezone_returnsValidTimes() {
        // Los Angeles (UTC-7/-8)
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: "America/Los_Angeles")
        let tz = TimeZone(identifier: "America/Los_Angeles")!

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: 34.0522,
            longitude: -118.2437,
            timeZone: tz
        )

        XCTAssertNotNil(sunTimes, "Should calculate sun times for negative timezone")
        if let times = sunTimes {
            // On summer solstice in LA, daylight should be long (14+ hours)
            let daylightHours = times.daylightDuration / 3600
            XCTAssertGreaterThan(daylightHours, 14, "Summer solstice should have long days")
        }
    }

    // MARK: - DST Change Days

    func test_sunTimes_stockholmAutumnDSTChangeDay_matchesNOAA() {
        // Stockholm, October 25, 2026 — clocks go back at 03:00 CEST → 02:00 CET
        // NOAA reference: Sunrise ~06:49, Sunset ~16:14 (local CET, UTC+1)
        let tzId = TestLocations.stockholm.tz
        let date = TestDates.local(year: 2026, month: 10, day: 25, hour: 12, timezone: tzId)

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: TimeZone(identifier: tzId)!
        )

        XCTAssertNotNil(sunTimes)
        if let times = sunTimes {
            assertTimeEquals(times.sunrise, hour: 6, minute: 49, timezone: tzId, toleranceMinutes: 5)
            assertTimeEquals(times.sunset, hour: 16, minute: 14, timezone: tzId, toleranceMinutes: 5)
        }
    }

    func test_sunTimes_dstChangeDays_stayContinuousWithPreviousDay() {
        // Sunrise moves by a few minutes a day in UTC; a DST change must not add an hour.
        let tzId = TestLocations.stockholm.tz
        let tz = TimeZone(identifier: tzId)!
        let changeDays = [(2026, 3, 29), (2026, 10, 25)]

        for (year, month, day) in changeDays {
            let before = TestDates.local(year: year, month: month, day: day - 1, hour: 12, timezone: tzId)
            let change = TestDates.local(year: year, month: month, day: day, hour: 12, timezone: tzId)
            let lat = TestLocations.stockholm.lat
            let lon = TestLocations.stockholm.lon

            guard let prev = SolarCalculator.sunTimes(date: before, latitude: lat, longitude: lon, timeZone: tz),
                  let curr = SolarCalculator.sunTimes(date: change, latitude: lat, longitude: lon, timeZone: tz),
                  let prevGolden = SolarCalculator.goldenHourTimes(date: before, latitude: lat, longitude: lon, timeZone: tz),
                  let currGolden = SolarCalculator.goldenHourTimes(date: change, latitude: lat, longitude: lon, timeZone: tz) else {
                XCTFail("Expected sun times for Stockholm on \(year)-\(month)-\(day)")
                continue
            }

            let oneDay: TimeInterval = 86_400
            XCTAssertEqual(curr.sunrise.timeIntervalSince(prev.sunrise), oneDay, accuracy: 5 * 60, "sunrise \(year)-\(month)-\(day)")
            XCTAssertEqual(curr.sunset.timeIntervalSince(prev.sunset), oneDay, accuracy: 5 * 60, "sunset \(year)-\(month)-\(day)")
            XCTAssertEqual(curr.solarNoon.timeIntervalSince(prev.solarNoon), oneDay, accuracy: 60, "solar noon \(year)-\(month)-\(day)")
            if let prevEnd = prevGolden.morningGoldenEnd, let currEnd = currGolden.morningGoldenEnd {
                XCTAssertEqual(currEnd.timeIntervalSince(prevEnd), oneDay, accuracy: 5 * 60, "golden hour \(year)-\(month)-\(day)")
            } else {
                XCTFail("Expected morning golden hour on \(year)-\(month)-\(day)")
            }
        }
    }
}
