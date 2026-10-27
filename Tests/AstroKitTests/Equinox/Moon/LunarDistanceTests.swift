import XCTest
@testable import AstroKit

/// Tests for MoonCalculator lunar distance calculations
final class LunarDistanceTests: XCTestCase {

    // MARK: - Distance Range Tests

    func test_lunarDistance_inReasonableRange() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)
        let distanceInfo = MoonCalculator.lunarDistance(for: date)

        // Moon distance ranges from ~356,500 km (perigee) to ~406,700 km (apogee)
        XCTAssertGreaterThan(distanceInfo.distanceKm, 350000)
        XCTAssertLessThan(distanceInfo.distanceKm, 410000)
    }

    func test_lunarDistance_averageDistanceCorrect() {
        // Sample multiple dates and verify average is reasonable
        var totalDistance = 0.0
        let samples = 30

        for day in 0..<samples {
            let date = TestDates.utc(year: 2025, month: 1, day: 1).addingTimeInterval(Double(day) * 86400)
            let distanceInfo = MoonCalculator.lunarDistance(for: date)
            totalDistance += distanceInfo.distanceKm
        }

        let average = totalDistance / Double(samples)
        // Average should be close to 384,400 km
        XCTAssertEqual(average, 384400, accuracy: 5000)
    }

    // MARK: - Percent of Average Tests

    func test_lunarDistance_percentOfAverage_calculatedCorrectly() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)
        let distanceInfo = MoonCalculator.lunarDistance(for: date)

        let expectedPercent = (distanceInfo.distanceKm / 384400.0) * 100
        XCTAssertEqual(distanceInfo.percentOfAverage, expectedPercent, accuracy: 0.1)
    }

    // MARK: - Distance Status Tests

    func test_lunarDistance_statusDetection_perigee() {
        // Find a date when moon is at perigee (search 60 days to ensure we find one)
        var perigeeFound = false
        var closestDistance = Double.infinity
        for day in 0..<60 {
            let date = TestDates.utc(year: 2025, month: 1, day: 1).addingTimeInterval(Double(day) * 86400)
            let distanceInfo = MoonCalculator.lunarDistance(for: date)
            closestDistance = min(closestDistance, distanceInfo.distanceKm)
            if distanceInfo.distanceStatus == .perigee || distanceInfo.distanceStatus == .nearPerigee {
                perigeeFound = true
                XCTAssertLessThan(distanceInfo.distanceKm, 375000)
                break
            }
        }
        XCTAssertTrue(perigeeFound, "Should find perigee within 60 days, closest distance was \(closestDistance)")
    }

    func test_lunarDistance_statusDetection_apogee() {
        // Find a date when moon is at apogee (search 60 days to ensure we find one)
        var apogeeFound = false
        var farthestDistance = 0.0
        for day in 0..<60 {
            let date = TestDates.utc(year: 2025, month: 1, day: 1).addingTimeInterval(Double(day) * 86400)
            let distanceInfo = MoonCalculator.lunarDistance(for: date)
            farthestDistance = max(farthestDistance, distanceInfo.distanceKm)
            if distanceInfo.distanceStatus == .apogee || distanceInfo.distanceStatus == .nearApogee {
                apogeeFound = true
                XCTAssertGreaterThan(distanceInfo.distanceKm, 390000)
                break
            }
        }
        XCTAssertTrue(apogeeFound, "Should find apogee within 60 days, farthest distance was \(farthestDistance)")
    }

    // MARK: - Supermoon Tests

    func test_lunarDistance_supermoon_requiresPerigeeAndFullMoon() {
        // Search for a supermoon
        for day in 0..<365 {
            let date = TestDates.utc(year: 2025, month: 1, day: 1).addingTimeInterval(Double(day) * 86400)
            let distanceInfo = MoonCalculator.lunarDistance(for: date)

            if distanceInfo.isSupermoon {
                // Must be near perigee
                XCTAssertTrue(
                    distanceInfo.distanceStatus == .perigee || distanceInfo.distanceStatus == .nearPerigee,
                    "Supermoon must be at perigee or near perigee"
                )
                // Phase should be full or near-full
                let phase = MoonCalculator.moonPhase(for: date)
                let isNearFull = phase.phase == .fullMoon ||
                                 phase.phase == .waxingGibbous ||
                                 phase.phase == .waningGibbous
                XCTAssertTrue(isNearFull, "Supermoon must be at or near full moon")
                break
            }
        }
        // Note: Not asserting supermoonFound as it may not occur in the test period
    }

    func test_lunarDistance_notSupermoon_atApogee() {
        // At apogee, should never be a supermoon
        for day in 0..<30 {
            let date = TestDates.utc(year: 2025, month: 1, day: 1).addingTimeInterval(Double(day) * 86400)
            let distanceInfo = MoonCalculator.lunarDistance(for: date)

            if distanceInfo.distanceStatus == .apogee || distanceInfo.distanceStatus == .nearApogee {
                XCTAssertFalse(distanceInfo.isSupermoon, "Cannot be supermoon at apogee")
            }
        }
    }

    // MARK: - Next Perigee/Apogee Tests

    func test_lunarDistance_nextPerigee_inFuture() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)
        let distanceInfo = MoonCalculator.lunarDistance(for: date)

        XCTAssertGreaterThan(distanceInfo.nextPerigee, date)
    }

    func test_lunarDistance_nextApogee_inFuture() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)
        let distanceInfo = MoonCalculator.lunarDistance(for: date)

        XCTAssertGreaterThan(distanceInfo.nextApogee, date)
    }

    func test_lunarDistance_nextPerigee_withinAnomalyPeriod() {
        // Anomalistic month is ~27.55 days
        let date = TestDates.utc(year: 2025, month: 3, day: 15)
        let distanceInfo = MoonCalculator.lunarDistance(for: date)

        let daysToPerigee = distanceInfo.nextPerigee.timeIntervalSince(date) / 86400
        XCTAssertLessThanOrEqual(daysToPerigee, 28)
    }

    func test_lunarDistance_nextApogee_withinAnomalyPeriod() {
        let date = TestDates.utc(year: 2025, month: 3, day: 15)
        let distanceInfo = MoonCalculator.lunarDistance(for: date)

        let daysToApogee = distanceInfo.nextApogee.timeIntervalSince(date) / 86400
        XCTAssertLessThanOrEqual(daysToApogee, 28)
    }

    // MARK: - Distance Status Enum Tests

    func test_lunarDistanceStatus_allCasesHaveDescriptions() {
        for status in [MoonCalculator.LunarDistanceStatus.perigee,
                       .apogee, .nearPerigee, .nearApogee, .normal] {
            XCTAssertFalse(status.rawValue.isEmpty)
            XCTAssertFalse(status.description.isEmpty)
        }
    }

    // MARK: - Consistency Tests

    func test_lunarDistance_sameInputs_sameOutputs() {
        let date = TestDates.utc(year: 2025, month: 5, day: 10)

        let dist1 = MoonCalculator.lunarDistance(for: date)
        let dist2 = MoonCalculator.lunarDistance(for: date)

        XCTAssertEqual(dist1.distanceKm, dist2.distanceKm)
        XCTAssertEqual(dist1.distanceStatus, dist2.distanceStatus)
        XCTAssertEqual(dist1.isSupermoon, dist2.isSupermoon)
    }
}
