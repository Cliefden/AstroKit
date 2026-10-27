import XCTest
@testable import AstroKit

/// Tests for MoonCalculator eclipse predictions
/// Note: Uses pre-computed eclipse data for 2024-2030
final class EclipseTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func test_upcomingEclipses_returnsResults() {
        let date = TestDates.utc(year: 2025, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date)

        XCTAssertFalse(eclipses.isEmpty, "Should return upcoming eclipses")
    }

    func test_upcomingEclipses_defaultLimitIsFive() {
        let date = TestDates.utc(year: 2025, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date)

        XCTAssertLessThanOrEqual(eclipses.count, 5)
    }

    func test_upcomingEclipses_respectsLimit() {
        let date = TestDates.utc(year: 2025, month: 1, day: 1)

        let limit1 = MoonCalculator.upcomingEclipses(after: date, limit: 1)
        let limit3 = MoonCalculator.upcomingEclipses(after: date, limit: 3)
        let limit10 = MoonCalculator.upcomingEclipses(after: date, limit: 10)

        XCTAssertEqual(limit1.count, 1)
        XCTAssertEqual(limit3.count, 3)
        XCTAssertLessThanOrEqual(limit10.count, 10)
    }

    // MARK: - Date Filtering Tests

    func test_upcomingEclipses_onlyReturnsFutureEclipses() {
        let date = TestDates.utc(year: 2025, month: 6, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date)

        for eclipse in eclipses {
            XCTAssertGreaterThan(eclipse.date, date, "Eclipse should be after query date")
        }
    }

    func test_upcomingEclipses_chronologicalOrder() {
        let date = TestDates.utc(year: 2025, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date, limit: 10)

        for i in 0..<(eclipses.count - 1) {
            XCTAssertLessThan(eclipses[i].date, eclipses[i + 1].date,
                              "Eclipses should be in chronological order")
        }
    }

    func test_upcomingEclipses_after2035_returnsEmpty() {
        // Pre-computed data only goes to 2035
        let date = TestDates.utc(year: 2036, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date)

        XCTAssertTrue(eclipses.isEmpty, "No eclipses in database after 2035")
    }

    func test_upcomingEclipses_extendsThrough2035() {
        let date = TestDates.utc(year: 2031, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date, limit: 50)
        let cal = Calendar(identifier: .gregorian)
        let years = Set(eclipses.map { cal.component(.year, from: $0.date) })
        XCTAssertEqual(years, [2031, 2032, 2033, 2034, 2035])
    }

    // MARK: - NASA reference eclipses (Five Millennium Canon)

    private func eclipse(on year: Int, _ month: Int, _ day: Int) -> MoonCalculator.EclipseEvent? {
        let start = TestDates.utc(year: year, month: month, day: day)
        return MoonCalculator.upcomingEclipses(after: start.addingTimeInterval(-86_400), limit: 1).first
    }

    func test_2028Dec31_isTotalLunar() {
        XCTAssertEqual(eclipse(on: 2028, 12, 31)?.type, .lunarTotal)
    }

    func test_2028Jan12_isPartialLunar() {
        XCTAssertEqual(eclipse(on: 2028, 1, 12)?.type, .lunarPartial)
    }

    func test_2031Nov14_isHybridSolar() {
        XCTAssertEqual(eclipse(on: 2031, 11, 14)?.type, .solarHybrid)
    }

    func test_2033Mar30_isTotalSolar() {
        XCTAssertEqual(eclipse(on: 2033, 3, 30)?.type, .solarTotal)
    }

    func test_2032To2033_lunarTetrad() {
        let tetrad = [(2032, 4, 25), (2032, 10, 18), (2033, 4, 14), (2033, 10, 8)]
        for (y, m, d) in tetrad {
            XCTAssertEqual(eclipse(on: y, m, d)?.type, .lunarTotal, "\(y)-\(m)-\(d) should be total lunar")
        }
    }

    func test_2035Sep2_isTotalSolar() {
        XCTAssertEqual(eclipse(on: 2035, 9, 2)?.type, .solarTotal)
    }

    // MARK: - Known Eclipse Tests

    func test_upcomingEclipses_firstLunarEclipse2025_march14() {
        let date = TestDates.utc(year: 2025, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date)

        XCTAssertGreaterThan(eclipses.count, 0)
        if let first = eclipses.first {
            XCTAssertEqual(first.type, .lunarTotal)

            let cal = Calendar.current
            let month = cal.component(.month, from: first.date)
            let day = cal.component(.day, from: first.date)

            XCTAssertEqual(month, 3, "First 2025 eclipse should be in March")
            XCTAssertEqual(day, 14, "First 2025 eclipse should be on the 14th")
        }
    }

    func test_upcomingEclipses_containsBothLunarAndSolar() {
        let date = TestDates.utc(year: 2025, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date, limit: 10)

        let hasLunar = eclipses.contains { $0.type.isLunar }
        let hasSolar = eclipses.contains { !$0.type.isLunar }

        XCTAssertTrue(hasLunar, "Should include lunar eclipses")
        XCTAssertTrue(hasSolar, "Should include solar eclipses")
    }

    // MARK: - Eclipse Type Tests

    func test_eclipseType_isLunar_correctForAllTypes() {
        XCTAssertTrue(MoonCalculator.EclipseEvent.EclipseType.lunarTotal.isLunar)
        XCTAssertTrue(MoonCalculator.EclipseEvent.EclipseType.lunarPartial.isLunar)
        XCTAssertTrue(MoonCalculator.EclipseEvent.EclipseType.lunarPenumbral.isLunar)

        XCTAssertFalse(MoonCalculator.EclipseEvent.EclipseType.solarTotal.isLunar)
        XCTAssertFalse(MoonCalculator.EclipseEvent.EclipseType.solarPartial.isLunar)
        XCTAssertFalse(MoonCalculator.EclipseEvent.EclipseType.solarAnnular.isLunar)
        XCTAssertFalse(MoonCalculator.EclipseEvent.EclipseType.solarHybrid.isLunar)
    }

    func test_eclipseType_allTypesHaveIcons() {
        let types: [MoonCalculator.EclipseEvent.EclipseType] = [
            .lunarTotal, .lunarPartial, .lunarPenumbral,
            .solarTotal, .solarPartial, .solarAnnular, .solarHybrid
        ]

        for type in types {
            XCTAssertFalse(type.icon.isEmpty)
            XCTAssertFalse(type.rawValue.isEmpty)
        }
    }

    // MARK: - Visibility Tests

    func test_upcomingEclipses_allHaveVisibility() {
        let date = TestDates.utc(year: 2025, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date, limit: 10)

        for eclipse in eclipses {
            XCTAssertFalse(eclipse.visibility.isEmpty, "Each eclipse should have visibility info")
        }
    }

    // MARK: - Boundary Tests

    func test_upcomingEclipses_before2025_includesAllKnown() {
        let date = TestDates.utc(year: 2024, month: 1, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date, limit: 20)

        // Should have many eclipses from 2025-2030
        XCTAssertGreaterThan(eclipses.count, 10)
    }

    func test_upcomingEclipses_mid2035_returnsFewResults() {
        let date = TestDates.utc(year: 2035, month: 6, day: 1)
        let eclipses = MoonCalculator.upcomingEclipses(after: date, limit: 10)

        // Only the last two eclipses of the table remain (Aug 19, Sep 2)
        XCTAssertEqual(eclipses.count, 2)
    }
}
