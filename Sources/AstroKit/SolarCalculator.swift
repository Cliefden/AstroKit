import Foundation

/// Calculates solar events (equinoxes, solstices) and sunrise/sunset times.
/// Based on the NOAA solar calculator and Jean Meeus "Astronomical Algorithms".
///
/// API ported from Equinox (`Shared/SolarCalculator.swift`), with additions for
/// Lunker (`polarState`, `twilightBoundaries`) and Otta
/// (`eventTimeClampingPolar`). Since 0.2 the numbers follow Lunker's
/// implementation: per-day results are anchored to the location's calendar
/// day with declination/equation of time taken at solar noon, and
/// position/elevation/subsolar queries evaluate them at the exact instant.
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
    private static let utcTimeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
    /// Gregorian calendar pinned to UTC, so results never depend on the device
    /// calendar or time zone.
    private static let gregorianUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utcTimeZone
        return cal
    }()
    /// A Gregorian calendar in `timeZone`. Per-day results are anchored to the
    /// *location's* calendar day.
    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
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
        let year = gregorianUTC.component(.year, from: date)
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
        let year = gregorianUTC.component(.year, from: date)
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

    // MARK: - Day Anchoring (from Lunker)

    /// One local calendar day at a location, anchored for NOAA event math.
    private struct DayAnchor {
        /// 00:00 UTC of the Gregorian date whose UTC-minute event times land
        /// on the location's local calendar day.
        let midnightUTC: Date
        /// Declination / equation of time evaluated at that day's solar noon.
        let elements: SolarElements
    }

    /// Anchor the location's local calendar day containing `date`.
    ///
    /// NOAA gives event times as *UTC* minutes after 00:00 UTC of a date
    /// (`720 − 4·lon − eqTime ± 4·ha`). Adding those to UTC midnight is exact
    /// on every day, including 23 h/25 h DST-transition days. The zone only
    /// picks *which* date (a whole-day shift for zones far from their
    /// meridian, e.g. UTC+14 at −157°), so the result does not depend on the
    /// time of day passed in, nor on the device time zone. Declination and the
    /// equation of time are evaluated at that day's solar noon.
    private static func dayAnchor(for date: Date, longitude: Double, timeZone: TimeZone) -> DayAnchor {
        let comps = calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        let jd0 = julianDay(year: comps.year ?? 2000, month: comps.month ?? 1, day: comps.day ?? 1)
        // Local wall-clock minute of solar noon if anchored on this UTC date;
        // shift whole days until it falls within the local date.
        let noonUTCMinutes = 720 - 4 * longitude
        let offsetMinutes = Double(timeZone.secondsFromGMT(for: date)) / 60.0
        let dayShift = -(((noonUTCMinutes + offsetMinutes) / 1440).rounded(.down))
        let jd = jd0 + dayShift
        return DayAnchor(
            midnightUTC: Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400),
            elements: solarElements(julianDay: jd + (720 - 4 * longitude) / 1440)
        )
    }

    /// Cosine of the hour angle at which the sun's centre reaches `zenith`.
    /// Outside [−1, 1] it never does: > 1 stays below, < −1 stays above.
    private static func cosHourAngle(zenith: Double, latitude: Double, declination: Double) -> Double {
        let latRad = latitude * rad
        let decRad = declination * rad
        return (cos(zenith * rad) / (cos(latRad) * cos(decRad))) - tan(latRad) * tan(decRad)
    }

    /// Event instant for hour angle `ha` (degrees; negative = morning).
    private static func instant(_ anchor: DayAnchor, longitude: Double, hourAngle ha: Double) -> Date {
        let utcMinutes = 720 - 4 * longitude - anchor.elements.eqTime + 4 * ha
        return anchor.midnightUTC.addingTimeInterval(utcMinutes * 60)
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

    /// Non-nil when the location has no sunrise/sunset on this date. Same
    /// answer as `polarState` (Equinox naming).
    public static func polarCondition(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> PolarCondition? {
        switch polarState(date: date, latitude: latitude, longitude: longitude, timeZone: timeZone) {
        case .polarDay: return .midnightSun
        case .polarNight: return .polarNight
        case nil: return nil
        }
    }

    /// Whether the sun stays up (`.polarDay`) or down (`.polarNight`) all day,
    /// judged by the same refracted-horizon threshold (zenith 90.833°) and the
    /// same declination as `sunTimes`, so it is non-nil exactly when `sunTimes`
    /// is nil. Returns nil when the sun rises and sets normally that day.
    public static func polarState(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> PolarState? {
        let anchor = dayAnchor(for: date, longitude: longitude, timeZone: timeZone)
        let cosHA = cosHourAngle(zenith: 90.833, latitude: latitude, declination: anchor.elements.declin)
        if cosHA < -1 { return .polarDay }
        if cosHA > 1 { return .polarNight }
        return nil
    }

    /// Sunrise, sunset and solar noon on the local calendar day (in
    /// `timeZone`) containing `date`. Any time of day within that day gives
    /// the same result. Returns nil during polar day or polar night.
    public static func sunTimes(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> SunTimes? {
        sunTimes(anchor: dayAnchor(for: date, longitude: longitude, timeZone: timeZone), latitude: latitude, longitude: longitude)
    }

    private static func sunTimes(anchor: DayAnchor, latitude: Double, longitude: Double) -> SunTimes? {
        let cosHA = cosHourAngle(zenith: 90.833, latitude: latitude, declination: anchor.elements.declin)
        if cosHA > 1 || cosHA < -1 { return nil }
        let ha = acos(cosHA) * deg
        return SunTimes(
            sunrise: instant(anchor, longitude: longitude, hourAngle: -ha),
            sunset: instant(anchor, longitude: longitude, hourAngle: ha),
            solarNoon: instant(anchor, longitude: longitude, hourAngle: 0)
        )
    }

    // MARK: - Twilight Calculations

    /// Twilight boundaries for one local day with every field optional
    /// (Lunker's shape). During polar night `sunrise`/`sunset` are nil yet
    /// civil or nautical twilight may still occur; during polar day the sun
    /// may never sink low enough for some (or any) boundaries.
    public struct TwilightBoundaries: Sendable, Hashable {
        public let astronomicalDawn: Date?
        public let nauticalDawn: Date?
        public let civilDawn: Date?
        public let sunrise: Date?
        public let sunset: Date?
        public let civilDusk: Date?
        public let nauticalDusk: Date?
        public let astronomicalDusk: Date?

        public init(astronomicalDawn: Date?, nauticalDawn: Date?, civilDawn: Date?, sunrise: Date?, sunset: Date?,
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

    /// Calculate all twilight times for a given date and location.
    /// Twilight zenith angles:
    /// - Civil: 96° (sun 6° below horizon)
    /// - Nautical: 102° (sun 12° below horizon)
    /// - Astronomical: 108° (sun 18° below horizon)
    ///
    /// Returns nil when the sun does not rise that day, because
    /// `TwilightTimes.sunrise` is non-optional. Use `twilightBoundaries` to
    /// also get twilight during polar night.
    public static func twilightTimes(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> TwilightTimes? {
        let anchor = dayAnchor(for: date, longitude: longitude, timeZone: timeZone)
        guard let sunTimes = sunTimes(anchor: anchor, latitude: latitude, longitude: longitude) else {
            return nil
        }
        func time(_ zenith: Double, _ isSunrise: Bool) -> Date? {
            sunTimeForZenith(anchor: anchor, latitude: latitude, longitude: longitude, zenith: zenith, isSunrise: isSunrise)
        }
        return TwilightTimes(
            astronomicalDawn: time(108, true),
            nauticalDawn: time(102, true),
            civilDawn: time(96, true),
            sunrise: sunTimes.sunrise,
            sunset: sunTimes.sunset,
            civilDusk: time(96, false),
            nauticalDusk: time(102, false),
            astronomicalDusk: time(108, false)
        )
    }

    /// Twilight boundaries for a given date and location, reported
    /// individually (Lunker's `twilightTimes`). Twilight is still reported
    /// during polar night, when `sunrise`/`sunset` are nil. Returns nil only
    /// when no boundary at all is crossed that day.
    public static func twilightBoundaries(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> TwilightBoundaries? {
        let anchor = dayAnchor(for: date, longitude: longitude, timeZone: timeZone)
        func time(_ zenith: Double, _ isSunrise: Bool) -> Date? {
            sunTimeForZenith(anchor: anchor, latitude: latitude, longitude: longitude, zenith: zenith, isSunrise: isSunrise)
        }
        let st = sunTimes(anchor: anchor, latitude: latitude, longitude: longitude)
        let result = TwilightBoundaries(
            astronomicalDawn: time(108, true),
            nauticalDawn: time(102, true),
            civilDawn: time(96, true),
            sunrise: st?.sunrise,
            sunset: st?.sunset,
            civilDusk: time(96, false),
            nauticalDusk: time(102, false),
            astronomicalDusk: time(108, false)
        )
        let all: [Date?] = [result.astronomicalDawn, result.nauticalDawn, result.civilDawn, result.sunrise,
                            result.sunset, result.civilDusk, result.nauticalDusk, result.astronomicalDusk]
        return all.contains { $0 != nil } ? result : nil
    }

    /// Calculate golden hour and blue hour boundaries for a given date and location.
    /// Boundaries are reported individually, so blue hour still appears on
    /// polar-night days with civil twilight. Returns nil only when the sun
    /// crosses none of the boundaries that day.
    public static func goldenHourTimes(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> GoldenHourTimes? {
        let anchor = dayAnchor(for: date, longitude: longitude, timeZone: timeZone)
        func time(_ zenith: Double, _ isSunrise: Bool) -> Date? {
            sunTimeForZenith(anchor: anchor, latitude: latitude, longitude: longitude, zenith: zenith, isSunrise: isSunrise)
        }
        let result = GoldenHourTimes(
            morningBlueStart: time(96, true),
            morningBlueEnd: time(94, true),
            morningGoldenEnd: time(84, true),
            eveningGoldenStart: time(84, false),
            eveningGoldenEnd: time(94, false),
            eveningBlueEnd: time(96, false)
        )
        let all: [Date?] = [result.morningBlueStart, result.morningBlueEnd, result.morningGoldenEnd,
                            result.eveningGoldenStart, result.eveningGoldenEnd, result.eveningBlueEnd]
        return all.contains { $0 != nil } ? result : nil
    }

    /// Time at which the sun's centre crosses `zenith` on `date`, or nil when
    /// it never does that day (polar). 90.833 = sunrise/sunset, 96/102/108 =
    /// civil/nautical/astronomical twilight, 94/84 = blue/golden hour edges.
    public static func eventTime(date: Date, latitude: Double, longitude: Double, zenith: Double, isSunrise: Bool, timeZone: TimeZone = .current) -> Date? {
        sunTimeForZenith(anchor: dayAnchor(for: date, longitude: longitude, timeZone: timeZone),
                         latitude: latitude, longitude: longitude, zenith: zenith, isSunrise: isSunrise)
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
        sunTimeForZenith(anchor: dayAnchor(for: date, longitude: longitude, timeZone: timeZone),
                         latitude: latitude, longitude: longitude, zenith: zenith,
                         isSunrise: isSunrise, clampPolar: true)!
    }

    /// Sun time for a specific zenith angle on an anchored day.
    private static func sunTimeForZenith(anchor: DayAnchor, latitude: Double, longitude: Double, zenith: Double, isSunrise: Bool, clampPolar: Bool = false) -> Date? {
        var cosHA = cosHourAngle(zenith: zenith, latitude: latitude, declination: anchor.elements.declin)
        if cosHA > 1 || cosHA < -1 {
            guard clampPolar else { return nil }
            // cosHA < -1: sun always above zenith → ha = 180° (±12 h from noon).
            // cosHA > 1: sun always below zenith → ha = 0° (event at solar noon).
            cosHA = min(1, max(-1, cosHA))
        }
        let ha = acos(cosHA) * deg
        return instant(anchor, longitude: longitude, hourAngle: isSunrise ? -ha : ha)
    }

    // MARK: - Solar Elevation and UV Index

    /// Calculate the sun's elevation angle at a specific time
    /// Returns elevation in degrees (positive = above horizon, negative = below).
    /// Declination and equation of time are evaluated at the instant itself.
    public static func solarElevation(at time: Date, latitude: Double, longitude: Double) -> Double {
        let elements = solarElements(at: time)
        let components = gregorianUTC.dateComponents([.hour, .minute, .second], from: time)
        let minutesFromMidnightUTC = Double(components.hour ?? 0) * 60 +
                                    Double(components.minute ?? 0) +
                                    Double(components.second ?? 0) / 60.0
        let trueSolarTime = (minutesFromMidnightUTC + elements.eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        let hourAngle = trueSolarTime / 4 < 0 ? trueSolarTime / 4 + 180 : trueSolarTime / 4 - 180
        let latRad = latitude * rad
        let decRad = elements.declin * rad
        let haRad = hourAngle * rad
        let cosZenith = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        // Clamp to acos's valid domain; floating-point error can push cosZenith just past ±1.
        return 90 - acos(min(1.0, max(-1.0, cosZenith))) * deg
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
        let elements = solarElements(at: time)
        let components = gregorianUTC.dateComponents([.hour, .minute, .second], from: time)
        let minutesFromMidnightUTC = Double(components.hour ?? 0) * 60 +
                                     Double(components.minute ?? 0) +
                                     Double(components.second ?? 0) / 60.0
        let trueSolarTime = (minutesFromMidnightUTC + elements.eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        let hourAngle = trueSolarTime / 4 < 0 ? trueSolarTime / 4 + 180 : trueSolarTime / 4 - 180
        let latRad = latitude * rad
        let decRad = elements.declin * rad
        let haRad = hourAngle * rad
        let cosZenith = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        let elevation = 90 - acos(min(1, max(-1, cosZenith))) * deg

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
    /// Used to draw the arc in AR or 2D sky diagrams. Spans local midnight to
    /// the next local midnight, so 23 h/25 h DST-transition days are covered
    /// exactly (the final sample may fall short of the next midnight).
    public static func sunPath(date: Date, latitude: Double, longitude: Double, intervalMinutes: Int = 10, timeZone: TimeZone = .current) -> [SunPosition] {
        let cal = calendar(in: timeZone)
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        let stride = max(1, intervalMinutes)
        let dayMinutes = Int((endOfDay.timeIntervalSince(startOfDay) / 60).rounded())
        let stepCount = dayMinutes / stride

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

    /// Declination and equation of time are evaluated at the instant itself.
    /// Longitude is in [−180, 180).
    public static func subsolarPoint(date: Date) -> SubsolarPoint {
        let elements = solarElements(at: date)
        let comps = gregorianUTC.dateComponents([.hour, .minute, .second], from: date)
        let utcHours = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60 + Double(comps.second ?? 0) / 3600
        // Longitude where true solar time is 12 h.
        var lon = -15.0 * (utcHours + elements.eqTime / 60.0 - 12.0)
        lon = lon.truncatingRemainder(dividingBy: 360)
        if lon < -180 { lon += 360 }
        if lon >= 180 { lon -= 360 }
        return SubsolarPoint(latitude: elements.declin, longitude: lon)
    }

    /// Hours of daylight at a latitude on a date — depends only on latitude and
    /// solar declination (evaluated at 0 h UT of the UTC date). 0 for polar
    /// night, 24 for midnight sun.
    public static func daylightHours(latitude: Double, date: Date) -> Double {
        let comps = gregorianUTC.dateComponents([.year, .month, .day], from: date)
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

    /// Solar elements at Julian day `jd`.
    private static func solarElements(julianDay jd: Double) -> SolarElements {
        solarElements(t: (jd - 2451545.0) / 36525.0)
    }

    /// Solar elements at an exact instant (position/elevation/subsolar queries).
    private static func solarElements(at instant: Date) -> SolarElements {
        solarElements(julianDay: instant.timeIntervalSince1970 / 86_400.0 + 2_440_587.5)
    }

    /// Compute solar declination and equation of time from a Julian century value.
    /// Sun times, solar elevation/position and the subsolar point all need
    /// these two quantities before diverging into their own geometry.
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

        return gregorianUTC.date(from: components) ?? Date()
    }
}
