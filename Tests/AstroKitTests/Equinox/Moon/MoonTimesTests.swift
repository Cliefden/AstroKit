import XCTest
@testable import AstroKit

/// Tests for MoonCalculator moonrise/moonset calculations
final class MoonTimesTests: XCTestCase {

    // MARK: - Standard Location Tests

    func test_moonTimes_standardLocation_returnsValidTimes() {
        let date = TestDates.utc(year: 2025, month: 1, day: 15)

        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )

        // At least one of moonrise/moonset should be present on most days
        let hasRiseOrSet = moonTimes.moonrise != nil || moonTimes.moonset != nil
        XCTAssertTrue(hasRiseOrSet, "Should have moonrise or moonset on a typical day")
    }

    func test_moonTimes_transitTime_isCalculated() {
        let date = TestDates.utc(year: 2025, month: 1, day: 15)

        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )

        XCTAssertNotNil(moonTimes.transitTime, "Transit time should always be calculated")
    }

    func test_moonTimes_moonriseBeforeTransitBeforeMoonset() {
        // On days with both moonrise and moonset, transit should be between them
        let date = TestDates.utc(year: 2025, month: 1, day: 15)

        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        if let rise = moonTimes.moonrise, let transit = moonTimes.transitTime, let set = moonTimes.moonset {
            // Note: Moon can set before rising on some days due to crossing midnight
            // This test is for the common case
            if rise < set {
                XCTAssertGreaterThan(transit, rise)
                XCTAssertLessThan(transit, set)
            }
        }
    }

    // MARK: - Different Locations

    func test_moonTimes_equator_hasValidTimes() {
        let date = TestDates.utc(year: 2025, month: 6, day: 15)

        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )

        XCTAssertNotNil(moonTimes.transitTime)
    }

    func test_moonTimes_southernHemisphere_hasValidTimes() {
        let date = TestDates.utc(year: 2025, month: 6, day: 15)

        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.sydney.lat,
            longitude: TestLocations.sydney.lon
        )

        XCTAssertNotNil(moonTimes.transitTime)
    }

    // MARK: - Polar Region Tests

    func test_moonTimes_arcticCircle_mayHaveCircumpolarMoon() {
        // At very high latitudes, moon may not rise/set on some days
        let date = TestDates.utc(year: 2025, month: 6, day: 21)

        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.svalbard.lat,
            longitude: TestLocations.svalbard.lon
        )

        // Transit should still be calculated even if no rise/set
        XCTAssertNotNil(moonTimes.transitTime)
    }

    // MARK: - Daily Progression Tests

    func test_moonTimes_dailyProgression_shiftsLater() {
        // Moonrise/moonset shifts approximately 50 minutes later each day
        let date1 = TestDates.utc(year: 2025, month: 3, day: 15)
        let date2 = TestDates.utc(year: 2025, month: 3, day: 16)
        // Re-baselined for 0.2: scan New York's own day. It used the process
        // time zone, so in zones west of New York (e.g. TZ=America/Los_Angeles)
        // the ~01:45 EDT transit fell at the edge of the scanned local day and
        // the comparison failed, in 0.1 as well as in 0.2. Expected New York
        // transits: 01:45 EDT (Mar 15) and 02:25 EDT (Mar 16).
        let tz = TimeZone(identifier: TestLocations.newYork.tz)!

        let times1 = MoonCalculator.moonTimes(
            date: date1,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        let times2 = MoonCalculator.moonTimes(
            date: date2,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        // If both days have transits, day 2 should be later
        XCTAssertNotNil(times1.transitTime)
        XCTAssertNotNil(times2.transitTime)
        if let transit1 = times1.transitTime, let transit2 = times2.transitTime {
            // Get minutes from midnight for comparison
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let mins1 = cal.component(.hour, from: transit1) * 60 + cal.component(.minute, from: transit1)
            let mins2 = cal.component(.hour, from: transit2) * 60 + cal.component(.minute, from: transit2)

            // Account for day wrapping (if transit2 wraps to early morning)
            let diff = mins2 - mins1
            let adjustedDiff = diff < -720 ? diff + 1440 : diff

            // Should be later by roughly 30-70 minutes (average ~50)
            XCTAssertGreaterThan(adjustedDiff, 20)
            XCTAssertLessThan(adjustedDiff, 100)
        }
    }

    // MARK: - Edge Cases

    func test_moonTimes_northPole_handlesExtreme() {
        let date = TestDates.utc(year: 2025, month: 6, day: 21)

        // Should not crash at North Pole
        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.northPole.lat,
            longitude: TestLocations.northPole.lon
        )

        // May or may not have rise/set at poles
        XCTAssertNotNil(moonTimes) // Just verify it returns something
    }

    func test_moonTimes_southPole_handlesExtreme() {
        let date = TestDates.utc(year: 2025, month: 12, day: 21)

        // Should not crash at South Pole
        let moonTimes = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.southPole.lat,
            longitude: TestLocations.southPole.lon
        )

        XCTAssertNotNil(moonTimes)
    }

    // MARK: - Precision Tests Against Reference Data
    // Reference: timeanddate.com moonrise/moonset data.
    // Tolerance is ±8 min (lunar orbit perturbations make moon times inherently less precise
    // than solar times; ±8 min matches typical tool-to-tool agreement).

    func test_moonTimes_stockholmFullMoonJan2025_matchesReference() {
        // Full Moon: January 13, 2025 at 22:27 UTC.
        // timeanddate.com Stockholm: moonrise 13:54 CET, moonset 09:40 CET.
        let date = TestDates.local(year: 2025, month: 1, day: 13, hour: 12, timezone: TestLocations.stockholm.tz)
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!
        let t = MoonCalculator.moonTimes(date: date, latitude: TestLocations.stockholm.lat,
                                         longitude: TestLocations.stockholm.lon, timeZone: tz)
        if let rise = t.moonrise {
            assertTimeEquals(rise, hour: 13, minute: 54, timezone: TestLocations.stockholm.tz, toleranceMinutes: 8)
        } else { XCTFail("moonrise should not be nil") }
        if let set = t.moonset {
            assertTimeEquals(set, hour: 9, minute: 40, timezone: TestLocations.stockholm.tz, toleranceMinutes: 8)
        } else { XCTFail("moonset should not be nil") }
    }

    func test_moonTimes_newYorkFullMoonJan2025_matchesReference() {
        // Full Moon: January 13, 2025.
        // timeanddate.com New York: moonrise 16:38 EST, moonset 07:40 EST.
        let date = TestDates.local(year: 2025, month: 1, day: 13, hour: 12, timezone: TestLocations.newYork.tz)
        let tz = TimeZone(identifier: TestLocations.newYork.tz)!
        let t = MoonCalculator.moonTimes(date: date, latitude: TestLocations.newYork.lat,
                                         longitude: TestLocations.newYork.lon, timeZone: tz)
        if let rise = t.moonrise {
            assertTimeEquals(rise, hour: 16, minute: 38, timezone: TestLocations.newYork.tz, toleranceMinutes: 8)
        } else { XCTFail("moonrise should not be nil") }
        if let set = t.moonset {
            assertTimeEquals(set, hour: 7, minute: 40, timezone: TestLocations.newYork.tz, toleranceMinutes: 8)
        } else { XCTFail("moonset should not be nil") }
    }

    func test_moonTimes_stockholmFullMoonSep2025_matchesReference() {
        // Full Moon: September 7, 2025.
        // timeanddate.com Stockholm: moonrise 19:20 CEST (13 min before sunset).
        let date = TestDates.local(year: 2025, month: 9, day: 7, hour: 12, timezone: TestLocations.stockholm.tz)
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!
        let t = MoonCalculator.moonTimes(date: date, latitude: TestLocations.stockholm.lat,
                                         longitude: TestLocations.stockholm.lon, timeZone: tz)
        if let rise = t.moonrise {
            assertTimeEquals(rise, hour: 19, minute: 20, timezone: TestLocations.stockholm.tz, toleranceMinutes: 8)
        } else { XCTFail("moonrise should not be nil") }
    }

    func test_moonTimes_newYorkFullMoonSep2025_matchesReference() {
        // Full Moon: September 7, 2025 (close to Harvest Moon).
        // timeanddate.com New York: moonrise 19:12 EDT (7 min before sunset).
        let date = TestDates.local(year: 2025, month: 9, day: 7, hour: 12, timezone: TestLocations.newYork.tz)
        let tz = TimeZone(identifier: TestLocations.newYork.tz)!
        let t = MoonCalculator.moonTimes(date: date, latitude: TestLocations.newYork.lat,
                                         longitude: TestLocations.newYork.lon, timeZone: tz)
        if let rise = t.moonrise {
            assertTimeEquals(rise, hour: 19, minute: 12, timezone: TestLocations.newYork.tz, toleranceMinutes: 8)
        } else { XCTFail("moonrise should not be nil") }
    }

    func test_moonTimes_stockholmFullMoonMar2025_matchesReference() {
        // Full Moon (total lunar eclipse): March 14, 2025.
        // timeanddate.com Stockholm: moonrise 18:23 CET.
        let date = TestDates.local(year: 2025, month: 3, day: 14, hour: 12, timezone: TestLocations.stockholm.tz)
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!
        let t = MoonCalculator.moonTimes(date: date, latitude: TestLocations.stockholm.lat,
                                         longitude: TestLocations.stockholm.lon, timeZone: tz)
        if let rise = t.moonrise {
            assertTimeEquals(rise, hour: 18, minute: 23, timezone: TestLocations.stockholm.tz, toleranceMinutes: 8)
        } else { XCTFail("moonrise should not be nil") }
    }

    func test_moonTimes_newYorkFullMoonMar2025_matchesReference() {
        // Full Moon (total lunar eclipse visible from Americas): March 14, 2025.
        // timeanddate.com New York: moonrise 19:46 EDT.
        let date = TestDates.local(year: 2025, month: 3, day: 14, hour: 12, timezone: TestLocations.newYork.tz)
        let tz = TimeZone(identifier: TestLocations.newYork.tz)!
        let t = MoonCalculator.moonTimes(date: date, latitude: TestLocations.newYork.lat,
                                         longitude: TestLocations.newYork.lon, timeZone: tz)
        if let rise = t.moonrise {
            assertTimeEquals(rise, hour: 19, minute: 46, timezone: TestLocations.newYork.tz, toleranceMinutes: 8)
        } else { XCTFail("moonrise should not be nil") }
    }

    // MARK: - Consistency Tests

    func test_moonTimes_sameInputs_sameOutputs() {
        let date = TestDates.utc(year: 2025, month: 5, day: 10)

        let times1 = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.tokyo.lat,
            longitude: TestLocations.tokyo.lon
        )

        let times2 = MoonCalculator.moonTimes(
            date: date,
            latitude: TestLocations.tokyo.lat,
            longitude: TestLocations.tokyo.lon
        )

        XCTAssertEqual(times1.moonrise, times2.moonrise)
        XCTAssertEqual(times1.moonset, times2.moonset)
        XCTAssertEqual(times1.transitTime, times2.transitTime)
    }
}
