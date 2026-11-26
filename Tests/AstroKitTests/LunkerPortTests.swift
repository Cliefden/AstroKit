import Foundation
import Testing
@testable import AstroKit

// The astronomy assertions of Lunker's LunkerTests/{SolarCalculator,
// MoonCalculator,SolunarCalculator}Tests.swift, ported to Swift Testing.
// Since 0.2 AstroKit reproduces Lunker's numbers exactly, so the assertions
// are kept as they are in Lunker. The only API adaptation: Lunker's
// all-optional `twilightTimes` is `twilightBoundaries` here (AstroKit's
// `twilightTimes` keeps Equinox's non-optional sunrise/sunset).
// Lunker's scoring tests (scoreFactors, DayRating, fishCount, day score) stay
// in Lunker: the rating is not part of AstroKit.

private let stockholm = (lat: 59.3293, lon: 18.0686)
private let stockholmTZ = TimeZone(identifier: "Europe/Stockholm")!
private let tromso = (lat: 69.6492, lon: 18.9553)
private let tromsoTZ = TimeZone(identifier: "Europe/Oslo")!
private let utcTZ = TimeZone(identifier: "UTC")!
/// Fixed reference instant (not the wall clock) so tests are reproducible.
private let referenceNow = Date(timeIntervalSince1970: 1_782_864_000) // 2026-07-01 00:00 UTC

private func gregorian(_ tz: TimeZone) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal
}
private let utcCalendar = gregorian(utcTZ)
private let stockholmCalendar = gregorian(stockholmTZ)

/// An instant on the UTC wall clock.
private func utc(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A wall-clock instant in `timeZone`.
private func local(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, in timeZone: TimeZone) -> Date {
    gregorian(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Minutes after local midnight of `date` in `timeZone`.
private func localMinutes(_ date: Date, in timeZone: TimeZone) -> Double {
    let c = gregorian(timeZone).dateComponents([.hour, .minute, .second], from: date)
    return Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0) + Double(c.second ?? 0) / 60
}

// MARK: - SolarCalculator (Lunker SolarCalculatorTests)

@Suite("Lunker port — solar events")
struct LunkerSolarEventTests {
    @Test(arguments: [
        (SolarCalculator.SolarEventType.springEquinox, 3, 19...21),
        (.summerSolstice, 6, 20...22),
        (.autumnEquinox, 9, 21...24),
        (.winterSolstice, 12, 20...23),
    ])
    func eventDates2025(_ type: SolarCalculator.SolarEventType, _ month: Int, _ days: ClosedRange<Int>) {
        let event = SolarCalculator.solarEvent(type, year: 2025)
        #expect(utcCalendar.component(.month, from: event) == month)
        #expect(days.contains(utcCalendar.component(.day, from: event)))
    }

    @Test func allEventsReturnsAllFour() {
        let events = SolarCalculator.allEvents(year: 2025)
        #expect(events.count == 4)
        #expect(Set(events.map(\.type)) == Set(SolarCalculator.SolarEventType.allCases))
    }

    @Test func nextEventIsInFutureAndLastEventInPast() {
        let jan = utc(2025, 1, 15)
        #expect(SolarCalculator.nextEvent(after: jan).date > jan)
        let jun = utc(2025, 6, 15)
        #expect(SolarCalculator.lastEvent(before: jun).date < jun)
    }

    @Test func solsticeMirrorDateIsAfterNextSolstice() {
        let reference = utc(2025, 6, 1)
        #expect(SolarCalculator.solsticeMirrorDate(for: reference) > SolarCalculator.nextSolstice(after: reference).date)
    }

    @Test func eventTypeProperties() {
        #expect(SolarCalculator.SolarEventType.springEquinox.isEquinox)
        #expect(!SolarCalculator.SolarEventType.springEquinox.isSolstice)
        #expect(SolarCalculator.SolarEventType.summerSolstice.isSolstice)
        #expect(!SolarCalculator.SolarEventType.summerSolstice.isEquinox)
    }
}

@Suite("Lunker port — sunrise/sunset")
struct LunkerSunTimesTests {
    @Test func stockholmSummerHasLongDays() throws {
        let times = try #require(SolarCalculator.sunTimes(date: utc(2025, 6, 21), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(times.daylightDuration / 3600 > 18)
    }

    @Test func stockholmWinterHasShortDays() throws {
        let times = try #require(SolarCalculator.sunTimes(date: utc(2025, 12, 21), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(times.daylightDuration / 3600 < 7)
    }

    @Test func sunriseBeforeNoonBeforeSunset() throws {
        let march = try #require(SolarCalculator.sunTimes(date: utc(2025, 3, 21), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(march.sunrise < march.sunset)
        let june = try #require(SolarCalculator.sunTimes(date: utc(2025, 6, 15), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(june.solarNoon > june.sunrise)
        #expect(june.solarNoon < june.sunset)
    }

    @Test func equatorHas12HourDaysAtEquinox() throws {
        let times = try #require(SolarCalculator.sunTimes(date: utc(2025, 3, 21), latitude: 0, longitude: 0, timeZone: TimeZone(secondsFromGMT: 0)!))
        #expect(abs(times.daylightDuration / 3600 - 12) <= 0.5)
    }

    /// Solar noon in Stockholm on the spring-forward day (2026-03-29, 23 h long)
    /// is ≈ 10:52 UTC = 12:52 CEST, whatever time of that day is passed in.
    @Test func solarNoonOnSpringForwardDayIsIndependentOfInputTime() throws {
        let inputs = [
            local(2026, 3, 29, hour: 0, minute: 30, in: stockholmTZ),   // still CET
            local(2026, 3, 29, hour: 12, in: stockholmTZ),              // CEST
            local(2026, 3, 29, hour: 23, minute: 30, in: stockholmTZ),
        ]
        let noons = try inputs.map { input in
            try #require(SolarCalculator.sunTimes(date: input, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)).solarNoon
        }
        for noon in noons {
            #expect(abs(noon.timeIntervalSince(noons[0])) <= 1)
            #expect(abs(localMinutes(noon, in: stockholmTZ) - (12 * 60 + 52)) <= 3)
        }
    }

    /// Solar noon in Stockholm on the fall-back day (2026-10-25, 25 h long)
    /// is ≈ 10:32 UTC = 11:32 CET, whatever time of that day is passed in.
    @Test func solarNoonOnFallBackDayIsIndependentOfInputTime() throws {
        let inputs = [
            local(2026, 10, 25, hour: 0, minute: 30, in: stockholmTZ),  // still CEST
            local(2026, 10, 25, hour: 12, in: stockholmTZ),             // CET
            local(2026, 10, 25, hour: 23, minute: 30, in: stockholmTZ),
        ]
        let results = try inputs.map { input in
            try #require(SolarCalculator.sunTimes(date: input, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        }
        for times in results {
            #expect(abs(times.solarNoon.timeIntervalSince(results[0].solarNoon)) <= 1)
            #expect(abs(times.sunrise.timeIntervalSince(results[0].sunrise)) <= 1)
            #expect(abs(localMinutes(times.solarNoon, in: stockholmTZ) - (11 * 60 + 32)) <= 3)
        }
    }

    /// The sun path covers the whole 23 h spring-forward day, no more.
    @Test func sunPathSpansShortDstDay() throws {
        let path = SolarCalculator.sunPath(date: local(2026, 3, 29, hour: 12, in: stockholmTZ),
                                           latitude: stockholm.lat, longitude: stockholm.lon,
                                           intervalMinutes: 30, timeZone: stockholmTZ)
        #expect(path.count == 47)   // 23 h / 30 min = 46 steps + 1
        let first = try #require(path.first)
        let last = try #require(path.last)
        #expect(abs(last.time.timeIntervalSince(first.time) - 23 * 3600) <= 1)
    }

    @Test func sunPathOnNormalDayHas49HalfHourSamples() {
        let path = SolarCalculator.sunPath(date: utc(2025, 6, 15), latitude: stockholm.lat, longitude: stockholm.lon,
                                           intervalMinutes: 30, timeZone: stockholmTZ)
        #expect(path.count == 49)
    }
}

@Suite("Lunker port — polar day/night, twilight, golden hour")
struct LunkerPolarTwilightTests {
    @Test func tromsoDecemberIsPolarNight() {
        #expect(SolarCalculator.polarState(date: utc(2025, 12, 15), latitude: tromso.lat, longitude: tromso.lon, timeZone: tromsoTZ) == .polarNight)
        #expect(SolarCalculator.sunTimes(date: utc(2025, 12, 15), latitude: tromso.lat, longitude: tromso.lon, timeZone: tromsoTZ) == nil)
    }

    @Test func tromsoJuneIsPolarDay() {
        #expect(SolarCalculator.polarState(date: utc(2025, 6, 21), latitude: tromso.lat, longitude: tromso.lon, timeZone: tromsoTZ) == .polarDay)
    }

    @Test func polarStateIsNilWhenSunRisesAndSets() {
        #expect(SolarCalculator.polarState(date: utc(2025, 3, 21), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ) == nil)
    }

    /// Mid-December Tromsø has no sunrise, but civil twilight still happens.
    @Test func twilightExistsDuringTromsoPolarNight() throws {
        let date = utc(2025, 12, 15)
        let twilight = try #require(SolarCalculator.twilightBoundaries(date: date, latitude: tromso.lat, longitude: tromso.lon, timeZone: tromsoTZ))
        #expect(twilight.sunrise == nil)
        #expect(twilight.sunset == nil)
        let civilDawn = try #require(twilight.civilDawn)
        let civilDusk = try #require(twilight.civilDusk)
        #expect(civilDawn < civilDusk)
        let nauticalDawn = try #require(twilight.nauticalDawn)
        #expect(nauticalDawn < civilDawn)

        // The legacy shape (non-optional sunrise) cannot represent this day.
        #expect(SolarCalculator.twilightTimes(date: date, latitude: tromso.lat, longitude: tromso.lon, timeZone: tromsoTZ) == nil)

        let golden = try #require(SolarCalculator.goldenHourTimes(date: date, latitude: tromso.lat, longitude: tromso.lon, timeZone: tromsoTZ))
        #expect(golden.morningBlueStart != nil, "blue hour still occurs in polar night")
        #expect(golden.morningGoldenEnd == nil, "the sun never reaches +6°")
    }

    @Test func twilightExistsAndIsOrdered() throws {
        #expect(SolarCalculator.twilightBoundaries(date: utc(2025, 6, 15), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ) != nil)

        let t = try #require(SolarCalculator.twilightBoundaries(date: utc(2025, 3, 21), latitude: 45, longitude: 0, timeZone: TimeZone(secondsFromGMT: 0)!))
        let astroDawn = try #require(t.astronomicalDawn)
        let nautDawn = try #require(t.nauticalDawn)
        let civilDawn = try #require(t.civilDawn)
        let sunrise = try #require(t.sunrise)
        #expect(astroDawn < nautDawn)
        #expect(nautDawn < civilDawn)
        #expect(civilDawn < sunrise)
        let sunset = try #require(t.sunset)
        let civilDusk = try #require(t.civilDusk)
        let nautDusk = try #require(t.nauticalDusk)
        let astroDusk = try #require(t.astronomicalDusk)
        #expect(sunset < civilDusk)
        #expect(civilDusk < nautDusk)
        #expect(nautDusk < astroDusk)

        // twilightTimes agrees field by field whenever the sun rises.
        let legacy = try #require(SolarCalculator.twilightTimes(date: utc(2025, 3, 21), latitude: 45, longitude: 0, timeZone: TimeZone(secondsFromGMT: 0)!))
        #expect(legacy.sunrise == sunrise && legacy.sunset == sunset)
        #expect(legacy.astronomicalDawn == astroDawn && legacy.astronomicalDusk == astroDusk)
        #expect(legacy.civilDawn == civilDawn && legacy.civilDusk == civilDusk)
    }

    @Test func goldenHourExistsAndMorningIsOrdered() throws {
        #expect(SolarCalculator.goldenHourTimes(date: utc(2025, 6, 15), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ) != nil)
        let g = try #require(SolarCalculator.goldenHourTimes(date: utc(2025, 3, 21), latitude: 45, longitude: 0, timeZone: TimeZone(secondsFromGMT: 0)!))
        let blueStart = try #require(g.morningBlueStart)
        let blueEnd = try #require(g.morningBlueEnd)
        let goldenEnd = try #require(g.morningGoldenEnd)
        #expect(blueStart < blueEnd)
        #expect(blueEnd < goldenEnd)
    }
}

@Suite("Lunker port — solar elevation and position")
struct LunkerSolarPositionTests {
    @Test func elevationAtNoonIsPositiveAndAtWinterMidnightNegative() throws {
        let times = try #require(SolarCalculator.sunTimes(date: utc(2025, 6, 15), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(SolarCalculator.solarElevation(at: times.solarNoon, latitude: stockholm.lat, longitude: stockholm.lon) > 0)
        #expect(SolarCalculator.solarElevation(at: utc(2025, 12, 21, hour: 0), latitude: stockholm.lat, longitude: stockholm.lon) < 0)
    }

    @Test func maxSolarElevationAtSolstice() throws {
        let max = try #require(SolarCalculator.maxSolarElevation(date: utc(2025, 6, 21), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        #expect(max > 50 && max < 60)   // ~54° at 59°N
    }

    @Test func azimuthInRangeAndSouthAtNoon() throws {
        let p = SolarCalculator.solarPosition(at: utc(2025, 6, 15, hour: 15), latitude: stockholm.lat, longitude: stockholm.lon)
        #expect(p.azimuth >= 0 && p.azimuth < 360)
        let times = try #require(SolarCalculator.sunTimes(date: utc(2025, 6, 15), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ))
        let noon = SolarCalculator.solarPosition(at: times.solarNoon, latitude: stockholm.lat, longitude: stockholm.lon)
        #expect(noon.azimuth > 160 && noon.azimuth < 200)
    }

    /// Lunker's SolunarZoneMap reads `subsolarPoint(date:).latitude/.longitude`
    /// (a tuple in Lunker, a struct here). Longitude is in [−180, 180).
    @Test func subsolarPointAtUTCNoonIsNearGreenwich() {
        // Equation of time ≈ −14.2 min: the sun crosses Greenwich ~14 min after
        // 12:00 UT, so at 12:00 UT it is overhead ≈ 3.55° east.
        let p = SolarCalculator.subsolarPoint(date: utc(2026, 2, 11))
        #expect(abs(p.longitude - 3.55) < 0.3)
        #expect(p.longitude >= -180 && p.longitude < 180)
        let antimeridian = SolarCalculator.subsolarPoint(date: utc(2026, 11, 3, hour: 0))   // EoT ≈ +16 min
        #expect(antimeridian.longitude >= -180 && antimeridian.longitude < 180)
    }
}

// MARK: - MoonCalculator (Lunker MoonCalculatorTests)

@Suite("Lunker port — moon phase")
struct LunkerMoonPhaseTests {
    @Test func fullAndNewMoonIllumination() {
        #expect(MoonCalculator.moonPhase(for: utc(2025, 1, 13)).illumination > 0.95)
        #expect(MoonCalculator.moonPhase(for: utc(2025, 1, 29)).illumination < 0.05)
    }

    @Test func ageAndNextPhasesAreConsistent() {
        let p = MoonCalculator.moonPhase(for: referenceNow)
        #expect(p.age >= 0 && p.age < p.synodicMonth)
        #expect(p.nextFullMoon > referenceNow)
        #expect(p.nextNewMoon > referenceNow)
    }

    @Test func allEightPhasesAreReachable() {
        let phases = Set((0..<30).map { MoonCalculator.moonPhase(for: utc(2025, 1, 1 + $0)).phase })
        #expect(phases.count == 8)
    }

    /// Phase bins are centred on the event: at the instant of full moon
    /// (2026-03-03 11:38 UTC) the label is Full Moon, not a gibbous edge.
    @Test func phaseLabelAtKnownFullMoon() {
        #expect(MoonCalculator.moonPhase(for: utc(2026, 3, 3, hour: 11, minute: 38)).phase == .fullMoon)
        // A day either side is still within the ±1.85-day Full Moon bin.
        #expect(MoonCalculator.moonPhase(for: utc(2026, 3, 2, hour: 11, minute: 38)).phase == .fullMoon)
        #expect(MoonCalculator.moonPhase(for: utc(2026, 3, 4, hour: 11, minute: 38)).phase == .fullMoon)
    }

    /// At the instant of new moon (2026-02-17 12:01 UTC) the label is New Moon
    /// even though the computed age sits just below the synodic month.
    @Test func phaseLabelAtKnownNewMoon() {
        let info = MoonCalculator.moonPhase(for: utc(2026, 2, 17, hour: 12, minute: 1))
        #expect(info.phase == .newMoon)
        #expect(info.illumination < 0.02)
    }

    /// Age and illumination come from the same elongation (0.2): the phase
    /// angle is exactly age / synodic month × 360°.
    @Test func ageIsDerivedFromElongation() {
        var t = utc(2026, 1, 1, hour: 0)
        for _ in 0..<60 {
            let p = MoonCalculator.moonPhase(for: t)
            #expect(abs(p.age - p.phaseAngle / 360 * p.synodicMonth) < 1e-9)
            t = t.addingTimeInterval(13 * 3600)
        }
    }

    /// Lunker's `dayPhase(for:)`: the phase sampled at the day's midday.
    @Test func dayPhaseSamplesMidday() {
        let dayStart = stockholmCalendar.startOfDay(for: local(2026, 3, 3, in: stockholmTZ))
        let day = MoonCalculator.dayPhase(for: dayStart)
        let midday = MoonCalculator.moonPhase(for: dayStart.addingTimeInterval(12 * 3600))
        #expect(day == midday)
    }

    @Test func symbolNameAndIsWaxing() {
        let expected: [MoonCalculator.MoonPhase: (String, Bool)] = [
            .newMoon: ("moonphase.new.moon", true),
            .waxingCrescent: ("moonphase.waxing.crescent", true),
            .firstQuarter: ("moonphase.first.quarter", true),
            .waxingGibbous: ("moonphase.waxing.gibbous", true),
            .fullMoon: ("moonphase.full.moon", false),
            .waningGibbous: ("moonphase.waning.gibbous", false),
            .lastQuarter: ("moonphase.last.quarter", false),
            .waningCrescent: ("moonphase.waning.crescent", false),
        ]
        for phase in MoonCalculator.MoonPhase.allCases {
            #expect(phase.symbolName == expected[phase]?.0)
            #expect(phase.isWaxing == expected[phase]?.1)
        }
        // Equinox's generic `icon` is unchanged.
        #expect(MoonCalculator.MoonPhase.fullMoon.icon == "moon.circle.fill")
    }
}

@Suite("Lunker port — moonrise/moonset")
struct LunkerMoonTimesTests {
    @Test func reasonableTimesAndTransit() {
        let t = MoonCalculator.moonTimes(date: utc(2025, 6, 15), latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
        #expect(t.moonrise != nil || t.moonset != nil)
        #expect(t.transitTime != nil)
    }

    /// Moonrise can come before or after moonset on a given day, so the
    /// meaningful properties are: both lie within the local day, the moon is
    /// actually climbing through the horizon at moonrise and sinking at moonset.
    @Test func moonriseAndMoonsetAreHorizonCrossingsWithinLocalDay() throws {
        func altitude(_ t: Date) -> Double {
            MoonCalculator.lunarPosition(at: t, latitude: stockholm.lat, longitude: stockholm.lon).altitude
        }
        var daysWithBoth = 0
        for dayOffset in 0..<15 {
            let day = utc(2025, 3, 1 + dayOffset)
            let dayStart = stockholmCalendar.startOfDay(for: day)
            let dayEnd = try #require(stockholmCalendar.date(byAdding: .day, value: 1, to: dayStart))
            let t = MoonCalculator.moonTimes(date: day, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
            if let rise = t.moonrise {
                #expect(rise >= dayStart && rise <= dayEnd)
                #expect(altitude(rise.addingTimeInterval(-600)) < altitude(rise.addingTimeInterval(600)), "moon must be rising at moonrise (day \(dayOffset))")
            }
            if let set = t.moonset {
                #expect(set >= dayStart && set <= dayEnd)
                #expect(altitude(set.addingTimeInterval(-600)) > altitude(set.addingTimeInterval(600)), "moon must be setting at moonset (day \(dayOffset))")
            }
            if t.moonrise != nil && t.moonset != nil { daysWithBoth += 1 }
        }
        #expect(daysWithBoth > 0)
    }

    /// On the 23 h spring-forward day the scan stops at the next local
    /// midnight: no event may land in the following day.
    @Test func moonTimesStayWithinShortDstDay() throws {
        let day = utc(2026, 3, 29)
        let dayStart = stockholmCalendar.startOfDay(for: day)
        let dayEnd = try #require(stockholmCalendar.date(byAdding: .day, value: 1, to: dayStart))
        #expect(abs(dayEnd.timeIntervalSince(dayStart) - 23 * 3600) <= 1)
        let times = MoonCalculator.moonTimes(date: day, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ)
        for event in [times.moonrise, times.moonset, times.transitTime].compactMap({ $0 }) {
            #expect(event >= dayStart && event <= dayEnd)
        }
    }

    /// The transit is never the next day's midnight sample.
    @Test func transitIsStrictlyBeforeNextMidnight() throws {
        var day = stockholmCalendar.startOfDay(for: utc(2026, 1, 1))
        for _ in 0..<60 {
            let next = try #require(stockholmCalendar.date(byAdding: .day, value: 1, to: day))
            let transit = try #require(MoonCalculator.moonTimes(date: day, latitude: stockholm.lat, longitude: stockholm.lon, timeZone: stockholmTZ).transitTime)
            #expect(transit >= day && transit < next)
            day = next
        }
    }
}

@Suite("Lunker port — lunar position and distance")
struct LunkerLunarPositionDistanceTests {
    @Test func positionRanges() {
        let p = MoonCalculator.lunarPosition(at: referenceNow, latitude: stockholm.lat, longitude: stockholm.lon)
        #expect(MoonCalculator.ZodiacConstellation.allCases.contains(p.constellation))
        #expect(p.eclipticLongitude >= 0 && p.eclipticLongitude < 360)
        #expect(p.rightAscension >= 0 && p.rightAscension < 360)
        #expect(p.declination >= -30 && p.declination <= 30)
        #expect(p.azimuth >= 0 && p.azimuth < 360)
        #expect(!MoonCalculator.lunarPosition(at: utc(2025, 4, 1), latitude: stockholm.lat, longitude: stockholm.lon).constellation.symbol.isEmpty)
    }

    @Test func distanceRangesAndNextApsides() {
        let d = MoonCalculator.lunarDistance(for: referenceNow)
        #expect(d.distanceKm > 350_000 && d.distanceKm < 410_000)
        #expect(d.percentOfAverage > 90 && d.percentOfAverage < 108)
        let toPerigee = d.nextPerigee.timeIntervalSince(referenceNow)
        let toApogee = d.nextApogee.timeIntervalSince(referenceNow)
        #expect(toPerigee > 0 && toPerigee < 28 * 86400)
        #expect(toApogee > 0 && toApogee < 28 * 86400)
        #expect(MoonCalculator.LunarDistanceStatus.allCases.contains(d.distanceStatus))
    }

    /// Lunar distance follows Meeus ch. 47: the 2025-11-05 22:27 UTC perigee
    /// was 356,833 km. (0.1 gave 356,294 km.)
    @Test func distanceAtKnownPerigee() {
        let info = MoonCalculator.lunarDistance(for: utc(2025, 11, 5, hour: 22, minute: 27))
        #expect(abs(info.distanceKm - 356_833) <= 300)
    }

    @Test func zodiacElementsAndSymbols() {
        #expect(MoonCalculator.ZodiacConstellation.aries.element == "Fire")
        #expect(MoonCalculator.ZodiacConstellation.taurus.element == "Earth")
        #expect(MoonCalculator.ZodiacConstellation.gemini.element == "Air")
        #expect(MoonCalculator.ZodiacConstellation.cancer.element == "Water")
        #expect(MoonCalculator.ZodiacConstellation.aries.symbol == "♈")
        #expect(MoonCalculator.ZodiacConstellation.pisces.symbol == "♓")
    }
}

@Suite("Lunker port — eclipses")
struct LunkerEclipseTests {
    @Test func upcomingEclipsesReturnResultsSortedAndInFuture() {
        let eclipses = MoonCalculator.upcomingEclipses(after: utc(2025, 1, 1), limit: 5)
        #expect(!eclipses.isEmpty && eclipses.count <= 5)
        let reference = utc(2025, 1, 1)
        for eclipse in MoonCalculator.upcomingEclipses(after: reference, limit: 3, calendar: utcCalendar) {
            #expect(eclipse.date > reference)
        }
        let all = MoonCalculator.upcomingEclipses(after: reference, limit: 100, calendar: utcCalendar)
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    /// Eclipse dates are the instant of greatest eclipse (UT), independent of
    /// the device calendar/zone.
    @Test func eclipseDatesAreGreatestEclipseInstants() throws {
        let first = try #require(MoonCalculator.upcomingEclipses(after: utc(2026, 9, 1), limit: 3, calendar: utcCalendar).first)
        #expect(first.date == utc(2027, 2, 6, hour: 16, minute: 0))
        #expect(first.type == .solarAnnular)
    }

    /// Regression: today's eclipse must stay listed for the whole local day.
    @Test func todaysEclipseStaysListedAllDay() throws {
        // 2026-08-28 partial lunar eclipse, greatest ~04:13 UT.
        let lateThatDay = utc(2026, 8, 28, hour: 23, minute: 30)
        let first = try #require(MoonCalculator.upcomingEclipses(after: lateThatDay, limit: 1, calendar: utcCalendar).first)
        #expect(first.type == .lunarPartial)
        #expect(utcCalendar.isDate(first.date, inSameDayAs: lateThatDay))
        let next = try #require(MoonCalculator.upcomingEclipses(after: utc(2026, 8, 29, hour: 0, minute: 30), limit: 1, calendar: utcCalendar).first)
        #expect(next.type != .lunarPartial)
    }

    /// In UTC+13 the 2026-08-12 total solar eclipse (greatest 17:46 UT) falls on
    /// Aug 13 local time; noon anchoring showed it a day early.
    @Test func eclipseLandsOnLocalDayInFarEastZones() throws {
        let tongatapu = gregorian(try #require(TimeZone(identifier: "Pacific/Tongatapu")))
        let eclipse = try #require(MoonCalculator.upcomingEclipses(after: utc(2026, 8, 1), limit: 5, calendar: tongatapu).first { $0.type == .solarTotal })
        #expect(tongatapu.component(.day, from: eclipse.date) == 13)
        #expect(tongatapu.component(.month, from: eclipse.date) == 8)
    }

    /// Pins the table's coverage (through 2035) so a truncated table is caught.
    @Test func tableCoversThrough2035() throws {
        let end = try #require(MoonCalculator.eclipseTableCoverageEnd)
        #expect(end >= utc(2035, 9, 1))
        #expect(end == utc(2035, 9, 2, hour: 1, minute: 56))
        let late = MoonCalculator.upcomingEclipses(after: utc(2034, 9, 1), limit: 100, calendar: utcCalendar)
        #expect(late.count >= 6, "2034-09 → 2035-09 has six eclipses")
    }

    /// The entries 0.2 adds to Equinox's 0.1 table (Lunker's), and the one
    /// entry where AstroKit keeps Equinox's (more precise) classification.
    @Test func tableEntriesAddedIn0_2() throws {
        let all = MoonCalculator.upcomingEclipses(after: utc(2024, 1, 1), limit: 100)
        #expect(all.count == 49)
        let added: [(Date, MoonCalculator.EclipseEvent.EclipseType)] = [
            (utc(2025, 3, 29, hour: 10, minute: 47), .solarPartial),
            (utc(2025, 9, 21, hour: 19, minute: 42), .solarPartial),
            (utc(2026, 2, 17, hour: 12, minute: 12), .solarAnnular),
            (utc(2026, 3, 3, hour: 11, minute: 34), .lunarTotal),
            (utc(2027, 7, 18, hour: 16, minute: 3), .lunarPenumbral),
        ]
        for (date, type) in added {
            #expect(all.contains { $0.date == date && $0.type == type }, "missing \(type) at \(date)")
        }
        // Lunker lists 2031-11-14 as annular only because it had no hybrid case.
        let hybrid = try #require(all.first { $0.date == utc(2031, 11, 14, hour: 21, minute: 6) })
        #expect(hybrid.type == .solarHybrid)
    }
}

// MARK: - Solunar (Lunker SolunarCalculatorTests, astronomy part)

@Suite("Lunker port — solunar periods")
struct LunkerSolunarTests {
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0, lat: Double = stockholm.lat, lon: Double = stockholm.lon) -> Solunar.Day {
        Solunar.day(for: local(y, m, d, hour: hour, minute: minute, in: stockholmTZ), latitude: lat, longitude: lon, calendar: stockholmCalendar)
    }

    @Test func periodStructure() {
        let major = Solunar.Period(kind: .majorOverhead, center: referenceNow)
        let minor = Solunar.Period(kind: .minorMoonrise, center: referenceNow)
        #expect(abs(major.end.timeIntervalSince(major.start) - 120 * 60) <= 1)
        #expect(abs(minor.end.timeIntervalSince(minor.start) - 60 * 60) <= 1)
        #expect(major.contains(referenceNow))
        #expect(major.contains(referenceNow.addingTimeInterval(-30 * 60)) && major.contains(referenceNow.addingTimeInterval(30 * 60)))
        #expect(!major.contains(referenceNow.addingTimeInterval(-90 * 60)) && !major.contains(referenceNow.addingTimeInterval(90 * 60)))
    }

    @Test func stockholmDayHasTwoToFourChronologicalPeriods() {
        let d = day(2026, 5, 10)
        #expect((2...4).contains(d.periods.count))
        #expect(!d.periods.isEmpty)
        #expect(zip(d.periods, d.periods.dropFirst()).allSatisfy { $0.center <= $1.center })
    }

    /// The cache is keyed by day, so results must not depend on the time of day
    /// of whichever call filled it.
    @Test func independentOfInputTimeOfDay() {
        let early = day(2026, 4, 14, hour: 0, minute: 30, lat: 57.7089, lon: 11.9746)
        let late = day(2026, 4, 14, hour: 23, minute: 30, lat: 57.7089, lon: 11.9946)
        #expect(early.date == late.date)
        let again = day(2026, 4, 14, hour: 18, lat: 57.7089, lon: 11.9746)
        #expect(again.periods == early.periods)
        #expect(again == early)
    }

    @Test func periodsAreWithinDay() throws {
        let d = day(2026, 4, 20)
        let dayEnd = try #require(stockholmCalendar.date(byAdding: .day, value: 1, to: d.date))
        for period in d.periods {
            #expect(period.center >= d.date && period.center < dayEnd)
        }
    }

    /// Regression: a transit within 5 minutes of either day edge was dropped by
    /// both days. In Stockholm the moon transits at ~00:03 local on 2026-05-01;
    /// it must be listed under May 1 (and not under April 30).
    @Test func transitJustAfterMidnightIsKeptByItsDay() throws {
        let may1 = day(2026, 5, 1)
        let transit = try #require(may1.periods.first { $0.kind == .majorOverhead })
        #expect(transit.center >= may1.date)
        #expect(transit.center < may1.date.addingTimeInterval(15 * 60))
        let april30 = day(2026, 4, 30)
        #expect(!april30.periods.contains { $0.kind == .majorOverhead && $0.center == transit.center })
    }

    /// 2026-05-01 is close to full moon (Lunker: phase factor > 30 of 50, i.e.
    /// |2·illumination − 1| > 0.6 at the day's midday).
    @Test func fullMoonDayHasStrongPhase() {
        let d = day(2026, 5, 1)
        let illumination = MoonCalculator.moonPhase(for: d.date.addingTimeInterval(12 * 3600)).illumination
        #expect(abs(2 * illumination - 1) > 0.6)
    }
}
