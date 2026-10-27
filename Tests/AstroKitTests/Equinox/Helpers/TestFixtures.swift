import Foundation
import XCTest
@testable import AstroKit

// MARK: - Test Locations

enum TestLocations {
    // Standard mid-latitude locations
    static let stockholm = (lat: 59.3293, lon: 18.0686, tz: "Europe/Stockholm")
    static let newYork = (lat: 40.7128, lon: -74.0060, tz: "America/New_York")
    static let sydney = (lat: -33.8688, lon: 151.2093, tz: "Australia/Sydney")
    static let tokyo = (lat: 35.6762, lon: 139.6503, tz: "Asia/Tokyo")

    // Edge cases
    static let equator = (lat: 0.0, lon: 0.0, tz: "UTC")
    static let northPole = (lat: 90.0, lon: 0.0, tz: "UTC")
    static let southPole = (lat: -90.0, lon: 0.0, tz: "UTC")

    // Arctic/Antarctic for polar day/night tests
    static let tromso = (lat: 69.6496, lon: 18.9560, tz: "Europe/Oslo")  // Inside Arctic Circle
    static let svalbard = (lat: 78.2232, lon: 15.6267, tz: "Arctic/Longyearbyen")
    static let mcmurdo = (lat: -77.8419, lon: 166.6863, tz: "Antarctica/McMurdo")
}

// MARK: - Date Creation Helpers

enum TestDates {
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Create a date in UTC
    static func utc(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: components)!
    }

    /// Create a date in a specific timezone
    static func local(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, timezone: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: timezone)
        return cal.date(from: components)!
    }
}

// MARK: - Date Comparison Extensions

extension Date {
    /// Initialize from ISO8601 string
    init(_ isoString: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self = formatter.date(from: isoString)!
    }

    /// Get hour and minute in UTC for comparison
    func utcComponents() -> (hour: Int, minute: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = cal.dateComponents([.hour, .minute], from: self)
        return (components.hour ?? 0, components.minute ?? 0)
    }

    /// Get hour and minute in a specific timezone
    func localComponents(timezone: String) -> (hour: Int, minute: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone)!
        let components = cal.dateComponents([.hour, .minute], from: self)
        return (components.hour ?? 0, components.minute ?? 0)
    }
}

// MARK: - XCTestCase Extensions

extension XCTestCase {
    /// Assert two dates are equal within a tolerance (in minutes)
    func assertDatesEqual(
        _ date1: Date,
        _ date2: Date,
        toleranceMinutes: Double = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let diff = abs(date1.timeIntervalSince(date2))
        let toleranceSeconds = toleranceMinutes * 60
        XCTAssertLessThanOrEqual(
            diff,
            toleranceSeconds,
            "Dates differ by \(diff / 60) minutes (tolerance: \(toleranceMinutes) min)",
            file: file,
            line: line
        )
    }

    /// Assert a value is within a percentage tolerance of expected
    func assertApproximatelyEqual(
        _ actual: Double,
        _ expected: Double,
        tolerancePercent: Double = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance = abs(expected) * (tolerancePercent / 100)
        XCTAssertEqual(actual, expected, accuracy: tolerance, file: file, line: line)
    }

    /// Assert a time matches expected hour:minute within tolerance
    func assertTimeEquals(
        _ date: Date,
        hour: Int,
        minute: Int,
        timezone: String,
        toleranceMinutes: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = date.localComponents(timezone: timezone)
        let actualMinutes = components.hour * 60 + components.minute
        let expectedMinutes = hour * 60 + minute
        let diff = abs(actualMinutes - expectedMinutes)

        XCTAssertLessThanOrEqual(
            diff,
            toleranceMinutes,
            "Time \(components.hour):\(String(format: "%02d", components.minute)) differs from expected \(hour):\(String(format: "%02d", minute)) by \(diff) minutes",
            file: file,
            line: line
        )
    }
}

// MARK: - Reference Data (USNO/NASA)

/// Known solar events from USNO Astronomical Applications
enum ReferenceSolarEvents {
    static let springEquinox2024 = TestDates.utc(year: 2024, month: 3, day: 20, hour: 3, minute: 6)
    static let summerSolstice2024 = TestDates.utc(year: 2024, month: 6, day: 20, hour: 20, minute: 51)
    static let autumnEquinox2024 = TestDates.utc(year: 2024, month: 9, day: 22, hour: 12, minute: 44)
    static let winterSolstice2024 = TestDates.utc(year: 2024, month: 12, day: 21, hour: 9, minute: 20)

    static let springEquinox2025 = TestDates.utc(year: 2025, month: 3, day: 20, hour: 9, minute: 1)
    static let summerSolstice2025 = TestDates.utc(year: 2025, month: 6, day: 21, hour: 2, minute: 42)
    static let autumnEquinox2025 = TestDates.utc(year: 2025, month: 9, day: 22, hour: 18, minute: 19)
    static let winterSolstice2025 = TestDates.utc(year: 2025, month: 12, day: 21, hour: 15, minute: 3)
}

/// Known moon phases from NASA/timeanddate.com
enum ReferenceMoonPhases {
    // 2025 full moons (UTC times approximate)
    static let fullMoonJan2025 = TestDates.utc(year: 2025, month: 1, day: 13, hour: 22, minute: 27)
    static let fullMoonFeb2025 = TestDates.utc(year: 2025, month: 2, day: 12, hour: 13, minute: 53)

    // 2025 new moons
    static let newMoonJan2025 = TestDates.utc(year: 2025, month: 1, day: 29, hour: 12, minute: 36)
    static let newMoonFeb2025 = TestDates.utc(year: 2025, month: 2, day: 28, hour: 0, minute: 45)
}
