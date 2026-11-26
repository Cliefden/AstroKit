import Foundation
import Testing
@testable import AstroKit

// Tests for the API AstroKit adds on top of Equinox's calculators, ported from
// Lunker's (SolarCalculatorTests, MoonCalculatorTests, SolunarCalculatorTests)
// and Otta's (SolarCalculatorTests, LunarCalculatorTests) suites. Since 0.2 the
// numbers are Lunker's; the full Lunker port is in LunkerPortTests.swift. See
// README "0.2 behaviour vs 0.1".

private let stockholm = (lat: 59.3293, lon: 18.0686)
private let stockholmTZ = TimeZone(identifier: "Europe/Stockholm")!
private let tromso = (lat: 69.6492, lon: 18.9553)
private let osloTZ = TimeZone(identifier: "Europe/Oslo")!

private func gregorian(_ tz: TimeZone) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal
}

private func local(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, in tz: TimeZone = stockholmTZ) -> Date {
    gregorian(tz).date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
}

// MARK: - SolarCalculator additions

@Suite("SolarCalculator — polar state (Lunker)")
struct PolarStateTests {
    @Test func tromsoDecemberIsPolarNight() {
        let date = local(2025, 12, 15, in: osloTZ)
        #expect(SolarCalculator.polarState(date: date, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ) == .polarNight)
        #expect(SolarCalculator.sunTimes(date: date, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ) == nil)
    }

    @Test func tromsoJuneIsPolarDay() {
        let date = local(2025, 6, 21, in: osloTZ)
        #expect(SolarCalculator.polarState(date: date, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ) == .polarDay)
    }

    @Test func nilWhenSunRisesAndSets() {
        #expect(SolarCalculator.polarState(date: local(2025, 3, 21), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ) == nil)
    }

    /// polarState must be non-nil exactly when sunTimes is nil, and agree with
    /// Equinox's polarCondition on which kind of polar day it is.
    @Test func agreesWithSunTimesAndPolarConditionAllYear() {
        let cal = gregorian(osloTZ)
        var day = local(2025, 1, 1, in: osloTZ)
        for _ in 0..<365 {
            let state = SolarCalculator.polarState(date: day, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ)
            let times = SolarCalculator.sunTimes(date: day, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ)
            let condition = SolarCalculator.polarCondition(date: day, latitude: tromso.lat, longitude: tromso.lon, timeZone: osloTZ)
            #expect((state == nil) == (times != nil), "mismatch on \(day)")
            switch (state, condition) {
            case (nil, nil), (.polarDay?, .midnightSun?), (.polarNight?, .polarNight?): break
            default: Issue.record("polarState \(String(describing: state)) vs polarCondition \(String(describing: condition)) on \(day)")
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
    }
}

@Suite("SolarCalculator — eventTimeClampingPolar (Otta)")
struct ClampingPolarTests {
    @Test func equalsRegularEventTimesAtMidLatitudes() throws {
        let date = local(2025, 4, 10)
        let times = try #require(SolarCalculator.sunTimes(date: date, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let rise = SolarCalculator.eventTimeClampingPolar(date: date, latitude: stockholm.lat, longitude: stockholm.lon, zenith: 90.833, isSunrise: true, timeZone: stockholmTZ)
        let set = SolarCalculator.eventTimeClampingPolar(date: date, latitude: stockholm.lat, longitude: stockholm.lon, zenith: 90.833, isSunrise: false, timeZone: stockholmTZ)
        #expect(abs(rise.timeIntervalSince(times.sunrise)) < 1)
        #expect(abs(set.timeIntervalSince(times.sunset)) < 1)

        let twilight = try #require(SolarCalculator.twilightTimes(date: date, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let civilDawn = SolarCalculator.eventTimeClampingPolar(date: date, latitude: stockholm.lat, longitude: stockholm.lon, zenith: 96, isSunrise: true, timeZone: stockholmTZ)
        #expect(abs(civilDawn.timeIntervalSince(try #require(twilight.civilDawn))) < 1)
        #expect(SolarCalculator.eventTime(date: date, latitude: stockholm.lat, longitude: stockholm.lon, zenith: 96, isSunrise: true, timeZone: stockholmTZ) == twilight.civilDawn)
    }

    /// Polar night: sunrise = sunset = solar noon (the window collapses to noon).
    @Test func polarNightCollapsesToSolarNoon() {
        let date = local(2025, 12, 15, in: osloTZ)
        let rise = SolarCalculator.eventTimeClampingPolar(date: date, latitude: tromso.lat, longitude: tromso.lon, zenith: 90.833, isSunrise: true, timeZone: osloTZ)
        let set = SolarCalculator.eventTimeClampingPolar(date: date, latitude: tromso.lat, longitude: tromso.lon, zenith: 90.833, isSunrise: false, timeZone: osloTZ)
        #expect(abs(set.timeIntervalSince(rise)) < 1)
        let hour = gregorian(osloTZ).component(.hour, from: rise)
        #expect((11...12).contains(hour), "collapsed event should sit at local solar noon, got \(hour)h")
        // Civil twilight still happens at Tromsø in mid-December → a real window.
        let civilDawn = SolarCalculator.eventTimeClampingPolar(date: date, latitude: tromso.lat, longitude: tromso.lon, zenith: 96, isSunrise: true, timeZone: osloTZ)
        let civilDusk = SolarCalculator.eventTimeClampingPolar(date: date, latitude: tromso.lat, longitude: tromso.lon, zenith: 96, isSunrise: false, timeZone: osloTZ)
        #expect(civilDusk.timeIntervalSince(civilDawn) > 3600)
    }

    /// Polar day: sunrise = noon − 12 h, sunset = noon + 12 h → a 24 h window.
    @Test func polarDaySpansWholeDay() {
        let date = local(2025, 6, 21, in: osloTZ)
        let rise = SolarCalculator.eventTimeClampingPolar(date: date, latitude: tromso.lat, longitude: tromso.lon, zenith: 90.833, isSunrise: true, timeZone: osloTZ)
        let set = SolarCalculator.eventTimeClampingPolar(date: date, latitude: tromso.lat, longitude: tromso.lon, zenith: 90.833, isSunrise: false, timeZone: osloTZ)
        #expect(abs(set.timeIntervalSince(rise) - 24 * 3600) < 1)
    }
}

@Suite("SolarCalculator — misc (Lunker/Otta)")
struct SolarMiscTests {
    @Test func solsticeMirrorDateIsSymmetric() {
        let date = local(2025, 5, 1)
        let mirror = SolarCalculator.solsticeMirrorDate(for: date)
        let solstice = SolarCalculator.nextSolstice(after: date).date
        #expect(abs(solstice.timeIntervalSince(date) - mirror.timeIntervalSince(solstice)) < 1)
        #expect(mirror > solstice)
    }

    @Test func allEventsAreCachedAndStable() {
        let first = SolarCalculator.allEvents(year: 2031)
        let second = SolarCalculator.allEvents(year: 2031)
        #expect(first == second)
        #expect(first.map(\.type) == SolarCalculator.SolarEventType.allCases)
    }

    @Test func subsolarPointLatitudeIsDeclination() {
        // Near the June solstice the subsolar latitude is ≈ +23.44°.
        let p = SolarCalculator.subsolarPoint(date: local(2025, 6, 21, hour: 12, in: TimeZone(identifier: "UTC")!))
        #expect(abs(p.latitude - 23.44) < 0.1)
        #expect((-180...180).contains(p.longitude))
    }

    /// Otta: clocks go back 03:00 CEST → 02:00 CET on 2026-10-25.
    /// NOAA: sunrise ~06:49, sunset ~16:14 local (CET).
    @Test func sunTimesOnAutumnDSTChangeDayMatchNOAA() throws {
        let cal = gregorian(stockholmTZ)
        let times = try #require(SolarCalculator.sunTimes(date: local(2026, 10, 25), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let rise = cal.dateComponents([.hour, .minute], from: times.sunrise)
        let set = cal.dateComponents([.hour, .minute], from: times.sunset)
        #expect(abs(Double(rise.hour! * 60 + rise.minute!) - (6 * 60 + 49)) <= 5)
        #expect(abs(Double(set.hour! * 60 + set.minute!) - (16 * 60 + 14)) <= 5)
    }

    /// Otta: a DST change must not shift sun events by an hour.
    @Test(arguments: [(2026, 3, 29), (2026, 10, 25)])
    func dstChangeDaysStayContinuous(_ ymd: (Int, Int, Int)) throws {
        let (y, m, d) = ymd
        let before = local(y, m, d - 1), change = local(y, m, d)
        let prev = try #require(SolarCalculator.sunTimes(date: before, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let curr = try #require(SolarCalculator.sunTimes(date: change, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let prevDawn = try #require(SolarCalculator.twilightTimes(date: before, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)?.civilDawn)
        let currDawn = try #require(SolarCalculator.twilightTimes(date: change, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)?.civilDawn)
        #expect(abs(curr.sunrise.timeIntervalSince(prev.sunrise) - 86_400) <= 300)
        #expect(abs(curr.sunset.timeIntervalSince(prev.sunset) - 86_400) <= 300)
        #expect(abs(currDawn.timeIntervalSince(prevDawn) - 86_400) <= 300)
    }

    @Test func uvIndexZeroBelowHorizonAndIncreasing() {
        #expect(SolarCalculator.estimateUVIndex(elevation: -5) == 0)
        #expect(SolarCalculator.estimateUVIndex(elevation: 30) < SolarCalculator.estimateUVIndex(elevation: 60))
    }
}

// MARK: - MoonCalculator additions

@Suite("MoonCalculator — phase angle (Otta)")
struct PhaseAngleTests {
    @Test func illuminatedFractionIsFunctionOfPhaseAngle() {
        var t = local(2026, 1, 1, hour: 0)
        for _ in 0..<120 {
            let p = MoonCalculator.moonPhase(for: t)
            #expect(p.phaseAngle >= 0 && p.phaseAngle < 360)
            #expect(p.illuminatedFraction == p.illumination)
            #expect(abs(p.illuminatedFraction - (1 - cos(p.phaseAngle * .pi / 180)) / 2) < 1e-9)
            #expect(p.illuminatedFraction >= 0 && p.illuminatedFraction <= 1)
            t = t.addingTimeInterval(6 * 3600)
        }
    }

    @Test func fullMoonIsOppositeSunAndNewMoonAligned() {
        var best = MoonCalculator.moonPhase(for: local(2026, 1, 1, hour: 0))
        var worst = best
        var t = local(2026, 1, 1, hour: 0)
        for _ in 0..<(45 * 8) {
            let p = MoonCalculator.moonPhase(for: t)
            if p.illumination > best.illumination { best = p }
            if p.illumination < worst.illumination { worst = p }
            t = t.addingTimeInterval(3 * 3600)
        }
        #expect(abs(best.phaseAngle - 180) < 12)
        #expect(best.phase == .fullMoon)
        #expect(min(worst.phaseAngle, 360 - worst.phaseAngle) < 12)
        #expect(worst.phase == .newMoon)
    }
}

@Suite("MoonCalculator — position and transits (Otta)")
struct TransitTests {
    @Test func moonPositionMatchesLunarPositionAndIsInRange() {
        var t = local(2026, 6, 10, hour: 0)
        for _ in 0..<48 {
            let p = MoonCalculator.moonPosition(at: t, latitude: stockholm.lat, longitude: stockholm.lon)
            let full = MoonCalculator.lunarPosition(at: t, latitude: stockholm.lat, longitude: stockholm.lon)
            #expect(p.elevation == full.altitude)
            #expect(p.azimuth == full.azimuth)
            #expect(p.azimuth >= 0 && p.azimuth < 360)
            #expect(p.elevation >= -90 && p.elevation <= 90)
            t = t.addingTimeInterval(3600)
        }
    }

    @Test func upperTransitIsHighestPoint() throws {
        let transits = MoonCalculator.transits(date: local(2026, 5, 20), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
        let upper = try #require(transits.upper)
        let atTransit = MoonCalculator.moonPosition(at: upper, latitude: stockholm.lat, longitude: stockholm.lon).elevation
        for hours in [-3.0, -1.5, 1.5, 3.0] {
            let other = MoonCalculator.moonPosition(at: upper.addingTimeInterval(hours * 3600), latitude: stockholm.lat, longitude: stockholm.lon).elevation
            #expect(atTransit > other, "altitude should peak at upper transit (offset \(hours)h)")
        }
    }

    @Test func lowerTransitIsLowerThanUpper() throws {
        let transits = MoonCalculator.transits(date: local(2026, 5, 20), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
        let upper = try #require(transits.upper)
        let lower = try #require(transits.lower)
        let upperAlt = MoonCalculator.moonPosition(at: upper, latitude: stockholm.lat, longitude: stockholm.lon).elevation
        let lowerAlt = MoonCalculator.moonPosition(at: lower, latitude: stockholm.lat, longitude: stockholm.lon).elevation
        #expect(upperAlt > lowerAlt)
    }

    /// A full moon is opposite the sun, so it culminates near local midnight.
    @Test func fullMoonCulminatesNearMidnight() throws {
        var bestDate = local(2026, 1, 1, hour: 0)
        var bestK = 0.0
        var t = bestDate
        for _ in 0..<(45 * 8) {
            let k = MoonCalculator.moonPhase(for: t).illumination
            if k > bestK { bestK = k; bestDate = t }
            t = t.addingTimeInterval(3 * 3600)
        }
        let upper = try #require(MoonCalculator.transits(date: bestDate, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ).upper)
        let cal = gregorian(stockholmTZ)
        let hour = Double(cal.component(.hour, from: upper)) + Double(cal.component(.minute, from: upper)) / 60
        #expect(min(hour, 24 - hour) < 4, "full moon should culminate near midnight, got \(hour)h")
    }

    @Test func moonTimesFindsBothEventsOnTypicalDays() {
        var daysWithBoth = 0
        for offset in 0..<7 {
            let day = local(2026, 4, 1).addingTimeInterval(Double(offset) * 86400)
            let t = MoonCalculator.moonTimes(date: day, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
            if t.moonrise != nil, t.moonset != nil { daysWithBoth += 1 }
        }
        #expect(daysWithBoth > 2)
    }
}

@Suite("MoonCalculator — eclipses (Lunker)")
struct EclipseAdditionsTests {
    @Test func calendarVariantKeepsTodaysEclipseAllDay() throws {
        let utc = TimeZone(identifier: "UTC")!
        let cal = gregorian(utc)
        // Late on the day of the 2026-08-12 total solar eclipse.
        let lateThatDay = local(2026, 8, 12, hour: 23, minute: 30, in: utc)
        let listed = MoonCalculator.upcomingEclipses(after: lateThatDay, limit: 1, calendar: cal)
        let first = try #require(listed.first)
        #expect(first.type == .solarTotal)
        #expect(cal.isDate(first.date, inSameDayAs: lateThatDay) || first.date > lateThatDay)
    }

    @Test func identifiersAreUniqueAndStable() {
        let all = MoonCalculator.upcomingEclipses(after: local(2024, 1, 1), limit: 100)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.map(\.id) == MoonCalculator.upcomingEclipses(after: local(2024, 1, 1), limit: 100).map(\.id))
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test func tableCoversThrough2035() throws {
        let end = try #require(MoonCalculator.eclipseTableCoverageEnd)
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: end)
        #expect(comps.year == 2035)
        #expect(comps.month == 9)
    }
}

// MARK: - Solunar

@Suite("Solunar (Lunker periods)")
struct SolunarTests {
    private let cal = gregorian(stockholmTZ)
    private let referenceNow = Date(timeIntervalSince1970: 1_782_864_000) // 2026-07-01 00:00 UTC

    @Test func periodDurations() {
        let major = Solunar.Period(kind: .majorOverhead, center: referenceNow)
        let minor = Solunar.Period(kind: .minorMoonrise, center: referenceNow)
        #expect(major.end.timeIntervalSince(major.start) == 120 * 60)
        #expect(minor.end.timeIntervalSince(minor.start) == 60 * 60)
    }

    @Test func periodContainsCenter() {
        let p = Solunar.Period(kind: .majorOverhead, center: referenceNow)
        #expect(p.contains(referenceNow))
        #expect(p.contains(referenceNow.addingTimeInterval(-30 * 60)))
        #expect(p.contains(referenceNow.addingTimeInterval(30 * 60)))
        #expect(!p.contains(referenceNow.addingTimeInterval(-90 * 60)))
        #expect(!p.contains(referenceNow.addingTimeInterval(90 * 60)))
    }

    @Test func nextPeriodChoosesEarliestStart() throws {
        let minor = Solunar.Period(kind: .minorMoonrise, center: referenceNow.addingTimeInterval(9 * 3600 + 40 * 60))
        let major = Solunar.Period(kind: .majorOverhead, center: referenceNow.addingTimeInterval(10 * 3600))
        #expect(major.start < minor.start)
        let day = Solunar.Day(date: referenceNow, periods: [minor, major], moonrise: minor.center, moonset: nil)
        #expect(try #require(day.nextPeriod(after: referenceNow.addingTimeInterval(8 * 3600))).kind == .majorOverhead)
        #expect(try #require(day.nextPeriod(after: referenceNow.addingTimeInterval(9 * 3600 + 5 * 60))).kind == .minorMoonrise)
        #expect(day.nextPeriod(after: referenceNow.addingTimeInterval(11 * 3600)) == nil)
        // 10:30 is inside the major (09:00–11:00) but past the minor (09:10–10:10).
        #expect(day.activePeriod(at: referenceNow.addingTimeInterval(10.5 * 3600))?.kind == .majorOverhead)
    }

    @Test func stockholmDayHasTwoToFourChronologicalInDayPeriods() throws {
        let day = Solunar.day(for: local(2026, 5, 10), latitude: stockholm.lat, longitude: stockholm.lon, calendar: cal)
        #expect((2...4).contains(day.periods.count))
        #expect(zip(day.periods, day.periods.dropFirst()).allSatisfy { $0.center <= $1.center })
        let dayEnd = try #require(cal.date(byAdding: .day, value: 1, to: day.date))
        for period in day.periods {
            #expect(period.center >= day.date && period.center < dayEnd)
        }
        #expect(day.majorPeriods.count + day.minorPeriods.count == day.periods.count)
    }

    @Test func independentOfInputTimeOfDay() {
        let early = Solunar.day(for: local(2026, 4, 14, hour: 0, minute: 30), latitude: 57.7089, longitude: 11.9746, calendar: cal)
        let late = Solunar.day(for: local(2026, 4, 14, hour: 23, minute: 30), latitude: 57.7089, longitude: 11.9746, calendar: cal)
        #expect(early == late)
        #expect(early.date == cal.startOfDay(for: local(2026, 4, 14)))
    }

    /// Regression (Lunker): a transit within minutes of a day edge was dropped
    /// by both days. Whatever day each transit falls on, it is listed once.
    @Test func majorPeriodsHaveNoGapsOrDuplicatesAcrossDays() throws {
        var day = cal.startOfDay(for: local(2026, 3, 20))
        var overhead: [Date] = []
        var underfoot: [Date] = []
        for _ in 0..<60 {
            let d = Solunar.day(for: day, latitude: stockholm.lat, longitude: stockholm.lon, calendar: cal)
            overhead += d.periods.filter { $0.kind == .majorOverhead }.map(\.center)
            underfoot += d.periods.filter { $0.kind == .majorUnderfoot }.map(\.center)
            day = try #require(cal.date(byAdding: .day, value: 1, to: day))
        }
        for (name, centers) in [("transit", overhead), ("anti-transit", underfoot)] {
            let sorted = centers.sorted()
            #expect(sorted.count > 55, "\(name)")
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let gapHours = b.timeIntervalSince(a) / 3600
                #expect(gapHours > 23, "\(name) listed twice near \(a)")
                #expect(gapHours < 26, "\(name) missing between \(a) and \(b)")
            }
        }
    }

    @Test func closestSunMoonAlignment() {
        let now = referenceNow
        #expect(Solunar.closestSunMoonAlignment(sunrise: nil, sunset: nil, moonrise: now, moonset: nil) == nil)
        let delta = Solunar.closestSunMoonAlignment(
            sunrise: now, sunset: now.addingTimeInterval(12 * 3600),
            moonrise: now.addingTimeInterval(10 * 60), moonset: now.addingTimeInterval(13 * 3600))
        #expect(delta == TimeInterval(10 * 60))
    }

    @Test func nextStrongAlignmentIsWithinThreshold() throws {
        let start = local(2026, 6, 1)
        let found = try #require(Solunar.nextStrongAlignment(after: start, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ, withinMinutes: 30, maxDays: 60))
        #expect(found > start)
        let sun = try #require(SolarCalculator.sunTimes(date: found, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let moon = MoonCalculator.moonTimes(date: found, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
        let delta = try #require(Solunar.closestSunMoonAlignment(sunrise: sun.sunrise, sunset: sun.sunset, moonrise: moon.moonrise, moonset: moon.moonset))
        #expect(delta <= 30 * 60)
        #expect(Solunar.nextStrongAlignment(after: start, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ, maxDays: 0) == nil)
    }
}
