import XCTest
@testable import AstroKit

/// Tests for SolarCalculator event navigation methods (lastEvent, nextEvent, etc.)
final class EventNavigationTests: XCTestCase {

    // MARK: - lastEvent Tests

    func test_lastEvent_midJanuary_returnsWinterSolstice() {
        let date = TestDates.utc(year: 2025, month: 1, day: 15)
        let lastEvent = SolarCalculator.lastEvent(before: date)

        XCTAssertEqual(lastEvent.type, .winterSolstice)
        // Should be the December 2024 solstice
        let year = Calendar.current.component(.year, from: lastEvent.date)
        XCTAssertEqual(year, 2024)
    }

    func test_lastEvent_midApril_returnsSpringEquinox() {
        let date = TestDates.utc(year: 2025, month: 4, day: 15)
        let lastEvent = SolarCalculator.lastEvent(before: date)

        XCTAssertEqual(lastEvent.type, .springEquinox)
        let year = Calendar.current.component(.year, from: lastEvent.date)
        XCTAssertEqual(year, 2025)
    }

    func test_lastEvent_midJuly_returnsSummerSolstice() {
        let date = TestDates.utc(year: 2025, month: 7, day: 15)
        let lastEvent = SolarCalculator.lastEvent(before: date)

        XCTAssertEqual(lastEvent.type, .summerSolstice)
    }

    func test_lastEvent_midOctober_returnsAutumnEquinox() {
        let date = TestDates.utc(year: 2025, month: 10, day: 15)
        let lastEvent = SolarCalculator.lastEvent(before: date)

        XCTAssertEqual(lastEvent.type, .autumnEquinox)
    }

    // MARK: - nextEvent Tests

    func test_nextEvent_midJanuary_returnsSpringEquinox() {
        let date = TestDates.utc(year: 2025, month: 1, day: 15)
        let nextEvent = SolarCalculator.nextEvent(after: date)

        XCTAssertEqual(nextEvent.type, .springEquinox)
        let year = Calendar.current.component(.year, from: nextEvent.date)
        XCTAssertEqual(year, 2025)
    }

    func test_nextEvent_midApril_returnsSummerSolstice() {
        let date = TestDates.utc(year: 2025, month: 4, day: 15)
        let nextEvent = SolarCalculator.nextEvent(after: date)

        XCTAssertEqual(nextEvent.type, .summerSolstice)
    }

    func test_nextEvent_midOctober_returnsWinterSolstice() {
        let date = TestDates.utc(year: 2025, month: 10, day: 15)
        let nextEvent = SolarCalculator.nextEvent(after: date)

        XCTAssertEqual(nextEvent.type, .winterSolstice)
    }

    func test_nextEvent_midDecember_returnsWinterSolstice() {
        let date = TestDates.utc(year: 2025, month: 12, day: 15)
        let nextEvent = SolarCalculator.nextEvent(after: date)

        XCTAssertEqual(nextEvent.type, .winterSolstice)
        let year = Calendar.current.component(.year, from: nextEvent.date)
        XCTAssertEqual(year, 2025)
    }

    // MARK: - Filtered Event Tests

    func test_lastEquinox_afterSpringEquinox_returnsSpring() {
        let date = TestDates.utc(year: 2025, month: 5, day: 1)
        let lastEquinox = SolarCalculator.lastEquinox(before: date)

        XCTAssertEqual(lastEquinox.type, .springEquinox)
    }

    func test_lastEquinox_afterAutumnEquinox_returnsAutumn() {
        let date = TestDates.utc(year: 2025, month: 11, day: 1)
        let lastEquinox = SolarCalculator.lastEquinox(before: date)

        XCTAssertEqual(lastEquinox.type, .autumnEquinox)
    }

    func test_nextEquinox_beforeSpring_returnsSpring() {
        let date = TestDates.utc(year: 2025, month: 2, day: 1)
        let nextEquinox = SolarCalculator.nextEquinox(after: date)

        XCTAssertEqual(nextEquinox.type, .springEquinox)
    }

    func test_nextEquinox_afterSpringBeforeAutumn_returnsAutumn() {
        let date = TestDates.utc(year: 2025, month: 5, day: 1)
        let nextEquinox = SolarCalculator.nextEquinox(after: date)

        XCTAssertEqual(nextEquinox.type, .autumnEquinox)
    }

    func test_lastSolstice_afterSummer_returnsSummer() {
        let date = TestDates.utc(year: 2025, month: 8, day: 1)
        let lastSolstice = SolarCalculator.lastSolstice(before: date)

        XCTAssertEqual(lastSolstice.type, .summerSolstice)
    }

    func test_nextSolstice_beforeSummer_returnsSummer() {
        let date = TestDates.utc(year: 2025, month: 4, day: 1)
        let nextSolstice = SolarCalculator.nextSolstice(after: date)

        XCTAssertEqual(nextSolstice.type, .summerSolstice)
    }

    // MARK: - Year Boundary Tests

    func test_lastEvent_crossingYearBoundary_findsCorrectEvent() {
        // Early January should find previous year's winter solstice
        let date = TestDates.utc(year: 2026, month: 1, day: 5)
        let lastEvent = SolarCalculator.lastEvent(before: date)

        XCTAssertEqual(lastEvent.type, .winterSolstice)
        let year = Calendar.current.component(.year, from: lastEvent.date)
        XCTAssertEqual(year, 2025)
    }

    func test_nextEvent_crossingYearBoundary_findsCorrectEvent() {
        // Late December should find next year's spring equinox
        let date = TestDates.utc(year: 2025, month: 12, day: 25)
        let nextEvent = SolarCalculator.nextEvent(after: date)

        XCTAssertEqual(nextEvent.type, .springEquinox)
        let year = Calendar.current.component(.year, from: nextEvent.date)
        XCTAssertEqual(year, 2026)
    }
}
