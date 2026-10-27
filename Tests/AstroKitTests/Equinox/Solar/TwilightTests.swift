import XCTest
@testable import AstroKit

/// Tests for SolarCalculator twilight calculations
final class TwilightTests: XCTestCase {

    // MARK: - Twilight Order Tests

    func test_twilightTimes_orderDawnToSunrise() {
        let date = TestDates.utc(year: 2025, month: 3, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let twilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        XCTAssertNotNil(twilight)
        if let t = twilight {
            // Order should be: astronomical dawn < nautical dawn < civil dawn < sunrise
            if let astro = t.astronomicalDawn, let naut = t.nauticalDawn {
                XCTAssertLessThan(astro, naut)
            }
            if let naut = t.nauticalDawn, let civil = t.civilDawn {
                XCTAssertLessThan(naut, civil)
            }
            if let civil = t.civilDawn {
                XCTAssertLessThan(civil, t.sunrise)
            }
        }
    }

    func test_twilightTimes_orderSunsetToDusk() {
        let date = TestDates.utc(year: 2025, month: 3, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let twilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        XCTAssertNotNil(twilight)
        if let t = twilight {
            // Order should be: sunset < civil dusk < nautical dusk < astronomical dusk
            if let civil = t.civilDusk {
                XCTAssertLessThan(t.sunset, civil)
            }
            if let civil = t.civilDusk, let naut = t.nauticalDusk {
                XCTAssertLessThan(civil, naut)
            }
            if let naut = t.nauticalDusk, let astro = t.astronomicalDusk {
                XCTAssertLessThan(naut, astro)
            }
        }
    }

    // MARK: - Twilight Duration Tests

    func test_twilightTimes_civilTwilightDuration_reasonable() {
        let date = TestDates.utc(year: 2025, month: 3, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let twilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        XCTAssertNotNil(twilight)
        if let t = twilight, let civilDawn = t.civilDawn {
            // Civil twilight (6 degrees) typically lasts 20-35 minutes at mid-latitudes
            let dawnDuration = t.sunrise.timeIntervalSince(civilDawn) / 60
            XCTAssertGreaterThan(dawnDuration, 15)
            XCTAssertLessThan(dawnDuration, 45)
        }
    }

    func test_twilightTimes_highLatitude_longerTwilight() {
        let date = TestDates.utc(year: 2025, month: 6, day: 15)
        let tz = TimeZone(identifier: "UTC")!

        // Tromso (69°N) should have longer twilight than New York
        let tromsoTwilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.tromso.lat,
            longitude: TestLocations.tromso.lon,
            timeZone: tz
        )

        let nyTwilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        // During summer at high latitudes, twilight is much longer
        // In fact, Tromso may not have astronomical darkness at all
        if let tromso = tromsoTwilight, let ny = nyTwilight,
           let tromsoCivil = tromso.civilDawn, let nyCivil = ny.civilDawn {
            let tromsoCivilDuration = tromso.sunrise.timeIntervalSince(tromsoCivil)
            let nyCivilDuration = ny.sunrise.timeIntervalSince(nyCivil)
            XCTAssertGreaterThan(tromsoCivilDuration, nyCivilDuration)
        }
    }

    // MARK: - Polar Region Tests

    func test_twilightTimes_polarRegion_returnsNil() {
        // During polar day/night, twilight should return nil
        let date = TestDates.utc(year: 2025, month: 6, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let twilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.svalbard.lat,
            longitude: TestLocations.svalbard.lon,
            timeZone: tz
        )

        XCTAssertNil(twilight, "Should return nil during midnight sun")
    }

    // MARK: - Equator Tests

    func test_twilightTimes_equator_shortTwilight() {
        // Near equator, twilight is shorter than at higher latitudes
        let date = TestDates.utc(year: 2025, month: 3, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let twilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon,
            timeZone: tz
        )

        XCTAssertNotNil(twilight)
        if let t = twilight, let civilDawn = t.civilDawn {
            // At equator, civil twilight is about 20-25 minutes
            let dawnDuration = t.sunrise.timeIntervalSince(civilDawn) / 60
            XCTAssertLessThan(dawnDuration, 30)
        }
    }

    // MARK: - Consistency Tests

    func test_twilightTimes_containsSunriseAndSunset() {
        let date = TestDates.utc(year: 2025, month: 3, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let twilight = SolarCalculator.twilightTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        )

        let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        )

        XCTAssertNotNil(twilight)
        XCTAssertNotNil(sunTimes)

        if let t = twilight, let s = sunTimes {
            // Twilight sunrise/sunset should match sunTimes
            assertDatesEqual(t.sunrise, s.sunrise, toleranceMinutes: 0.1)
            assertDatesEqual(t.sunset, s.sunset, toleranceMinutes: 0.1)
        }
    }
}
