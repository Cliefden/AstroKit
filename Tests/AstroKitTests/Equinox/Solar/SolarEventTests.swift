import XCTest
@testable import AstroKit

/// Tests for SolarCalculator equinox and solstice calculations
/// Reference data: USNO Astronomical Applications Department
final class SolarEventTests: XCTestCase {

    // MARK: - Spring Equinox Tests

    func test_solarEvent_springEquinox2024_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.springEquinox, year: 2024)
        assertDatesEqual(calculated, ReferenceSolarEvents.springEquinox2024, toleranceMinutes: 15)
    }

    func test_solarEvent_springEquinox2025_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.springEquinox, year: 2025)
        assertDatesEqual(calculated, ReferenceSolarEvents.springEquinox2025, toleranceMinutes: 15)
    }

    // MARK: - Summer Solstice Tests

    func test_solarEvent_summerSolstice2024_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.summerSolstice, year: 2024)
        assertDatesEqual(calculated, ReferenceSolarEvents.summerSolstice2024, toleranceMinutes: 15)
    }

    func test_solarEvent_summerSolstice2025_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.summerSolstice, year: 2025)
        assertDatesEqual(calculated, ReferenceSolarEvents.summerSolstice2025, toleranceMinutes: 15)
    }

    // MARK: - Autumn Equinox Tests

    func test_solarEvent_autumnEquinox2024_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.autumnEquinox, year: 2024)
        assertDatesEqual(calculated, ReferenceSolarEvents.autumnEquinox2024, toleranceMinutes: 15)
    }

    func test_solarEvent_autumnEquinox2025_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.autumnEquinox, year: 2025)
        assertDatesEqual(calculated, ReferenceSolarEvents.autumnEquinox2025, toleranceMinutes: 15)
    }

    // MARK: - Winter Solstice Tests

    func test_solarEvent_winterSolstice2024_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.winterSolstice, year: 2024)
        assertDatesEqual(calculated, ReferenceSolarEvents.winterSolstice2024, toleranceMinutes: 15)
    }

    func test_solarEvent_winterSolstice2025_withinReasonableTolerance() {
        let calculated = SolarCalculator.solarEvent(.winterSolstice, year: 2025)
        assertDatesEqual(calculated, ReferenceSolarEvents.winterSolstice2025, toleranceMinutes: 15)
    }

    // MARK: - allEvents Tests

    func test_allEvents_returnsFourEventsInChronologicalOrder() {
        let events = SolarCalculator.allEvents(year: 2025)

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0].type, .springEquinox)
        XCTAssertEqual(events[1].type, .summerSolstice)
        XCTAssertEqual(events[2].type, .autumnEquinox)
        XCTAssertEqual(events[3].type, .winterSolstice)

        // Verify chronological order
        for i in 0..<(events.count - 1) {
            XCTAssertLessThan(events[i].date, events[i + 1].date)
        }
    }

    func test_allEvents_cacheReturnsSameResults() {
        let firstCall = SolarCalculator.allEvents(year: 2026)
        let secondCall = SolarCalculator.allEvents(year: 2026)

        XCTAssertEqual(firstCall.count, secondCall.count)
        for i in 0..<firstCall.count {
            XCTAssertEqual(firstCall[i].type, secondCall[i].type)
            XCTAssertEqual(firstCall[i].date, secondCall[i].date)
        }
    }

    // MARK: - Edge Case Tests

    func test_solarEvent_leapYear2024_calculatesCorrectly() {
        // 2024 is a leap year - ensure calculations still work
        let events = SolarCalculator.allEvents(year: 2024)
        XCTAssertEqual(events.count, 4)

        // Spring equinox should be in March
        let springMonth = Calendar.current.component(.month, from: events[0].date)
        XCTAssertEqual(springMonth, 3)
    }

    func test_solarEvent_year2000_handlesReferenceYear() {
        // Year 2000 is the reference year for Jean Meeus algorithm
        let events = SolarCalculator.allEvents(year: 2000)
        XCTAssertEqual(events.count, 4)

        // Verify reasonable dates
        let springMonth = Calendar.current.component(.month, from: events[0].date)
        XCTAssertEqual(springMonth, 3)
    }

    func test_solarEvent_year2050_handlesFutureYear() {
        let events = SolarCalculator.allEvents(year: 2050)
        XCTAssertEqual(events.count, 4)

        // Events should still be in expected months
        let months = events.map { Calendar.current.component(.month, from: $0.date) }
        XCTAssertEqual(months[0], 3)  // Spring
        XCTAssertEqual(months[1], 6)  // Summer
        XCTAssertEqual(months[2], 9)  // Autumn
        XCTAssertEqual(months[3], 12) // Winter
    }

    // MARK: - SolarEventType Tests

    func test_solarEventType_isEquinox_returnsCorrectly() {
        XCTAssertTrue(SolarCalculator.SolarEventType.springEquinox.isEquinox)
        XCTAssertTrue(SolarCalculator.SolarEventType.autumnEquinox.isEquinox)
        XCTAssertFalse(SolarCalculator.SolarEventType.summerSolstice.isEquinox)
        XCTAssertFalse(SolarCalculator.SolarEventType.winterSolstice.isEquinox)
    }

    func test_solarEventType_isSolstice_returnsCorrectly() {
        XCTAssertTrue(SolarCalculator.SolarEventType.summerSolstice.isSolstice)
        XCTAssertTrue(SolarCalculator.SolarEventType.winterSolstice.isSolstice)
        XCTAssertFalse(SolarCalculator.SolarEventType.springEquinox.isSolstice)
        XCTAssertFalse(SolarCalculator.SolarEventType.autumnEquinox.isSolstice)
    }
}
