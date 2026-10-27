import Foundation

/// Calculates solar events (equinoxes, solstices) and sunrise/sunset times.
/// Based on the NOAA solar calculator and Jean Meeus "Astronomical Algorithms".
///
/// Ported from Equinox (`Shared/SolarCalculator.swift`), the reference
/// implementation. Additions for Lunker (`polarState`, `PolarState`) and Otta
/// (`eventTimeClampingPolar`) are layered on the same math, so every app gets
/// identical numbers.
///
/// All members are static and pure; the only state is a lock-guarded cache of
/// equinox/solstice dates per year.
public struct SolarCalculator: Sendable {

    // MARK: - Solar Event Types

    public enum SolarEventType: String, CaseIterable, Sendable, Hashable {
        case springEquinox = "Spring Equinox"
        case summerSolstice = "Summer Solstice"
        case autumnEquinox = "Autumn Equinox"
        case winterSolstice = "Winter Solstice"

        /// Localized display name. `rawValue` is the English source key, looked
        /// up in the host app's main-bundle string catalog.
        public var localizedName: String { NSLocalizedString(rawValue, bundle: .main, comment: "Solar event name") }

        public var isEquinox: Bool {
            self == .springEquinox || self == .autumnEquinox
        }

        public var isSolstice: Bool {
            self == .summerSolstice || self == .winterSolstice
        }
    }

    public struct SolarEvent: Sendable, Hashable {
        public let type: SolarEventType
        public let date: Date

        public init(type: SolarEventType, date: Date) {
            self.type = type
            self.date = date
        }
    }

    public struct SunTimes: Sendable, Hashable {
        public let sunrise: Date
        public let sunset: Date
        public let solarNoon: Date

        public init(sunrise: Date, sunset: Date, solarNoon: Date) {
            self.sunrise = sunrise
            self.sunset = sunset
            self.solarNoon = solarNoon
        }

        public var daylightDuration: TimeInterval {
            sunset.timeIntervalSince(sunrise)
        }
    }

    public struct TwilightTimes: Sendable, Hashable {
        public let astronomicalDawn: Date?
        public let nauticalDawn: Date?
        public let civilDawn: Date?
        public let sunrise: Date
        public let sunset: Date
        public let civilDusk: Date?
        public let nauticalDusk: Date?
        public let astronomicalDusk: Date?

        public init(astronomicalDawn: Date?, nauticalDawn: Date?, civilDawn: Date?, sunrise: Date, sunset: Date,
                    civilDusk: Date?, nauticalDusk: Date?, astronomicalDusk: Date?) {
            self.astronomicalDawn = astronomicalDawn
            self.nauticalDawn = nauticalDawn
            self.civilDawn = civilDawn
            self.sunrise = sunrise
            self.sunset = sunset
            self.civilDusk = civilDusk
            self.nauticalDusk = nauticalDusk
            self.astronomicalDusk = astronomicalDusk
        }
    }

    /// Photographer-standard golden and blue hour boundaries.
    /// Blue hour: sun between -6° and -4° (zenith 96°↔94°).
    /// Golden hour: sun between -4° and +6° (zenith 94°↔84°).
    public struct GoldenHourTimes: Sendable, Hashable {
        public let morningBlueStart: Date?    // sun reaches -6° (= civil dawn)
        public let morningBlueEnd: Date?      // sun reaches -4° (= morning golden start)
        public let morningGoldenEnd: Date?    // sun reaches +6° (light becomes harsh)
        public let eveningGoldenStart: Date?  // sun falls to +6° (golden hour begins)
        public let eveningGoldenEnd: Date?    // sun falls to -4° (= evening blue start)
        public let eveningBlueEnd: Date?      // sun falls to -6° (= civil dusk)

        public init(morningBlueStart: Date?, morningBlueEnd: Date?, morningGoldenEnd: Date?,
                    eveningGoldenStart: Date?, eveningGoldenEnd: Date?, eveningBlueEnd: Date?) {
            self.morningBlueStart = morningBlueStart
            self.morningBlueEnd = morningBlueEnd
            self.morningGoldenEnd = morningGoldenEnd
            self.eveningGoldenStart = eveningGoldenStart
            self.eveningGoldenEnd = eveningGoldenEnd
            self.eveningBlueEnd = eveningBlueEnd
        }

        public var morningBlueDuration: TimeInterval? {
            guard let s = morningBlueStart, let e = morningBlueEnd else { return nil }
            return e.timeIntervalSince(s)
        }
        public var morningGoldenDuration: TimeInterval? {
            guard let s = morningBlueEnd, let e = morningGoldenEnd else { return nil }
            return e.timeIntervalSince(s)
        }
        public var eveningGoldenDuration: TimeInterval? {
            guard let s = eveningGoldenStart, let e = eveningGoldenEnd else { return nil }
            return e.timeIntervalSince(s)
        }
        public var eveningBlueDuration: TimeInterval? {
            guard let s = eveningGoldenEnd, let e = eveningBlueEnd else { return nil }
            return e.timeIntervalSince(s)
        }
    }

    public enum UVLevel: String, Sendable, Hashable, CaseIterable {
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
        case veryHigh = "Very High"
        case extreme = "Extreme"

        /// Localized display name. `rawValue` is the English source key, looked
        /// up in the host app's main-bundle string catalog.
        public var localizedName: String { NSLocalizedString(rawValue, bundle: .main, comment: "UV index level") }

        public var color: String {
            switch self {
            case .low: return "green"
            case .moderate: return "yellow"
            case .high: return "orange"
            case .veryHigh: return "red"
            case .extreme: return "purple"
            }
        }

        public static func from(uvIndex: Double) -> UVLevel {
            switch uvIndex {
            case ..<3: return .low
            case 3..<6: return .moderate
            case 6..<8: return .high
            case 8..<11: return .veryHigh
            default: return .extreme
            }
        }
    }

    // MARK: - Constants

    // Astronomical date arithmetic must be Gregorian: locales like ar-SA default
    // to a lunar calendar whose year/month components would corrupt the algorithms.
    private static let calendar = Calendar(identifier: .gregorian)
    private static let rad = Double.pi / 180
    private static let deg = 180 / Double.pi

    // Cache for solar events by year (events are the same worldwide).
    private static let eventCacheLock = NSLock()
    nonisolated(unsafe) private static var eventCache: [Int: [SolarEvent]] = [:]

    // MARK: - Equinox and Solstice Calculations

    /// Calculate the approximate date of a solar event for a given year
    /// Using Jean Meeus algorithm
    public static func solarEvent(_ type: SolarEventType, year: Int) -> Date {
        let y = (Double(year) - 2000) / 1000

        let jde: Double
        switch type {
        case .springEquinox:
            jde = 2451623.80984 + 365242.37404 * y + 0.05169 * y * y - 0.00411 * y * y * y - 0.00057 * y * y * y * y
        case .summerSolstice:
            jde = 2451716.56767 + 365241.62603 * y + 0.00325 * y * y + 0.00888 * y * y * y - 0.00030 * y * y * y * y
        case .autumnEquinox:
            jde = 2451810.21715 + 365242.01767 * y - 0.11575 * y * y + 0.00337 * y * y * y + 0.00078 * y * y * y * y
        case .winterSolstice:
            jde = 2451900.05952 + 365242.74049 * y - 0.06223 * y * y - 0.00823 * y * y * y + 0.00032 * y * y * y * y
        }

        return julianToDate(jde)
    }

    /// Get all solar events for a given year (cached)
    public static func allEvents(year: Int) -> [SolarEvent] {
        eventCacheLock.lock()
        if let cached = eventCache[year] {
            eventCacheLock.unlock()
            return cached
        }
        eventCacheLock.unlock()

        let events = SolarEventType.allCases.map { type in
            SolarEvent(type: type, date: solarEvent(type, year: year))
        }

        eventCacheLock.lock()
        eventCache[year] = events
        eventCacheLock.unlock()
        return events
    }

    /// Find the last solar event before a given date
    public static func lastEvent(before date: Date, ofType types: [SolarEventType]? = nil) -> SolarEvent {
        let year = calendar.component(.year, from: date)
        let targetTypes = types ?? SolarEventType.allCases

        // Check current year and previous year
        let events = (allEvents(year: year - 1) + allEvents(year: year))
            .filter { targetTypes.contains($0.type) }
            .filter { $0.date < date }
            .sorted { $0.date > $1.date }

        guard let first = events.first else {
            preconditionFailure("lastEvent(before:ofType:) produced no candidates — types array must not be empty")
        }
        return first
    }

    /// Find the next solar event after a given date
    public static func nextEvent(after date: Date, ofType types: [SolarEventType]? = nil) -> SolarEvent {
        let year = calendar.component(.year, from: date)
        let targetTypes = types ?? SolarEventType.allCases

        // Check current year and next year
        let events = (allEvents(year: year) + allEvents(year: year + 1))
            .filter { targetTypes.contains($0.type) }
            .filter { $0.date > date }
            .sorted { $0.date < $1.date }

        guard let first = events.first else {
            preconditionFailure("nextEvent(after:ofType:) produced no candidates — types array must not be empty")
        }
        return first
    }

    /// Find the last equinox before a given date
    public static func lastEquinox(before date: Date) -> SolarEvent {
        lastEvent(before: date, ofType: [.springEquinox, .autumnEquinox])
    }

    /// Find the next equinox after a given date
    public static func nextEquinox(after date: Date) -> SolarEvent {
        nextEvent(after: date, ofType: [.springEquinox, .autumnEquinox])
    }

    /// Find the last solstice before a given date
    public static func lastSolstice(before date: Date) -> SolarEvent {
        lastEvent(before: date, ofType: [.summerSolstice, .winterSolstice])
    }

    /// Find the next solstice after a given date
    public static func nextSolstice(after date: Date) -> SolarEvent {
        nextEvent(after: date, ofType: [.summerSolstice, .winterSolstice])
    }

    /// Date that is the same interval *after* the next solstice as `date` is *before* it.
    /// Both dates have approximately equal daylight duration (symmetric about the solstice).
    public static func solsticeMirrorDate(for date: Date) -> Date {
        let next = nextSolstice(after: date).date
        return next.addingTimeInterval(next.timeIntervalSince(date))
    }

    // MARK: - Sunrise/Sunset Calculations (NOAA Algorithm)

    /// Why `sunTimes` returned nil: the sun never sets (midnight sun) or never
    /// rises (polar night). Lets callers show "Midnight sun"/"Polar night"
    /// instead of an ambiguous placeholder that reads like a failure.
    public enum PolarCondition: Sendable, Hashable {
        case midnightSun
        case polarNight
    }

    /// Lunker's spelling of `PolarCondition`: whether the sun stays above
    /// (polar day) or below (polar night) the horizon for a whole local day.
    public enum PolarState: Sendable, Hashable {
        case polarDay
        case polarNight
    }

    /// Non-nil when the location has no sunrise/sunset on this date.
    public static func polarCondition(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> PolarCondition? {
        guard sunTimes(date: date, latitude: latitude, longitude: longitude, timeZone: timeZone) == nil else { return nil }
        let cal = calendar
        var noonComponents = cal.dateComponents(in: timeZone, from: date)
        noonComponents.hour = 12; noonComponents.minute = 0; noonComponents.second = 0
        let noon = cal.date(from: noonComponents) ?? date
        return solarElevation(at: noon, latitude: latitude, longitude: longitude) > 0 ? .midnightSun : .polarNight
    }

    /// Whether the sun stays up (`.polarDay`) or down (`.polarNight`) all day,
    /// judged by the same refracted-horizon threshold (zenith 90.833°) and the
    /// same declination as `sunTimes`, so it is non-nil exactly when `sunTimes`
    /// is nil. Returns nil when the sun rises and sets normally that day.
    public static func polarState(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> PolarState? {
        let cosHA = cosHourAngle(date: date, latitude: latitude, zenith: 90.833)
        if cosHA < -1 { return .polarDay }
        if cosHA > 1 { return .polarNight }
        return nil
    }

    /// Calculate sunrise and sunset times for a given date and location
    public static func sunTimes(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> SunTimes? {
        let cal = calendar
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)

        // Julian day
        let jd = julianDay(year: year, month: month, day: day)

        let t = (jd - 2451545.0) / 36525.0
        let elements = solarElements(t: t)
        let declin = elements.declin
        let eqTime = elements.eqTime

        // Hour angle for sunrise/sunset
        let latRad = latitude * rad
        let decRad = declin * rad
        let zenith = 90.833 // Official zenith for sunrise/sunset

        let cosHA = (cos(zenith * rad) / (cos(latRad) * cos(decRad))) - tan(latRad) * tan(decRad)

        // Check for polar day/night
        if cosHA > 1 || cosHA < -1 {
            return nil // No sunrise/sunset (polar)
        }

        let ha = acos(cosHA) * deg

        // Timezone offset in minutes
        let tzOffsetMinutes = Double(timeZone.secondsFromGMT(for: date)) / 60.0

        // Solar noon in local time (minutes from midnight)
        let solarNoonMinutes = 720 - 4 * longitude - eqTime + tzOffsetMinutes

        // Sunrise and sunset times (minutes from local midnight)
        let sunriseMinutes = solarNoonMinutes - ha * 4
        let sunsetMinutes = solarNoonMinutes + ha * 4

        let sunrise = instant(minutesAfterLocalMidnight: sunriseMinutes, tzOffsetMinutes: tzOffsetMinutes, on: date, timeZone: timeZone)
        let sunset = instant(minutesAfterLocalMidnight: sunsetMinutes, tzOffsetMinutes: tzOffsetMinutes, on: date, timeZone: timeZone)
        let solarNoon = instant(minutesAfterLocalMidnight: solarNoonMinutes, tzOffsetMinutes: tzOffsetMinutes, on: date, timeZone: timeZone)

        return SunTimes(sunrise: sunrise, sunset: sunset, solarNoon: solarNoon)
    }

    /// Converts a NOAA local clock time (minutes after local midnight, at
    /// `tzOffsetMinutes`) to an absolute instant. Going through UTC rather than
    /// adding elapsed seconds to local midnight keeps the result right on DST
    /// change days, when midnight and the event sit on different UTC offsets.
    private static func instant(minutesAfterLocalMidnight minutes: Double, tzOffsetMinutes: Double, on date: Date, timeZone: TimeZone) -> Date {
        var localCal = calendar
        localCal.timeZone = timeZone
        var utcCal = calendar
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let day = localCal.dateComponents([.year, .month, .day], from: date)
        let utcMidnight = utcCal.date(from: day) ?? localCal.startOfDay(for: date)
        return utcMidnight.addingTimeInterval((minutes - tzOffsetMinutes) * 60)
    }

    // MARK: - Twilight Calculations

    /// Calculate all twilight times for a given date and location
    /// Twilight zenith angles:
    /// - Civil: 96° (sun 6° below horizon)
    /// - Nautical: 102° (sun 12° below horizon)
    /// - Astronomical: 108° (sun 18° below horizon)
    public static func twilightTimes(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> TwilightTimes? {
        guard let sunTimes = sunTimes(date: date, latitude: latitude, longitude: longitude, timeZone: timeZone) else {
            return nil
        }

        let civilDawn = sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 96, isSunrise: true, timeZone: timeZone)
        let civilDusk = sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 96, isSunrise: false, timeZone: timeZone)

        let nauticalDawn = sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 102, isSunrise: true, timeZone: timeZone)
        let nauticalDusk = sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 102, isSunrise: false, timeZone: timeZone)

        let astronomicalDawn = sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 108, isSunrise: true, timeZone: timeZone)
        let astronomicalDusk = sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 108, isSunrise: false, timeZone: timeZone)

        return TwilightTimes(
            astronomicalDawn: astronomicalDawn,
            nauticalDawn: nauticalDawn,
            civilDawn: civilDawn,
            sunrise: sunTimes.sunrise,
            sunset: sunTimes.sunset,
            civilDusk: civilDusk,
            nauticalDusk: nauticalDusk,
            astronomicalDusk: astronomicalDusk
        )
    }

    /// Calculate golden hour and blue hour boundaries for a given date and location.
    /// Returns nil if the location experiences no sunrise/sunset on that date.
    public static func goldenHourTimes(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> GoldenHourTimes? {
        guard sunTimes(date: date, latitude: latitude, longitude: longitude, timeZone: timeZone) != nil else {
            return nil
        }
        return GoldenHourTimes(
            morningBlueStart: sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 96, isSunrise: true, timeZone: timeZone),
            morningBlueEnd: sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 94, isSunrise: true, timeZone: timeZone),
            morningGoldenEnd: sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 84, isSunrise: true, timeZone: timeZone),
            eveningGoldenStart: sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 84, isSunrise: false, timeZone: timeZone),
            eveningGoldenEnd: sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 94, isSunrise: false, timeZone: timeZone),
            eveningBlueEnd: sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: 96, isSunrise: false, timeZone: timeZone)
        )
    }

    /// Time at which the sun's centre crosses `zenith` on `date`, or nil when
    /// it never does that day (polar). 90.833 = sunrise/sunset, 96/102/108 =
    /// civil/nautical/astronomical twilight, 94/84 = blue/golden hour edges.
    public static func eventTime(date: Date, latitude: Double, longitude: Double, zenith: Double, isSunrise: Bool, timeZone: TimeZone = .current) -> Date? {
        sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: zenith, isSunrise: isSunrise, timeZone: timeZone)
    }

    /// Polar-aware time at which the sun crosses `zenith` on `date`. Never nil.
    /// (Ported from Otta, where legal hunting hours need a defined limit.)
    ///
    /// Outside the polar regions this equals the regular event time. When the
    /// crossing does not happen that day, the continuous limit is used:
    /// - Sun stays **above** the zenith all day (polar day / midnight sun for
    ///   sunrise-sunset): dawn = solar noon − 12 h, dusk = solar noon + 12 h,
    ///   i.e. the whole day lies between "sunrise" and "sunset".
    /// - Sun stays **below** the zenith all day (polar night / kaamos /
    ///   mørketid): dawn = dusk = solar noon, i.e. the moment the sun is
    ///   closest to rising. A window such as "sunrise −60 → sunset +60"
    ///   therefore shrinks to solar noon ± 1 h instead of disappearing.
    public static func eventTimeClampingPolar(date: Date, latitude: Double, longitude: Double, zenith: Double, isSunrise: Bool, timeZone: TimeZone = .current) -> Date {
        // Force-unwrap is safe: with clampPolar the helper never returns nil.
        sunTimeForZenith(date: date, latitude: latitude, longitude: longitude, zenith: zenith,
                         isSunrise: isSunrise, timeZone: timeZone, clampPolar: true)!
    }

    /// Calculate sun time for a specific zenith angle
    private static func sunTimeForZenith(date: Date, latitude: Double, longitude: Double, zenith: Double, isSunrise: Bool, timeZone: TimeZone, clampPolar: Bool = false) -> Date? {
        let cal = calendar
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)

        let jd = julianDay(year: year, month: month, day: day)
        let t = (jd - 2451545.0) / 36525.0
        let elements = solarElements(t: t)
        let declin = elements.declin
        let eqTime = elements.eqTime

        let latRad = latitude * rad
        let decRad = declin * rad

        var cosHA = (cos(zenith * rad) / (cos(latRad) * cos(decRad))) - tan(latRad) * tan(decRad)

        if cosHA > 1 || cosHA < -1 {
            guard clampPolar else { return nil }
            // cosHA < -1: sun always above zenith → ha = 180° (±12 h from noon).
            // cosHA > 1: sun always below zenith → ha = 0° (event at solar noon).
            cosHA = min(1, max(-1, cosHA))
        }

        let ha = acos(cosHA) * deg
        let tzOffsetMinutes = Double(timeZone.secondsFromGMT(for: date)) / 60.0
        let solarNoonMinutes = 720 - 4 * longitude - eqTime + tzOffsetMinutes

        let eventMinutes = isSunrise ? solarNoonMinutes - ha * 4 : solarNoonMinutes + ha * 4

        return instant(minutesAfterLocalMidnight: eventMinutes, tzOffsetMinutes: tzOffsetMinutes, on: date, timeZone: timeZone)
    }

    /// Cosine of the hour angle at which the sun reaches `zenith` on the day
    /// `sunTimes` would use. Outside [−1, 1] it never does: > 1 stays below,
    /// < −1 stays above.
    private static func cosHourAngle(date: Date, latitude: Double, zenith: Double) -> Double {
        let cal = calendar
        let jd = julianDay(year: cal.component(.year, from: date),
                           month: cal.component(.month, from: date),
                           day: cal.component(.day, from: date))
        let declin = solarElements(t: (jd - 2451545.0) / 36525.0).declin
        let latRad = latitude * rad
        let decRad = declin * rad
        return (cos(zenith * rad) / (cos(latRad) * cos(decRad))) - tan(latRad) * tan(decRad)
    }

    // MARK: - Solar Elevation and UV Index

    /// Calculate the sun's elevation angle at a specific time
    /// Returns elevation in degrees (positive = above horizon, negative = below)
    public static func solarElevation(at time: Date, latitude: Double, longitude: Double) -> Double {
        let cal = calendar
        let year = cal.component(.year, from: time)
        let month = cal.component(.month, from: time)
        let day = cal.component(.day, from: time)

        let jd = julianDay(year: year, month: month, day: day)
        let t = (jd - 2451545.0) / 36525.0
        let elements = solarElements(t: t)
        let declin = elements.declin
        let eqTime = elements.eqTime

        // Time of day in minutes from midnight UTC
        let utc = TimeZone.gmt
        let components = cal.dateComponents(in: utc, from: time)
        let minutesFromMidnightUTC = Double(components.hour ?? 0) * 60 + Double(components.minute ?? 0) + Double(components.second ?? 0) / 60.0

        // Solar time
        let trueSolarTime = (minutesFromMidnightUTC + eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)

        // Hour angle
        let hourAngle: Double
        if trueSolarTime / 4 < 0 {
            hourAngle = trueSolarTime / 4 + 180
        } else {
            hourAngle = trueSolarTime / 4 - 180
        }

        // Solar zenith angle
        let latRad = latitude * rad
        let decRad = declin * rad
        let haRad = hourAngle * rad

        let cosZenith = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        // Clamp to acos's valid domain; floating-point error can push cosZenith just past ±1
        // (at extreme elevations/latitudes), which would otherwise yield NaN. Matches solarPosition.
        let zenithAngle = acos(min(1, max(-1, cosZenith))) * deg

        // Elevation = 90 - zenith
        return 90 - zenithAngle
    }

    /// Sun position at an instant: where in the sky the sun appears.
    /// Azimuth is measured clockwise from true north (0° = N, 90° = E, 180° = S, 270° = W).
    public struct SunPosition: Sendable, Hashable {
        public let time: Date
        public let elevation: Double  // degrees above horizon (negative = below)
        public let azimuth: Double    // degrees clockwise from true north

        public init(time: Date, elevation: Double, azimuth: Double) {
            self.time = time
            self.elevation = elevation
            self.azimuth = azimuth
        }
    }

    /// Calculate sun azimuth + elevation at a specific time and location.
    /// Used by AR sun-path rendering and any feature that needs sun direction, not just height.
    public static func solarPosition(at time: Date, latitude: Double, longitude: Double) -> SunPosition {
        let cal = calendar
        let year = cal.component(.year, from: time)
        let month = cal.component(.month, from: time)
        let day = cal.component(.day, from: time)

        let jd = julianDay(year: year, month: month, day: day)
        let t = (jd - 2451545.0) / 36525.0
        let elements = solarElements(t: t)
        let declin = elements.declin
        let eqTime = elements.eqTime

        let utc = TimeZone.gmt
        let components = cal.dateComponents(in: utc, from: time)
        let minutesFromMidnightUTC = Double(components.hour ?? 0) * 60 +
                                     Double(components.minute ?? 0) +
                                     Double(components.second ?? 0) / 60.0

        let trueSolarTime = (minutesFromMidnightUTC + eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)

        let hourAngle: Double
        if trueSolarTime / 4 < 0 {
            hourAngle = trueSolarTime / 4 + 180
        } else {
            hourAngle = trueSolarTime / 4 - 180
        }

        let latRad = latitude * rad
        let decRad = declin * rad
        let haRad = hourAngle * rad

        let cosZenith = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        let zenithAngle = acos(min(1, max(-1, cosZenith))) * deg
        let elevation = 90 - zenithAngle

        // Azimuth from NOAA solar calculator convention (clockwise from north)
        let elevRad = elevation * rad
        let cosLat = cos(latRad)
        let cosElev = cos(elevRad)
        var azimuth: Double
        if abs(cosLat) < 1e-9 || abs(cosElev) < 1e-9 {
            // Sun directly overhead or observer at pole — azimuth undefined; default south
            azimuth = 180
        } else {
            var cosAz = (sin(decRad) - sin(elevRad) * sin(latRad)) / (cosElev * cosLat)
            cosAz = min(1, max(-1, cosAz))
            let azDeg = acos(cosAz) * deg
            azimuth = hourAngle > 0 ? (360 - azDeg) : azDeg
        }
        // Wrap to [0, 360)
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }

        return SunPosition(time: time, elevation: elevation, azimuth: azimuth)
    }

    /// Sample the sun's path across a full local day at fixed intervals.
    /// Used to draw the arc in AR or 2D sky diagrams.
    public static func sunPath(date: Date, latitude: Double, longitude: Double, intervalMinutes: Int = 10, timeZone: TimeZone = .current) -> [SunPosition] {
        var localCal = calendar
        localCal.timeZone = timeZone
        let startOfDay = localCal.startOfDay(for: date)
        let stride = max(1, intervalMinutes)
        let stepCount = (24 * 60) / stride

        return (0...stepCount).map { i in
            let time = startOfDay.addingTimeInterval(TimeInterval(i * stride * 60))
            return solarPosition(at: time, latitude: latitude, longitude: longitude)
        }
    }

    /// Calculate maximum solar elevation for a day (at solar noon)
    public static func maxSolarElevation(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> Double? {
        guard let sunTimes = sunTimes(date: date, latitude: latitude, longitude: longitude, timeZone: timeZone) else {
            return nil
        }
        return solarElevation(at: sunTimes.solarNoon, latitude: latitude, longitude: longitude)
    }

    /// Estimate UV index based on solar elevation angle
    /// This is a simplified clear-sky estimate; actual UV depends on clouds, ozone, altitude, etc.
    public static func estimateUVIndex(elevation: Double) -> Double {
        guard elevation > 0 else { return 0 }

        // Simplified formula based on solar elevation
        // UV index roughly proportional to sin(elevation)
        // Max UV around 12 at zenith in tropical regions
        let sinElevation = sin(elevation * rad)
        let baseUV = 12.0 * sinElevation

        // Clamp to reasonable range
        return max(0, min(baseUV, 12))
    }

    /// Get UV index level classification
    public static func uvLevel(from uvIndex: Double) -> UVLevel {
        UVLevel.from(uvIndex: uvIndex)
    }

    // MARK: - Subsolar Point

    /// The point on Earth where the sun is directly overhead, in degrees
    /// (latitude = solar declination; longitude from UTC time + equation of time).
    /// Drives the sunlight globe visualization.
    public struct SubsolarPoint: Sendable, Hashable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public static func subsolarPoint(date: Date) -> SubsolarPoint {
        let utc = TimeZone.gmt
        let comps = calendar.dateComponents(in: utc, from: date)
        let jd = julianDay(year: comps.year ?? 2000, month: comps.month ?? 1, day: comps.day ?? 1)
        let t = (jd - 2451545.0) / 36525.0
        let elements = solarElements(t: t)

        let minutesUTC = Double(comps.hour ?? 0) * 60 + Double(comps.minute ?? 0) + Double(comps.second ?? 0) / 60.0
        // Solar noon is at longitude where true solar time is 720 minutes.
        var lon = (720 - minutesUTC - elements.eqTime) / 4
        while lon < -180 { lon += 360 }
        while lon > 180 { lon -= 360 }
        return SubsolarPoint(latitude: elements.declin, longitude: lon)
    }

    /// Hours of daylight at a latitude on a date — depends only on latitude and
    /// solar declination. 0 for polar night, 24 for midnight sun.
    public static func daylightHours(latitude: Double, date: Date) -> Double {
        let comps = calendar.dateComponents(in: TimeZone.gmt, from: date)
        let jd = julianDay(year: comps.year ?? 2000, month: comps.month ?? 1, day: comps.day ?? 1)
        let t = (jd - 2451545.0) / 36525.0
        let declin = solarElements(t: t).declin
        let cosHA = (cos(90.833 * rad) / (cos(latitude * rad) * cos(declin * rad))) - tan(latitude * rad) * tan(declin * rad)
        if cosHA < -1 { return 24 }
        if cosHA > 1 { return 0 }
        return acos(cosHA) * deg * 2 / 15
    }

    // MARK: - Solar Elements Helper

    private struct SolarElements {
        let declin: Double
        let eqTime: Double
    }

    /// Compute solar declination and equation of time from a Julian century value.
    /// `sunTimes`, `sunTimeForZenith`, `solarElevation`, and `solarPosition`
    /// all need these two quantities before diverging into their own geometry.
    private static func solarElements(t: Double) -> SolarElements {
        let l0 = (280.46646 + t * (36000.76983 + 0.0003032 * t)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let mRad = m * rad
        let c = sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
                sin(2 * mRad) * (0.019993 - 0.000101 * t) +
                sin(3 * mRad) * 0.000289
        let sunLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = sunLong - 0.00569 - 0.00478 * sin(omega * rad)
        let obliq0 = 23.0 + (26.0 + (21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
        let obliq = obliq0 + 0.00256 * cos(omega * rad)
        let declin = asin(sin(obliq * rad) * sin(lambda * rad)) * deg
        let y = tan(obliq * rad / 2) * tan(obliq * rad / 2)
        let l0Rad = l0 * rad
        let eqTime = 4 * deg * (y * sin(2 * l0Rad) - 2 * e * sin(mRad) + 4 * e * y * sin(mRad) * cos(2 * l0Rad) -
                                 0.5 * y * y * sin(4 * l0Rad) - 1.25 * e * e * sin(2 * mRad))
        return SolarElements(declin: declin, eqTime: eqTime)
    }

    // MARK: - Julian Date Conversions

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month

        if m <= 2 {
            y -= 1
            m += 12
        }

        let a = y / 100
        let b = 2 - a + a / 4

        return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1))) + Double(day) + Double(b) - 1524.5
    }

    private static func julianToDate(_ jd: Double) -> Date {
        let z = Int(jd + 0.5)
        let f = jd + 0.5 - Double(z)

        let a: Int
        if z < 2299161 {
            a = z
        } else {
            let alpha = Int((Double(z) - 1867216.25) / 36524.25)
            a = z + 1 + alpha - alpha / 4
        }

        let b = a + 1524
        let c = Int((Double(b) - 122.1) / 365.25)
        let d = Int(365.25 * Double(c))
        let e = Int(Double(b - d) / 30.6001)

        let day = b - d - Int(30.6001 * Double(e))
        let month = e < 14 ? e - 1 : e - 13
        let year = month > 2 ? c - 4716 : c - 4715

        let dayFraction = f
        let hours = Int(dayFraction * 24)
        let minutes = Int((dayFraction * 24 - Double(hours)) * 60)

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hours
        components.minute = minutes
        components.timeZone = TimeZone(identifier: "UTC")

        return calendar.date(from: components) ?? Date()
    }
}
