import XCTest
@testable import AstroKit

/// Tests for SolarCalculator solar elevation and UV index calculations
final class SolarElevationTests: XCTestCase {

    // MARK: - Solar Elevation Tests

    func test_solarElevation_middayHigherThanMorning() {
        // Simple test: elevation at midday should be higher than at morning
        let morning = TestDates.utc(year: 2025, month: 6, day: 21, hour: 8)
        let midday = TestDates.utc(year: 2025, month: 6, day: 21, hour: 12)

        let morningElevation = SolarCalculator.solarElevation(
            at: morning,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )

        let middayElevation = SolarCalculator.solarElevation(
            at: midday,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )

        XCTAssertGreaterThan(middayElevation, morningElevation)
    }

    func test_solarElevation_atSunrise_isLow() {
        // At sunrise time, elevation should be near the horizon (low value)
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: TestLocations.stockholm.tz)

        guard let sunTimes = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        ) else {
            XCTFail("Should have sun times")
            return
        }

        let sunriseElevation = SolarCalculator.solarElevation(
            at: sunTimes.sunrise,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )

        // At sunrise, elevation should be low (between -10° and +10°)
        XCTAssertLessThan(abs(sunriseElevation), 10, "Elevation at sunrise should be near horizon, got \(sunriseElevation)")
    }

    func test_solarElevation_midnight_isNegative() {
        let midnight = TestDates.utc(year: 2025, month: 3, day: 21, hour: 0, minute: 0)

        let elevation = SolarCalculator.solarElevation(
            at: midnight,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon
        )

        XCTAssertLessThan(elevation, 0)
    }

    func test_solarElevation_summerHigherThanWinter() {
        let summerNoon = TestDates.utc(year: 2025, month: 6, day: 21, hour: 12)
        let winterNoon = TestDates.utc(year: 2025, month: 12, day: 21, hour: 12)

        let summerElevation = SolarCalculator.solarElevation(
            at: summerNoon,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )

        let winterElevation = SolarCalculator.solarElevation(
            at: winterNoon,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )

        XCTAssertGreaterThan(summerElevation, winterElevation)
    }

    // MARK: - Max Solar Elevation Tests

    func test_maxSolarElevation_returnsPositiveValue() {
        let date = TestDates.utc(year: 2025, month: 6, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let maxElevation = SolarCalculator.maxSolarElevation(
            date: date,
            latitude: TestLocations.newYork.lat,
            longitude: TestLocations.newYork.lon,
            timeZone: tz
        )

        XCTAssertNotNil(maxElevation)
        XCTAssertGreaterThan(maxElevation!, 0)
    }

    func test_maxSolarElevation_polarNight_returnsNil() {
        let date = TestDates.utc(year: 2025, month: 12, day: 21)
        let tz = TimeZone(identifier: "UTC")!

        let maxElevation = SolarCalculator.maxSolarElevation(
            date: date,
            latitude: TestLocations.svalbard.lat,
            longitude: TestLocations.svalbard.lon,
            timeZone: tz
        )

        XCTAssertNil(maxElevation, "Should return nil during polar night")
    }

    func test_maxSolarElevation_midLatitude_isPositive() {
        // At mid-latitude, max solar elevation should be positive during summer
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: TestLocations.stockholm.tz)

        let maxElevation = SolarCalculator.maxSolarElevation(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        )

        XCTAssertNotNil(maxElevation)
        // At mid-latitude in summer, max elevation should be positive and reasonable
        XCTAssertGreaterThan(maxElevation!, 40)
    }

    // MARK: - UV Index Tests

    func test_estimateUVIndex_zeroElevation_returnsZero() {
        let uvIndex = SolarCalculator.estimateUVIndex(elevation: 0)
        XCTAssertEqual(uvIndex, 0)
    }

    func test_estimateUVIndex_negativeElevation_returnsZero() {
        let uvIndex = SolarCalculator.estimateUVIndex(elevation: -10)
        XCTAssertEqual(uvIndex, 0)
    }

    func test_estimateUVIndex_highElevation_returnsHighUV() {
        let uvIndex = SolarCalculator.estimateUVIndex(elevation: 80)
        XCTAssertGreaterThan(uvIndex, 10)
    }

    func test_estimateUVIndex_moderateElevation_returnsModerateuV() {
        let uvIndex = SolarCalculator.estimateUVIndex(elevation: 45)
        XCTAssertGreaterThan(uvIndex, 3)
        XCTAssertLessThan(uvIndex, 9)
    }

    func test_estimateUVIndex_maxValue_clampedTo12() {
        let uvIndex = SolarCalculator.estimateUVIndex(elevation: 90)
        XCTAssertLessThanOrEqual(uvIndex, 12)
    }

    // MARK: - UV Level Tests

    func test_uvLevel_lowIndex_returnsLow() {
        let level = SolarCalculator.uvLevel(from: 2.0)
        XCTAssertEqual(level, .low)
    }

    func test_uvLevel_moderateIndex_returnsModerate() {
        let level = SolarCalculator.uvLevel(from: 4.0)
        XCTAssertEqual(level, .moderate)
    }

    func test_uvLevel_highIndex_returnsHigh() {
        let level = SolarCalculator.uvLevel(from: 7.0)
        XCTAssertEqual(level, .high)
    }

    func test_uvLevel_veryHighIndex_returnsVeryHigh() {
        let level = SolarCalculator.uvLevel(from: 9.0)
        XCTAssertEqual(level, .veryHigh)
    }

    func test_uvLevel_extremeIndex_returnsExtreme() {
        let level = SolarCalculator.uvLevel(from: 11.5)
        XCTAssertEqual(level, .extreme)
    }

    func test_uvLevel_boundaries_correct() {
        XCTAssertEqual(SolarCalculator.uvLevel(from: 2.9), .low)
        XCTAssertEqual(SolarCalculator.uvLevel(from: 3.0), .moderate)
        XCTAssertEqual(SolarCalculator.uvLevel(from: 5.9), .moderate)
        XCTAssertEqual(SolarCalculator.uvLevel(from: 6.0), .high)
        XCTAssertEqual(SolarCalculator.uvLevel(from: 7.9), .high)
        XCTAssertEqual(SolarCalculator.uvLevel(from: 8.0), .veryHigh)
        XCTAssertEqual(SolarCalculator.uvLevel(from: 10.9), .veryHigh)
        XCTAssertEqual(SolarCalculator.uvLevel(from: 11.0), .extreme)
    }

    // MARK: - UVLevel Enum Tests

    func test_uvLevel_allCasesHaveColors() {
        XCTAssertEqual(SolarCalculator.UVLevel.low.color, "green")
        XCTAssertEqual(SolarCalculator.UVLevel.moderate.color, "yellow")
        XCTAssertEqual(SolarCalculator.UVLevel.high.color, "orange")
        XCTAssertEqual(SolarCalculator.UVLevel.veryHigh.color, "red")
        XCTAssertEqual(SolarCalculator.UVLevel.extreme.color, "purple")
    }
}
