import XCTest
@testable import AstroKit

/// Tests for MoonCalculator moon phase calculations
/// Reference data: NASA Moon Phase Calendar, timeanddate.com
final class MoonPhaseTests: XCTestCase {

    // MARK: - Known Full Moon Tests

    func test_moonPhase_knownFullMoonJan2025_returnsNearFullMoon() {
        // January 13, 2025 ~22:27 UTC is a full moon
        // Phase classification may be fullMoon or adjacent phases due to age calculation
        let date = ReferenceMoonPhases.fullMoonJan2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        let nearFullPhases: [MoonCalculator.MoonPhase] = [.waxingGibbous, .fullMoon, .waningGibbous]
        XCTAssertTrue(nearFullPhases.contains(phaseInfo.phase),
                      "Expected near-full phase, got \(phaseInfo.phase)")
        // Illumination should be high
        XCTAssertGreaterThan(phaseInfo.illumination, 0.95)
    }

    func test_moonPhase_knownFullMoonFeb2025_returnsNearFullMoon() {
        // February 12, 2025 is a full moon
        let date = ReferenceMoonPhases.fullMoonFeb2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        let nearFullPhases: [MoonCalculator.MoonPhase] = [.waxingGibbous, .fullMoon, .waningGibbous]
        XCTAssertTrue(nearFullPhases.contains(phaseInfo.phase),
                      "Expected near-full phase, got \(phaseInfo.phase)")
        // Illumination should be high
        XCTAssertGreaterThan(phaseInfo.illumination, 0.95)
    }

    // MARK: - Known New Moon Tests

    func test_moonPhase_knownNewMoonJan2025_returnsNewMoon() {
        // January 29, 2025 ~12:36 UTC is a new moon
        let date = ReferenceMoonPhases.newMoonJan2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        XCTAssertEqual(phaseInfo.phase, .newMoon)
    }

    func test_moonPhase_knownNewMoonFeb2025_returnsNewMoon() {
        // February 28, 2025 is a new moon
        let date = ReferenceMoonPhases.newMoonFeb2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        XCTAssertEqual(phaseInfo.phase, .newMoon)
    }

    // MARK: - Illumination Tests

    func test_moonPhase_fullMoon_illuminationNear100() {
        let date = ReferenceMoonPhases.fullMoonJan2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        // Illumination should be very close to 100%
        XCTAssertGreaterThan(phaseInfo.illumination, 0.98)
    }

    func test_moonPhase_newMoon_illuminationNear0() {
        let date = ReferenceMoonPhases.newMoonJan2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        // Illumination should be very close to 0%
        XCTAssertLessThan(phaseInfo.illumination, 0.02)
    }

    func test_moonPhase_midCycle_illuminationAround50() {
        // First quarter is approximately 7.4 days after new moon
        let newMoon = ReferenceMoonPhases.newMoonJan2025
        let firstQuarter = newMoon.addingTimeInterval(7.4 * 86400)

        let phaseInfo = MoonCalculator.moonPhase(for: firstQuarter)

        // Should be around 50% (within 10%)
        XCTAssertEqual(phaseInfo.illumination, 0.5, accuracy: 0.15)
    }

    // MARK: - Age Tests

    func test_moonPhase_newMoon_ageNearZero() {
        let date = ReferenceMoonPhases.newMoonJan2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        // Age should be near 0 or near synodic month (wrapping)
        let isNearZero = phaseInfo.age < 2
        let isNearEnd = phaseInfo.age > 27.5
        XCTAssertTrue(isNearZero || isNearEnd, "Age should be near cycle boundary")
    }

    func test_moonPhase_fullMoon_ageNear15Days() {
        let date = ReferenceMoonPhases.fullMoonJan2025
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        // Full moon is approximately halfway through the cycle
        let halfCycle = phaseInfo.synodicMonth / 2
        XCTAssertEqual(phaseInfo.age, halfCycle, accuracy: 2)
    }

    // MARK: - Synodic Month Tests

    func test_moonPhase_synodicMonth_isCorrectValue() {
        let date = TestDates.utc(year: 2025, month: 1, day: 15)
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        // Synodic month should be approximately 29.53 days
        XCTAssertEqual(phaseInfo.synodicMonth, 29.530588853, accuracy: 0.001)
    }

    // MARK: - Next Phase Prediction Tests

    func test_moonPhase_nextNewMoon_withinSynodicMonth() {
        let date = TestDates.utc(year: 2025, month: 1, day: 15)
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        let daysToNextNew = phaseInfo.nextNewMoon.timeIntervalSince(date) / 86400
        XCTAssertGreaterThan(daysToNextNew, 0)
        XCTAssertLessThanOrEqual(daysToNextNew, phaseInfo.synodicMonth)
    }

    func test_moonPhase_nextFullMoon_withinSynodicMonth() {
        let date = TestDates.utc(year: 2025, month: 1, day: 15)
        let phaseInfo = MoonCalculator.moonPhase(for: date)

        let daysToNextFull = phaseInfo.nextFullMoon.timeIntervalSince(date) / 86400
        XCTAssertGreaterThan(daysToNextFull, 0)
        XCTAssertLessThanOrEqual(daysToNextFull, phaseInfo.synodicMonth)
    }

    // MARK: - Phase Progression Tests

    func test_moonPhase_progressionOverMonth_coversAllPhases() {
        let startDate = ReferenceMoonPhases.newMoonJan2025
        var phasesEncountered: Set<MoonCalculator.MoonPhase> = []

        // Check every day for one synodic month
        for dayOffset in 0..<30 {
            let date = startDate.addingTimeInterval(Double(dayOffset) * 86400)
            let phaseInfo = MoonCalculator.moonPhase(for: date)
            phasesEncountered.insert(phaseInfo.phase)
        }

        // Should encounter all 8 phases
        XCTAssertEqual(phasesEncountered.count, 8, "Should see all 8 moon phases in a month")
    }

    func test_moonPhase_illuminationIncreasesDuringWaxing() {
        // From new moon to full moon, illumination should increase
        let newMoon = ReferenceMoonPhases.newMoonJan2025
        let day7 = newMoon.addingTimeInterval(7 * 86400)
        let day14 = newMoon.addingTimeInterval(14 * 86400)

        let phaseNew = MoonCalculator.moonPhase(for: newMoon)
        let phase7 = MoonCalculator.moonPhase(for: day7)
        let phase14 = MoonCalculator.moonPhase(for: day14)

        XCTAssertLessThan(phaseNew.illumination, phase7.illumination)
        XCTAssertLessThan(phase7.illumination, phase14.illumination)
    }

    // MARK: - All Phase Names Tests

    func test_moonPhase_allPhasesHaveDescriptions() {
        for phase in MoonCalculator.MoonPhase.allCases {
            XCTAssertFalse(phase.rawValue.isEmpty)
            XCTAssertFalse(phase.description.isEmpty)
            XCTAssertFalse(phase.icon.isEmpty)
        }
    }
}
