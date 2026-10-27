import XCTest
@testable import AstroKit

/// Tests for MoonCalculator lunar position and zodiac calculations
final class LunarPositionTests: XCTestCase {

    // MARK: - Ecliptic Longitude Tests

    func test_lunarPosition_eclipticLongitude_inValidRange() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)

        let position = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        XCTAssertGreaterThanOrEqual(position.eclipticLongitude, 0)
        XCTAssertLessThan(position.eclipticLongitude, 360)
    }

    func test_lunarPosition_eclipticLongitude_progressesThroughMonth() {
        // Moon moves about 13° per day through the zodiac
        let date1 = TestDates.utc(year: 2025, month: 3, day: 1)
        let date2 = TestDates.utc(year: 2025, month: 3, day: 3)

        let pos1 = MoonCalculator.lunarPosition(at: date1, latitude: 0, longitude: 0)
        let pos2 = MoonCalculator.lunarPosition(at: date2, latitude: 0, longitude: 0)

        // Should have moved about 26° in 2 days
        var diff = pos2.eclipticLongitude - pos1.eclipticLongitude
        if diff < 0 { diff += 360 } // Handle wraparound

        XCTAssertGreaterThan(diff, 20)
        XCTAssertLessThan(diff, 35)
    }

    // MARK: - Zodiac Tests

    func test_lunarPosition_zodiac_matchesLongitude() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)

        let position = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )

        // Each zodiac sign spans 30°
        let expectedIndex = Int(position.eclipticLongitude / 30)
        let expectedZodiac = MoonCalculator.ZodiacConstellation.allCases[expectedIndex]

        XCTAssertEqual(position.constellation, expectedZodiac)
    }

    func test_lunarPosition_zodiac_coversAllSigns() {
        // Over ~28 days, moon should visit all 12 zodiac signs
        var signsVisited: Set<MoonCalculator.ZodiacConstellation> = []
        let startDate = TestDates.utc(year: 2025, month: 1, day: 1)

        for day in 0..<30 {
            let date = startDate.addingTimeInterval(Double(day) * 86400)
            let position = MoonCalculator.lunarPosition(at: date, latitude: 0, longitude: 0)
            signsVisited.insert(position.constellation)
        }

        XCTAssertEqual(signsVisited.count, 12, "Moon should visit all 12 zodiac signs in a month")
    }

    // MARK: - Altitude and Azimuth Tests

    func test_lunarPosition_altitude_inValidRange() {
        let date = TestDates.utc(year: 2025, month: 6, day: 15, hour: 22)

        let position = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        XCTAssertGreaterThanOrEqual(position.altitude, -90)
        XCTAssertLessThanOrEqual(position.altitude, 90)
    }

    func test_lunarPosition_azimuth_inValidRange() {
        let date = TestDates.utc(year: 2025, month: 6, day: 15, hour: 22)

        let position = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        XCTAssertGreaterThanOrEqual(position.azimuth, 0)
        XCTAssertLessThan(position.azimuth, 360)
    }

    func test_lunarPosition_altitudeChanges_overDay() {
        let date1 = TestDates.utc(year: 2025, month: 3, day: 15, hour: 0)
        let date2 = TestDates.utc(year: 2025, month: 3, day: 15, hour: 12)

        let pos1 = MoonCalculator.lunarPosition(
            at: date1,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        let pos2 = MoonCalculator.lunarPosition(
            at: date2,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        // Altitude should be different at midnight vs noon
        XCTAssertNotEqual(pos1.altitude, pos2.altitude, accuracy: 1)
    }

    // MARK: - Right Ascension and Declination Tests

    func test_lunarPosition_rightAscension_inValidRange() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)

        let position = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )

        XCTAssertGreaterThanOrEqual(position.rightAscension, 0)
        XCTAssertLessThan(position.rightAscension, 360)
    }

    func test_lunarPosition_declination_inValidRange() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)

        let position = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )

        // Moon's declination ranges about ±28.5° (±23.5° obliquity ± 5° lunar inclination)
        XCTAssertGreaterThanOrEqual(position.declination, -30)
        XCTAssertLessThanOrEqual(position.declination, 30)
    }

    // MARK: - Location Independence Tests

    func test_lunarPosition_eclipticCoordinates_independentOfObserver() {
        let date = TestDates.utc(year: 2025, month: 6, day: 15, hour: 12)

        let posNY = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        let posSydney = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.sydney.lat,
            longitude: TestLocations.sydney.lon
        )

        // Ecliptic longitude should be the same regardless of observer
        XCTAssertEqual(posNY.eclipticLongitude, posSydney.eclipticLongitude, accuracy: 1)
        XCTAssertEqual(posNY.constellation, posSydney.constellation)
    }

    func test_lunarPosition_horizontalCoordinates_dependOnObserver() {
        let date = TestDates.utc(year: 2025, month: 6, day: 15, hour: 12)

        let posNY = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        let posSydney = MoonCalculator.lunarPosition(
            at: date,
            latitude: TestLocations.sydney.lat,
            longitude: TestLocations.sydney.lon
        )

        // Altitude OR azimuth should differ for different observers
        // (One might coincidentally be similar, but not both)
        let altitudeDiff = abs(posNY.altitude - posSydney.altitude)
        let azimuthDiff = abs(posNY.azimuth - posSydney.azimuth)

        let hasDifference = altitudeDiff > 1 || azimuthDiff > 1
        XCTAssertTrue(hasDifference, "Horizontal coordinates should differ: altitude diff=\(altitudeDiff), azimuth diff=\(azimuthDiff)")
    }

    // MARK: - Zodiac Enum Tests

    func test_zodiacConstellation_allCasesHaveSymbols() {
        for constellation in MoonCalculator.ZodiacConstellation.allCases {
            XCTAssertFalse(constellation.symbol.isEmpty)
            XCTAssertFalse(constellation.rawValue.isEmpty)
            XCTAssertFalse(constellation.element.isEmpty)
        }
    }

    func test_zodiacConstellation_elementsAreValid() {
        let validElements = ["Fire", "Earth", "Air", "Water"]
        for constellation in MoonCalculator.ZodiacConstellation.allCases {
            XCTAssertTrue(validElements.contains(constellation.element))
        }
    }
}
