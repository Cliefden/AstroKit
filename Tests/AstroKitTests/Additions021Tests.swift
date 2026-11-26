import Foundation
import Testing
@testable import AstroKit

// 0.2.1 additions: upcoming sun events, distance reference constants,
// UV symbols and eclipse central-line paths.

private let stockholm = (lat: 59.3293, lon: 18.0686)
private let stockholmTZ = TimeZone(identifier: "Europe/Stockholm")!
private let tromso = (lat: 69.6492, lon: 18.9553)
private let osloTZ = TimeZone(identifier: "Europe/Oslo")!
private let utcTZ = TimeZone(identifier: "UTC")!

private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, in tz: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Upcoming sun events")
struct UpcomingSunEventsTests {
    @Test func alternatesAndStartsAfterTheGivenInstant() throws {
        let now = at(2026, 3, 10, hour: 12, in: stockholmTZ)
        let events = SolarCalculator.upcomingSunEvents(after: now, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
        #expect(events.first?.kind == .sunset)
        #expect(events.allSatisfy { $0.time > now })
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.time < $1.time && $0.kind != $1.kind })
        // Rest of today (sunset) + 3 more days of rise/set.
        #expect(events.count == 7)

        let today = try #require(SolarCalculator.sunTimes(date: now, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(events.first?.time == today.sunset)
    }

    @Test func nextEventMatchesSunTimes() throws {
        let morning = at(2026, 6, 1, hour: 2, in: stockholmTZ)
        let times = try #require(SolarCalculator.sunTimes(date: morning, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let next = try #require(SolarCalculator.nextSunEvent(after: morning, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(next == SolarCalculator.SunEvent(kind: .sunrise, time: times.sunrise))

        let evening = at(2026, 6, 1, hour: 23, minute: 30, in: stockholmTZ)
        let after = try #require(SolarCalculator.nextSunEvent(after: evening, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(after.kind == .sunrise)
        #expect(after.time > evening)
    }

    @Test func untilBoundsTheWindowInclusively() throws {
        let now = at(2026, 3, 10, hour: 12, in: stockholmTZ)
        let all = SolarCalculator.upcomingSunEvents(after: now, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ, days: 10)
        let cutoff = all[2].time
        let bounded = SolarCalculator.upcomingSunEvents(after: now, until: cutoff, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ, days: 10)
        #expect(bounded == Array(all.prefix(3)))
    }

    @Test func polarNightHasNoEventsWithinShortWindow() {
        let midwinter = at(2026, 12, 21, in: osloTZ)
        #expect(SolarCalculator.upcomingSunEvents(after: midwinter, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ).isEmpty)
        #expect(SolarCalculator.nextSunEvent(after: midwinter, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ) == nil)
    }

    @Test func longWindowFindsTheEndOfPolarNight() throws {
        // Tromsø's sun returns around 15 January.
        let midwinter = at(2026, 12, 21, in: osloTZ)
        let first = try #require(SolarCalculator.nextSunEvent(after: midwinter, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ, days: 40))
        #expect(first.kind == .sunrise)
        #expect(first.time > at(2027, 1, 10, in: osloTZ))
        #expect(first.time < at(2027, 1, 20, in: osloTZ))
    }

    @Test func dayCountIsPerLocalCalendarDay() {
        // Evening in UTC is already the next day in Tokyo: the window follows Tokyo's days.
        let tokyo = (lat: 35.6762, lon: 139.6503)
        let tokyoTZ = TimeZone(identifier: "Asia/Tokyo")!
        let now = at(2026, 3, 10, hour: 20, in: utcTZ)   // 05:00 on the 11th in Tokyo, before sunrise
        let events = SolarCalculator.upcomingSunEvents(after: now, latitude: tokyo.lat, longitude: tokyo.lon, timeZone: tokyoTZ, days: 0)
        #expect(events.map(\.kind) == [.sunrise, .sunset])
    }
}

@Suite("Lunar distance reference constants")
struct DistanceConstantTests {
    @Test func valuesMatchTheStatusBands() {
        #expect(MoonCalculator.averageDistance == 384_400)
        #expect(MoonCalculator.perigeeDistance == 356_500)
        #expect(MoonCalculator.apogeeDistance == 406_700)
        #expect(MoonCalculator.perigeeDistance < MoonCalculator.averageDistance)
        #expect(MoonCalculator.averageDistance < MoonCalculator.apogeeDistance)
    }

    @Test func percentOfAverageUsesThePublicAverage() {
        let info = MoonCalculator.lunarDistance(for: at(2026, 5, 1, in: utcTZ))
        #expect(abs(info.percentOfAverage - info.distanceKm / MoonCalculator.averageDistance * 100) < 1e-9)
    }
}

@Suite("UV level symbols")
struct UVSymbolTests {
    @Test func everyLevelHasASymbol() {
        #expect(SolarCalculator.UVLevel.low.symbolName == "sun.min.fill")
        #expect(SolarCalculator.UVLevel.moderate.symbolName == "sun.max.fill")
        #expect(SolarCalculator.UVLevel.high.symbolName == "sun.max.fill")
        #expect(SolarCalculator.UVLevel.veryHigh.symbolName == "sun.max.trianglebadge.exclamationmark.fill")
        #expect(SolarCalculator.UVLevel.extreme.symbolName == "sun.max.trianglebadge.exclamationmark.fill")
    }
}

@Suite("Eclipse central-line paths")
struct EclipsePathTests {
    @Test func everyPathMatchesACentralEclipseInTheTable() throws {
        let central: Set<MoonCalculator.EclipseEvent.EclipseType> = [.solarTotal, .solarAnnular, .solarHybrid]
        let table = MoonCalculator.upcomingEclipses(after: .distantPast, limit: 1000)
        for path in MoonCalculator.EclipsePath.all {
            #expect(central.contains(path.type))
            #expect(path.centralLine.count >= 2)
            let event = try #require(table.first { MoonCalculator.eclipsePath(for: $0) == path }, "no table entry for \(path.id)")
            #expect(event.type == path.type)
        }
    }

    @Test func pathsAreInDateOrderWithValidCoordinates() {
        let ids = MoonCalculator.EclipsePath.all.map(\.id)
        #expect(ids == ids.sorted())
        #expect(ids.first == "2026-08-12")
        for point in MoonCalculator.EclipsePath.all.flatMap(\.centralLine) {
            #expect((-90...90).contains(point.latitude))
            #expect((-180...180).contains(point.longitude))
        }
    }

    @Test func spain2026IsTotalAndEndsInSpain() throws {
        let path = try #require(MoonCalculator.eclipsePath(onUTCDayOf: at(2026, 8, 12, hour: 17, in: utcTZ)))
        #expect(path.type == .solarTotal)
        let end = try #require(path.centralLine.last)
        #expect((36...44).contains(end.latitude))
        #expect((-10...5).contains(end.longitude))
    }

    @Test func lunarAndPartialEclipsesHaveNoPath() {
        for event in MoonCalculator.upcomingEclipses(after: .distantPast, limit: 1000)
        where event.type.isLunar || event.type == .solarPartial {
            #expect(MoonCalculator.eclipsePath(for: event) == nil)
        }
    }

    @Test func coverageSpansTheTable() throws {
        let coverage = try #require(MoonCalculator.eclipsePathCoverage)
        #expect(coverage.lowerBound == at(2026, 8, 12, hour: 0, in: utcTZ))
        #expect(coverage.upperBound == at(2030, 11, 25, hour: 0, in: utcTZ))
    }
}
