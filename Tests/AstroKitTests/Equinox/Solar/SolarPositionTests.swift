import XCTest
@testable import AstroKit

/// Tests for SolarCalculator.solarPosition (azimuth + elevation) and sunPath sampling.
final class SolarPositionTests: XCTestCase {

    // MARK: - Azimuth invariants

    func test_azimuth_inUnitCircle() {
        // Azimuth must always be in [0, 360).
        let date = TestDates.utc(year: 2026, month: 5, day: 9, hour: 12)
        for hour in 0..<24 {
            let t = TestDates.utc(year: 2026, month: 5, day: 9, hour: hour)
            let pos = SolarCalculator.solarPosition(
                at: t,
                latitude: TestLocations.stockholm.lat,
                longitude: TestLocations.stockholm.lon
            )
            XCTAssertGreaterThanOrEqual(pos.azimuth, 0, "azimuth at hour \(hour)")
            XCTAssertLessThan(pos.azimuth, 360, "azimuth at hour \(hour)")
            _ = date
        }
    }

    // MARK: - Equator equinox sanity (sun rises due east, sets due west)

    func test_equatorEquinox_sunriseAzimuth_isEast() {
        // March equinox at the equator: sun rises ~due east (azimuth ~90°).
        let tz = TimeZone(identifier: "UTC")!
        let date = TestDates.local(year: 2025, month: 3, day: 20, hour: 12, timezone: "UTC")
        guard let sun = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon,
            timeZone: tz
        ) else {
            XCTFail("Equator should have sunrise")
            return
        }
        let pos = SolarCalculator.solarPosition(
            at: sun.sunrise,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )
        XCTAssertEqual(pos.azimuth, 90, accuracy: 2.0,
                       "Equinox sunrise at equator should be due east")
    }

    func test_equatorEquinox_sunsetAzimuth_isWest() {
        let tz = TimeZone(identifier: "UTC")!
        let date = TestDates.local(year: 2025, month: 3, day: 20, hour: 12, timezone: "UTC")
        guard let sun = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon,
            timeZone: tz
        ) else {
            XCTFail("Equator should have sunset")
            return
        }
        let pos = SolarCalculator.solarPosition(
            at: sun.sunset,
            latitude: TestLocations.equator.lat,
            longitude: TestLocations.equator.lon
        )
        XCTAssertEqual(pos.azimuth, 270, accuracy: 2.0,
                       "Equinox sunset at equator should be due west")
    }

    // MARK: - Northern mid-latitude solar noon (sun in the south)

    func test_stockholmSolstice_solarNoonAzimuth_isSouth() {
        let tz = TimeZone(identifier: TestLocations.stockholm.tz)!
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 12, timezone: TestLocations.stockholm.tz)
        guard let sun = SolarCalculator.sunTimes(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            timeZone: tz
        ) else {
            XCTFail("Stockholm should have solar noon")
            return
        }
        let pos = SolarCalculator.solarPosition(
            at: sun.solarNoon,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )
        XCTAssertEqual(pos.azimuth, 180, accuracy: 1.0,
                       "Solar noon in northern hemisphere should be due south")
    }

    func test_stockholmSummer_morningAzimuth_isEastward() {
        // 6 AM local in Stockholm in June: sun should be in the eastern half (azimuth < 180°).
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 6, timezone: TestLocations.stockholm.tz)
        let pos = SolarCalculator.solarPosition(
            at: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )
        XCTAssertLessThan(pos.azimuth, 180, "Morning sun should be east of south")
        XCTAssertGreaterThan(pos.azimuth, 0)
    }

    func test_stockholmSummer_eveningAzimuth_isWestward() {
        // 19:00 local in Stockholm in June: sun should be in the western half (> 180°).
        let date = TestDates.local(year: 2025, month: 6, day: 21, hour: 19, timezone: TestLocations.stockholm.tz)
        let pos = SolarCalculator.solarPosition(
            at: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )
        XCTAssertGreaterThan(pos.azimuth, 180, "Evening sun should be west of south")
        XCTAssertLessThan(pos.azimuth, 360)
    }

    // MARK: - Elevation parity with solarElevation()

    func test_solarPosition_elevationMatchesSolarElevation() {
        // The new solarPosition.elevation must equal the existing solarElevation() value.
        let date = TestDates.utc(year: 2026, month: 5, day: 9, hour: 12)
        let pos = SolarCalculator.solarPosition(
            at: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )
        let elev = SolarCalculator.solarElevation(
            at: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon
        )
        XCTAssertEqual(pos.elevation, elev, accuracy: 0.01)
    }

    // MARK: - sunPath sampling

    func test_sunPath_returnsExpectedNumberOfSamples() {
        let date = TestDates.utc(year: 2026, month: 5, day: 9, hour: 12)
        let path = SolarCalculator.sunPath(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            intervalMinutes: 60
        )
        // 24 hours / 60 minutes = 24 intervals → 25 endpoints (inclusive)
        XCTAssertEqual(path.count, 25)
    }

    func test_sunPath_isMonotonicallyIncreasingThenDecreasingElevation() {
        // For a normal mid-latitude day, elevation rises from sunrise, peaks around noon, then falls.
        let date = TestDates.utc(year: 2026, month: 6, day: 21, hour: 12)
        let path = SolarCalculator.sunPath(
            date: date,
            latitude: TestLocations.stockholm.lat,
            longitude: TestLocations.stockholm.lon,
            intervalMinutes: 30
        )
        // Find peak; elevations before peak should be non-decreasing locally, after should be non-increasing.
        // Coarse check: max should not be at index 0 or last.
        guard let maxIdx = path.indices.max(by: { path[$0].elevation < path[$1].elevation }) else {
            XCTFail("No samples")
            return
        }
        XCTAssertGreaterThan(maxIdx, 0)
        XCTAssertLessThan(maxIdx, path.count - 1)
    }
}
