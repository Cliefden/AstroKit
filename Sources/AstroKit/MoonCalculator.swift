import Foundation

/// Calculates lunar data including moon phases, moonrise/moonset, distance, and zodiac position.
/// Based on Jean Meeus "Astronomical Algorithms".
///
/// API ported from Equinox (`Shared/MoonCalculator.swift`), with additions for
/// Otta (`transits`, `moonPosition`, `MoonPhaseInfo.phaseAngle` /
/// `illuminatedFraction`) and Lunker (`dayPhase`, `MoonPhase.symbolName` /
/// `isWaxing`, `upcomingEclipses(after:limit:calendar:)`,
/// `eclipseTableCoverageEnd`, `EclipseEvent: Identifiable`). Since 0.2 the
/// numbers follow Lunker's implementation (elongation-based phase, Meeus
/// distance series, DST-exact last-crossing moon times, UT eclipse instants).
public struct MoonCalculator: Sendable {

    // MARK: - Moon Phase Types

    public enum MoonPhase: String, CaseIterable, Sendable, Hashable {
        case newMoon = "New Moon"
        case waxingCrescent = "Waxing Crescent"
        case firstQuarter = "First Quarter"
        case waxingGibbous = "Waxing Gibbous"
        case fullMoon = "Full Moon"
        case waningGibbous = "Waning Gibbous"
        case lastQuarter = "Last Quarter"
        case waningCrescent = "Waning Crescent"

        /// Equinox's generic moon symbols (kept for compatibility). For a
        /// symbol that shows the actual phase, use `symbolName`.
        public var icon: String {
            switch self {
            case .newMoon: return "moon.fill"
            case .waxingCrescent: return "moon.stars.fill"
            case .firstQuarter: return "moon.haze.fill"
            case .waxingGibbous: return "moon.haze.fill"
            case .fullMoon: return "moon.circle.fill"
            case .waningGibbous: return "moon.haze.fill"
            case .lastQuarter: return "moon.haze.fill"
            case .waningCrescent: return "moon.stars.fill"
            }
        }

        /// The phase-accurate `moonphase.*` SF Symbol (iOS 17 / watchOS 10).
        public var symbolName: String {
            switch self {
            case .newMoon: return "moonphase.new.moon"
            case .waxingCrescent: return "moonphase.waxing.crescent"
            case .firstQuarter: return "moonphase.first.quarter"
            case .waxingGibbous: return "moonphase.waxing.gibbous"
            case .fullMoon: return "moonphase.full.moon"
            case .waningGibbous: return "moonphase.waning.gibbous"
            case .lastQuarter: return "moonphase.last.quarter"
            case .waningCrescent: return "moonphase.waning.crescent"
            }
        }

        /// Lit fraction growing (new → full), for drawing the terminator.
        public var isWaxing: Bool {
            switch self {
            case .newMoon, .waxingCrescent, .firstQuarter, .waxingGibbous:
                return true
            case .fullMoon, .waningGibbous, .lastQuarter, .waningCrescent:
                return false
            }
        }

        /// Localized display name. `rawValue` is the English source key, looked
        /// up in the host app's main-bundle string catalog.
        public var localizedName: String { NSLocalizedString(rawValue, bundle: .main, comment: "Moon phase name") }

        public var description: String {
            switch self {
            case .newMoon: return String(localized: "The Moon is between Earth and the Sun", bundle: .main)
            case .waxingCrescent: return String(localized: "The Moon is growing, less than half lit", bundle: .main)
            case .firstQuarter: return String(localized: "The right half of the Moon is lit", bundle: .main)
            case .waxingGibbous: return String(localized: "The Moon is growing, more than half lit", bundle: .main)
            case .fullMoon: return String(localized: "The Moon is fully illuminated", bundle: .main)
            case .waningGibbous: return String(localized: "The Moon is shrinking, more than half lit", bundle: .main)
            case .lastQuarter: return String(localized: "The left half of the Moon is lit", bundle: .main)
            case .waningCrescent: return String(localized: "The Moon is shrinking, less than half lit", bundle: .main)
            }
        }
    }

    public enum ZodiacConstellation: String, CaseIterable, Sendable, Hashable {
        case aries = "Aries"
        case taurus = "Taurus"
        case gemini = "Gemini"
        case cancer = "Cancer"
        case leo = "Leo"
        case virgo = "Virgo"
        case libra = "Libra"
        case scorpio = "Scorpio"
        case sagittarius = "Sagittarius"
        case capricorn = "Capricorn"
        case aquarius = "Aquarius"
        case pisces = "Pisces"

        public var symbol: String {
            switch self {
            case .aries: return "♈"
            case .taurus: return "♉"
            case .gemini: return "♊"
            case .cancer: return "♋"
            case .leo: return "♌"
            case .virgo: return "♍"
            case .libra: return "♎"
            case .scorpio: return "♏"
            case .sagittarius: return "♐"
            case .capricorn: return "♑"
            case .aquarius: return "♒"
            case .pisces: return "♓"
            }
        }

        /// Localized constellation name. `rawValue` is the English source key.
        public var localizedName: String { NSLocalizedString(rawValue, bundle: .main, comment: "Zodiac constellation name") }

        /// English element key used for logic/colour mapping — do not display directly.
        public var element: String {
            switch self {
            case .aries, .leo, .sagittarius: return "Fire"
            case .taurus, .virgo, .capricorn: return "Earth"
            case .gemini, .libra, .aquarius: return "Air"
            case .cancer, .scorpio, .pisces: return "Water"
            }
        }

        /// Localized element name for display.
        public var localizedElement: String { NSLocalizedString(element, bundle: .main, comment: "Zodiac element (Fire/Earth/Air/Water)") }
    }

    public enum LunarDistanceStatus: String, Sendable, Hashable, CaseIterable {
        case perigee = "Perigee"
        case apogee = "Apogee"
        case nearPerigee = "Near Perigee"
        case nearApogee = "Near Apogee"
        case normal = "Normal"

        /// Localized display name. `rawValue` is the English source key.
        public var localizedName: String { NSLocalizedString(rawValue, bundle: .main, comment: "Lunar distance status") }

        public var description: String {
            switch self {
            case .perigee: return String(localized: "Closest point to Earth", bundle: .main)
            case .apogee: return String(localized: "Farthest point from Earth", bundle: .main)
            case .nearPerigee: return String(localized: "Close to Earth", bundle: .main)
            case .nearApogee: return String(localized: "Far from Earth", bundle: .main)
            case .normal: return String(localized: "Average distance", bundle: .main)
            }
        }
    }

    public struct EclipseEvent: Sendable, Hashable, Identifiable {
        public enum EclipseType: String, Sendable, Hashable, CaseIterable {
            case lunarTotal = "Total Lunar Eclipse"
            case lunarPartial = "Partial Lunar Eclipse"
            case lunarPenumbral = "Penumbral Lunar Eclipse"
            case solarTotal = "Total Solar Eclipse"
            case solarPartial = "Partial Solar Eclipse"
            case solarAnnular = "Annular Solar Eclipse"
            case solarHybrid = "Hybrid Solar Eclipse"

            /// Localized display name. `rawValue` is the English source key.
            public var localizedName: String { NSLocalizedString(rawValue, bundle: .main, comment: "Eclipse type") }

            public var icon: String {
                switch self {
                case .lunarTotal, .lunarPartial, .lunarPenumbral:
                    return "moon.circle"
                case .solarTotal, .solarPartial, .solarAnnular, .solarHybrid:
                    return "sun.max.trianglebadge.exclamationmark"
                }
            }

            public var isLunar: Bool {
                switch self {
                case .lunarTotal, .lunarPartial, .lunarPenumbral: return true
                default: return false
                }
            }
        }

        public let type: EclipseType
        public let date: Date
        public let visibility: String

        public init(type: EclipseType, date: Date, visibility: String) {
            self.type = type
            self.date = date
            self.visibility = visibility
        }

        /// Stable identity: each known eclipse has a unique type+date, so this
        /// survives recomputation (unlike a positional index or a fresh UUID).
        public var id: String { "\(type.rawValue)@\(date.timeIntervalSinceReferenceDate)" }
    }

    // MARK: - Result Structs

    public struct MoonTimes: Sendable, Hashable {
        public let moonrise: Date?
        public let moonset: Date?
        public let transitTime: Date?

        public init(moonrise: Date?, moonset: Date?, transitTime: Date?) {
            self.moonrise = moonrise
            self.moonset = moonset
            self.transitTime = transitTime
        }
    }

    public struct MoonPhaseInfo: Sendable, Hashable {
        public let phase: MoonPhase
        /// Illuminated fraction of the disc, 0 (new) … 1 (full).
        public let illumination: Double
        /// Days since the last new moon, 0 … ~29.53.
        public let age: Double
        public let nextNewMoon: Date
        public let nextFullMoon: Date
        public let synodicMonth: Double
        /// Sun→moon elongation in ecliptic longitude, 0°…360°
        /// (0 = new, 90 = first quarter, 180 = full, 270 = last quarter).
        /// `illumination == (1 - cos(phaseAngle)) / 2`.
        public let phaseAngle: Double

        public init(phase: MoonPhase, illumination: Double, age: Double, nextNewMoon: Date, nextFullMoon: Date,
                    synodicMonth: Double, phaseAngle: Double) {
            self.phase = phase
            self.illumination = illumination
            self.age = age
            self.nextNewMoon = nextNewMoon
            self.nextFullMoon = nextFullMoon
            self.synodicMonth = synodicMonth
            self.phaseAngle = phaseAngle
        }

        /// Otta's spelling of `illumination`.
        public var illuminatedFraction: Double { illumination }
    }

    public struct LunarPosition: Sendable, Hashable {
        public let constellation: ZodiacConstellation
        public let eclipticLongitude: Double
        public let rightAscension: Double
        public let declination: Double
        public let altitude: Double
        public let azimuth: Double

        public init(constellation: ZodiacConstellation, eclipticLongitude: Double, rightAscension: Double,
                    declination: Double, altitude: Double, azimuth: Double) {
            self.constellation = constellation
            self.eclipticLongitude = eclipticLongitude
            self.rightAscension = rightAscension
            self.declination = declination
            self.altitude = altitude
            self.azimuth = azimuth
        }
    }

    public struct LunarDistanceInfo: Sendable, Hashable {
        public let distanceKm: Double
        public let distanceStatus: LunarDistanceStatus
        public let percentOfAverage: Double
        public let nextPerigee: Date
        public let nextApogee: Date
        public let isSupermoon: Bool

        public init(distanceKm: Double, distanceStatus: LunarDistanceStatus, percentOfAverage: Double,
                    nextPerigee: Date, nextApogee: Date, isSupermoon: Bool) {
            self.distanceKm = distanceKm
            self.distanceStatus = distanceStatus
            self.percentOfAverage = percentOfAverage
            self.nextPerigee = nextPerigee
            self.nextApogee = nextApogee
            self.isSupermoon = isSupermoon
        }
    }

    /// Where the moon appears in the sky at an instant (mirrors
    /// `SolarCalculator.SunPosition`). Azimuth clockwise from true north.
    public struct MoonPosition: Sendable, Hashable {
        public let time: Date
        public let elevation: Double  // degrees above horizon (negative = below)
        public let azimuth: Double    // degrees clockwise from true north

        public init(time: Date, elevation: Double, azimuth: Double) {
            self.time = time
            self.elevation = elevation
            self.azimuth = azimuth
        }
    }

    /// Meridian transits within one local day: `upper` = moon highest
    /// (overhead, the primary solunar major period); `lower` = moon lowest
    /// (underfoot).
    public struct MoonTransits: Sendable, Hashable {
        public let upper: Date?
        public let lower: Date?

        public init(upper: Date?, lower: Date?) {
            self.upper = upper
            self.lower = lower
        }
    }

    // MARK: - Constants

    /// Gregorian/UTC calendar for astronomical date math. `Calendar.current`
    /// may be non-Gregorian (ar-SA, th-TH, ja-JP…) or in an unrelated zone.
    private static let gregorianUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return cal
    }()
    private static let rad = Double.pi / 180
    private static let deg = 180 / Double.pi
    /// Average lunar (synodic) month in days.
    public static let synodicMonth = 29.530588853
    private static let averageDistance = 384400.0 // Average Moon distance in km
    private static let perigeeDistance = 356500.0 // Approximate perigee
    private static let apogeeDistance = 406700.0 // Approximate apogee

    // MARK: - Moon Phase Calculations

    /// The phase that represents a whole local day: sampled at its midday, so
    /// a phase change late in the evening doesn't relabel the day.
    /// `dayStart` is the location's midnight.
    public static func dayPhase(for dayStart: Date) -> MoonPhaseInfo {
        moonPhase(for: dayStart.addingTimeInterval(12 * 3600))
    }

    /// Calculate moon phase information for a given date.
    ///
    /// Illumination, age, phase name and the next new/full moon all derive
    /// from the same sun→moon elongation, so the label never disagrees with
    /// the lit fraction.
    public static func moonPhase(for date: Date) -> MoonPhaseInfo {
        let jd = julianDay(from: date)
        let t = (jd - 2451545.0) / 36525.0

        // === Calculate Moon's ecliptic longitude ===
        let Lp = (218.3164477 + 481267.88123421 * t).truncatingRemainder(dividingBy: 360)
        let D = (297.8501921 + 445267.1114034 * t).truncatingRemainder(dividingBy: 360)
        let M = (134.9633964 + 477198.8675055 * t).truncatingRemainder(dividingBy: 360)
        let Ms = (357.5291092 + 35999.0502909 * t).truncatingRemainder(dividingBy: 360)

        let moonLonCorrection = 6.289 * sin(M * rad)
            - 1.274 * sin((2 * D - M) * rad)
            + 0.658 * sin(2 * D * rad)
            - 0.214 * sin(2 * M * rad)
            - 0.186 * sin(Ms * rad)

        var moonLon = Lp + moonLonCorrection
        moonLon = moonLon.truncatingRemainder(dividingBy: 360)
        if moonLon < 0 { moonLon += 360 }

        // === Calculate Sun's ecliptic longitude ===
        let sunMeanLon = (280.46646 + 36000.76983 * t).truncatingRemainder(dividingBy: 360)
        let sunEquationOfCenter = (1.914602 - 0.004817 * t) * sin(Ms * rad)
            + 0.019993 * sin(2 * Ms * rad)

        var sunLon = sunMeanLon + sunEquationOfCenter
        sunLon = sunLon.truncatingRemainder(dividingBy: 360)
        if sunLon < 0 { sunLon += 360 }

        // === Calculate elongation (Moon - Sun) ===
        var elongation = moonLon - sunLon
        if elongation < 0 { elongation += 360 }

        // Illumination from elongation: k = (1 - cos(elongation)) / 2
        let illumination = (1 - cos(elongation * rad)) / 2

        // Age, phase name and next-phase dates come from the SAME elongation
        // that drives illumination (0° = new, 180° = full, sweeping 360° over
        // one synodic month).
        let normalizedAge = (elongation / 360) * synodicMonth

        // Determine phase name
        let phase = phaseFromAge(normalizedAge)

        // Calculate next new moon and full moon
        let daysToNewMoon = synodicMonth - normalizedAge
        let nextNewMoon = date.addingTimeInterval(daysToNewMoon * 86400)

        let daysToFullMoon: Double
        if normalizedAge < synodicMonth / 2 {
            daysToFullMoon = (synodicMonth / 2) - normalizedAge
        } else {
            daysToFullMoon = synodicMonth - normalizedAge + (synodicMonth / 2)
        }
        let nextFullMoon = date.addingTimeInterval(daysToFullMoon * 86400)

        return MoonPhaseInfo(
            phase: phase,
            illumination: illumination,
            age: normalizedAge,
            nextNewMoon: nextNewMoon,
            nextFullMoon: nextFullMoon,
            synodicMonth: synodicMonth,
            phaseAngle: elongation
        )
    }

    /// Determine moon phase from age in days.
    /// Each of the eight bins is *centred* on its event (new at age 0, first
    /// quarter at ¼, full at ½, …), so e.g. "Full Moon" spans ±1.85 days around
    /// the instant of full moon rather than starting at it.
    private static func phaseFromAge(_ age: Double) -> MoonPhase {
        let phaseLength = synodicMonth / 8
        var dayInCycle = (age + phaseLength / 2).truncatingRemainder(dividingBy: synodicMonth)
        if dayInCycle < 0 { dayInCycle += synodicMonth }

        switch dayInCycle {
        case 0..<phaseLength:
            return .newMoon
        case phaseLength..<(2 * phaseLength):
            return .waxingCrescent
        case (2 * phaseLength)..<(3 * phaseLength):
            return .firstQuarter
        case (3 * phaseLength)..<(4 * phaseLength):
            return .waxingGibbous
        case (4 * phaseLength)..<(5 * phaseLength):
            return .fullMoon
        case (5 * phaseLength)..<(6 * phaseLength):
            return .waningGibbous
        case (6 * phaseLength)..<(7 * phaseLength):
            return .lastQuarter
        default:
            return .waningCrescent
        }
    }

    // MARK: - Moonrise/Moonset Calculations

    // Moon's horizontal parallax varies but averages about 0.95°
    // This makes the Moon appear lower than its geometric position
    private static let moonParallax = 0.95
    // Atmospheric refraction at horizon
    private static let refractionAtHorizon = 0.567
    // Moon's average semi-diameter
    private static let moonSemiDiameter = 0.26
    // The horizon altitude for moonrise/moonset (upper limb touching horizon)
    // = -parallax + refraction + semi-diameter ≈ -0.12°.
    // (The textbook value is +parallax − refraction − semi-diameter ≈ +0.125°;
    // the sign is kept as-is because Equinox and Lunker both ship it — see
    // README "Candidates for a later accuracy release".)
    private static let moonHorizonAltitude = -moonParallax + refractionAtHorizon + moonSemiDiameter // ≈ -0.12°

    /// Calculate moonrise and moonset times for a given date and location.
    ///
    /// `timeZone` selects which local day is scanned: from midnight in the
    /// location's own zone to the next local midnight (so 23 h / 25 h
    /// DST-transition days are covered exactly). When the moon crosses the
    /// horizon twice in one day (high latitudes), the **last** crossing of
    /// each kind is reported. `transitTime` is the highest 5-minute sample
    /// strictly before the next midnight.
    public static func moonTimes(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> MoonTimes {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        let dayMinutes = Int((endOfDay.timeIntervalSince(startOfDay) / 60).rounded())

        var moonrise: Date?
        var moonset: Date?
        var transitTime: Date?
        var maxAltitude = -90.0

        // First pass: check every 5 minutes to find approximate crossings
        var prevAltitude: Double?
        var prevTime: Date?

        for minutes in stride(from: 0, through: dayMinutes, by: 5) {
            let checkTime = startOfDay.addingTimeInterval(Double(minutes) * 60)
            let position = lunarPosition(at: checkTime, latitude: latitude, longitude: longitude)
            let altitude = position.altitude

            // Track transit (highest point). Exclude the final sample at the
            // NEXT day's midnight: a transit there belongs to tomorrow. (The
            // sample is still used for rise/set crossing detection in the last
            // 5-minute window of today.)
            if altitude > maxAltitude && minutes < dayMinutes {
                maxAltitude = altitude
                transitTime = checkTime
            }

            if let prev = prevAltitude, let prevT = prevTime {
                // Moon rising (crossed horizon altitude from below). No
                // `== nil` guard: at high latitudes the moon can briefly dip
                // below and rise again; overwriting keeps the LAST (main) rise.
                if prev < moonHorizonAltitude && altitude >= moonHorizonAltitude {
                    moonrise = refineHorizonCrossing(
                        startTime: prevT,
                        endTime: checkTime,
                        latitude: latitude,
                        longitude: longitude,
                        isRising: true
                    )
                }
                // Moon setting (crossed horizon altitude from above). Same reasoning.
                if prev >= moonHorizonAltitude && altitude < moonHorizonAltitude {
                    moonset = refineHorizonCrossing(
                        startTime: prevT,
                        endTime: checkTime,
                        latitude: latitude,
                        longitude: longitude,
                        isRising: false
                    )
                }
            }

            prevAltitude = altitude
            prevTime = checkTime
        }

        return MoonTimes(moonrise: moonrise, moonset: moonset, transitTime: transitTime)
    }

    /// Refine horizon crossing time using binary search
    private static func refineHorizonCrossing(
        startTime: Date,
        endTime: Date,
        latitude: Double,
        longitude: Double,
        isRising: Bool
    ) -> Date {
        var low = startTime
        var high = endTime

        // Binary search for 8 iterations (accuracy ~2 seconds)
        for _ in 0..<8 {
            let mid = Date(timeIntervalSince1970: (low.timeIntervalSince1970 + high.timeIntervalSince1970) / 2)
            let position = lunarPosition(at: mid, latitude: latitude, longitude: longitude)
            let altitude = position.altitude

            if isRising {
                if altitude < moonHorizonAltitude {
                    low = mid
                } else {
                    high = mid
                }
            } else {
                if altitude >= moonHorizonAltitude {
                    low = mid
                } else {
                    high = mid
                }
            }
        }

        return Date(timeIntervalSince1970: (low.timeIntervalSince1970 + high.timeIntervalSince1970) / 2)
    }

    // MARK: - Transits (from Otta)

    /// Upper and lower meridian transits within the local day containing `date`.
    ///
    /// Scans the moon's altitude at 6-minute steps from local midnight to the
    /// next midnight (24 h) and refines the highest and lowest samples with a
    /// parabolic fit. When an extremum sits on the window edge (the true
    /// transit falls on a neighbouring day) the edge sample is returned
    /// unrefined, matching Otta's `LunarCalculator.transits`.
    public static func transits(date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> MoonTransits {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: date)

        let stepMinutes = 6.0
        let steps = Int((24 * 60) / stepMinutes)
        let stepSeconds = stepMinutes * 60

        var alts = [Double]()
        alts.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = start.addingTimeInterval(Double(i) * stepSeconds)
            alts.append(lunarPosition(at: t, latitude: latitude, longitude: longitude).altitude)
        }

        let upperIndex = alts.indices.max(by: { alts[$0] < alts[$1] })
        let lowerIndex = alts.indices.min(by: { alts[$0] < alts[$1] })

        return MoonTransits(
            upper: refinedExtremum(at: upperIndex, alts: alts, start: start, stepSeconds: stepSeconds),
            lower: refinedExtremum(at: lowerIndex, alts: alts, start: start, stepSeconds: stepSeconds)
        )
    }

    /// Parabolic refinement of an interior extremum; falls back to the sample time
    /// at the boundaries (where the true transit lies outside the scanned day).
    private static func refinedExtremum(at index: Int?, alts: [Double], start: Date, stepSeconds: Double) -> Date? {
        guard let i = index else { return nil }
        func time(_ offset: Double) -> Date {
            start.addingTimeInterval((Double(i) + offset) * stepSeconds)
        }
        guard i > 0, i < alts.count - 1 else { return time(0) }
        let ym1 = alts[i - 1], y0 = alts[i], yp1 = alts[i + 1]
        let denom = ym1 - 2 * y0 + yp1
        guard abs(denom) > 1e-12 else { return time(0) }
        let offset = 0.5 * (ym1 - yp1) / denom  // vertex offset in sample steps, (-0.5, 0.5)
        return time(offset)
    }

    // MARK: - Lunar Position Calculations

    /// Moon elevation + azimuth at an instant — a slim view of `lunarPosition`
    /// shaped like `SolarCalculator.SunPosition` (Otta's `moonPosition`).
    public static func moonPosition(at time: Date, latitude: Double, longitude: Double) -> MoonPosition {
        let p = lunarPosition(at: time, latitude: latitude, longitude: longitude)
        return MoonPosition(time: time, elevation: p.altitude, azimuth: p.azimuth)
    }

    /// Calculate the Moon's position at a specific time and location
    public static func lunarPosition(at time: Date, latitude: Double, longitude: Double) -> LunarPosition {
        let jd = julianDay(from: time)
        let t = (jd - 2451545.0) / 36525.0 // Julian centuries from J2000.0

        // Moon's mean longitude
        let Lp = (218.3164477 + 481267.88123421 * t - 0.0015786 * t * t).truncatingRemainder(dividingBy: 360)

        // Moon's mean anomaly
        let M = (134.9633964 + 477198.8675055 * t + 0.0087414 * t * t).truncatingRemainder(dividingBy: 360)

        // Moon's mean elongation
        let D = (297.8501921 + 445267.1114034 * t - 0.0018819 * t * t).truncatingRemainder(dividingBy: 360)

        // Sun's mean anomaly
        let Ms = (357.5291092 + 35999.0502909 * t - 0.0001536 * t * t).truncatingRemainder(dividingBy: 360)

        // Moon's argument of latitude
        let F = (93.2720950 + 483202.0175233 * t - 0.0036539 * t * t).truncatingRemainder(dividingBy: 360)

        // Longitude corrections (simplified)
        let dL = 6.289 * sin(M * rad)
            - 1.274 * sin((2 * D - M) * rad)
            + 0.658 * sin(2 * D * rad)
            - 0.214 * sin(2 * M * rad)
            - 0.186 * sin(Ms * rad)

        // Latitude correction (simplified)
        let dB = 5.128 * sin(F * rad)

        // Ecliptic coordinates
        let eclipticLongitude = (Lp + dL).truncatingRemainder(dividingBy: 360)
        let normalizedLongitude = eclipticLongitude < 0 ? eclipticLongitude + 360 : eclipticLongitude
        let eclipticLatitude = dB

        // Obliquity of ecliptic
        let obliquity = 23.439291 - 0.0130042 * t

        // Convert to equatorial coordinates
        let lonRad = normalizedLongitude * rad
        let latRad = eclipticLatitude * rad
        let oblRad = obliquity * rad

        let rightAscension = atan2(
            sin(lonRad) * cos(oblRad) - tan(latRad) * sin(oblRad),
            cos(lonRad)
        ) * deg

        let declination = asin(
            sin(latRad) * cos(oblRad) + cos(latRad) * sin(oblRad) * sin(lonRad)
        ) * deg

        // Calculate altitude and azimuth (reuse the jd/t already computed above)
        let (altitude, azimuth) = calculateAltAz(
            rightAscension: rightAscension,
            declination: declination,
            latitude: latitude,
            longitude: longitude,
            jd: jd,
            t: t
        )

        // Determine zodiac constellation
        let constellation = zodiacFromLongitude(normalizedLongitude)

        return LunarPosition(
            constellation: constellation,
            eclipticLongitude: normalizedLongitude,
            rightAscension: rightAscension < 0 ? rightAscension + 360 : rightAscension,
            declination: declination,
            altitude: altitude,
            azimuth: azimuth
        )
    }

    /// Calculate altitude and azimuth from equatorial coordinates, given the
    /// Julian day and Julian century already computed by the caller.
    private static func calculateAltAz(rightAscension: Double, declination: Double, latitude: Double, longitude: Double, jd: Double, t: Double) -> (altitude: Double, azimuth: Double) {
        // Greenwich Mean Sidereal Time
        let gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t

        // Local Sidereal Time
        let lst = (gmst + longitude).truncatingRemainder(dividingBy: 360)

        // Hour angle
        let ha = lst - rightAscension
        let haRad = ha * rad

        let latRad = latitude * rad
        let decRad = declination * rad

        // Altitude
        let sinAlt = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        let altitude = asin(sinAlt) * deg

        // Azimuth
        let cosAz = (sin(decRad) - sin(latRad) * sinAlt) / (cos(latRad) * cos(altitude * rad))
        var azimuth = acos(max(-1, min(1, cosAz))) * deg

        if sin(haRad) > 0 {
            azimuth = 360 - azimuth
        }

        return (altitude, azimuth)
    }

    /// Determine zodiac constellation from ecliptic longitude
    private static func zodiacFromLongitude(_ longitude: Double) -> ZodiacConstellation {
        // Normalize into [0, 360) first — truncatingRemainder keeps the sign, so a
        // negative longitude would otherwise produce a negative (out-of-bounds) index.
        var normalizedLon = longitude.truncatingRemainder(dividingBy: 360)
        if normalizedLon < 0 { normalizedLon += 360 }
        let index = min(11, max(0, Int(normalizedLon / 30)))
        return ZodiacConstellation.allCases[index]
    }

    // MARK: - Lunar Distance Calculations

    /// Calculate lunar distance information for a given date
    public static func lunarDistance(for date: Date) -> LunarDistanceInfo {
        let jd = julianDay(from: date)
        let t = (jd - 2451545.0) / 36525.0

        // Fundamental arguments (degrees)
        let D = (297.8501921 + 445267.1114034 * t).truncatingRemainder(dividingBy: 360) * rad  // Mean elongation
        let M = (134.9633964 + 477198.8675055 * t).truncatingRemainder(dividingBy: 360) * rad  // Moon's mean anomaly
        let Ms = (357.5291092 + 35999.0502909 * t).truncatingRemainder(dividingBy: 360) * rad  // Sun's mean anomaly
        let F = (93.2720950 + 483202.0175233 * t).truncatingRemainder(dividingBy: 360) * rad   // Argument of latitude

        // Largest Σr terms of Meeus Table 47.A (M here = Moon's anomaly M′,
        // Ms = Sun's anomaly M; the E eccentricity factor is omitted).
        // Split into two sums to keep the type checker fast.
        let mainTerms: Double =
            -20905.355 * cos(M)
            - 3699.111 * cos(2 * D - M)
            - 2955.968 * cos(2 * D)
            - 569.925 * cos(2 * M)
            + 48.888 * cos(Ms)
            - 3.149 * cos(2 * F)
            + 246.158 * cos(2 * D - 2 * M)
            - 152.138 * cos(2 * D - Ms - M)
            - 170.733 * cos(2 * D + M)
            - 204.586 * cos(2 * D - Ms)
            - 129.620 * cos(Ms - M)
            + 108.743 * cos(D)
            + 104.755 * cos(Ms + M)
        let minorTerms: Double =
            10.321 * cos(2 * D - 2 * F)
            + 79.661 * cos(M - 2 * F)
            - 34.782 * cos(4 * D - M)
            - 23.210 * cos(3 * M)
            - 21.636 * cos(4 * D - 2 * M)
            + 24.208 * cos(2 * D + Ms - M)
            + 30.824 * cos(2 * D + Ms)
        let distanceTerms = mainTerms + minorTerms

        // Meeus eq. 47: Δ = 385000.56 km + Σr (the series' own mean, not the
        // 384400 km semi-major axis used for percentOfAverage below).
        let distance = 385000.56 + distanceTerms

        // Calculate status
        let percentOfAverage = (distance / averageDistance) * 100
        let status: LunarDistanceStatus
        if distance < perigeeDistance + 5000 {
            status = .perigee
        } else if distance < perigeeDistance + 15000 {
            status = .nearPerigee
        } else if distance > apogeeDistance - 5000 {
            status = .apogee
        } else if distance > apogeeDistance - 15000 {
            status = .nearApogee
        } else {
            status = .normal
        }

        // Calculate next perigee and apogee (approximate)
        let anomalyPeriod = 27.55455 // Anomalistic month in days
        // M is in radians; recover the mean anomaly in degrees, normalized to 0..<360
        // (only negative before J2000, where the fold is needed).
        var currentAnomaly = (M * deg).truncatingRemainder(dividingBy: 360)
        if currentAnomaly < 0 { currentAnomaly += 360 }

        // Perigee occurs at anomaly = 0°
        let daysToPerigee = ((360 - currentAnomaly).truncatingRemainder(dividingBy: 360) / 360) * anomalyPeriod
        let nextPerigee = date.addingTimeInterval(daysToPerigee * 86400)

        // Apogee occurs at anomaly = 180°
        let daysToApogee = (((180 - currentAnomaly + 360).truncatingRemainder(dividingBy: 360)) / 360) * anomalyPeriod
        let nextApogee = date.addingTimeInterval(daysToApogee * 86400)

        // Check for supermoon (full moon near perigee)
        let phaseInfo = moonPhase(for: date)
        let isSupermoon = (status == .perigee || status == .nearPerigee) &&
            (phaseInfo.phase == .fullMoon || phaseInfo.phase == .waxingGibbous || phaseInfo.phase == .waningGibbous)

        return LunarDistanceInfo(
            distanceKm: distance,
            distanceStatus: status,
            percentOfAverage: percentOfAverage,
            nextPerigee: nextPerigee,
            nextApogee: nextApogee,
            isSupermoon: isSupermoon
        )
    }

    // MARK: - Eclipse Predictions

    /// Every solar (total/annular/hybrid/partial) and lunar
    /// (total/partial/penumbral) eclipse from 2025 through 2035, in
    /// chronological order, at the instant of greatest eclipse (UT, rounded to
    /// the minute — NASA tables quote TD, which runs ~74 s ahead) per the
    /// NASA/Espenak eclipse catalogues (Lunker's table). Visibility strings are
    /// broad regions only, and are English keys looked up in the host app's
    /// main-bundle string catalog.
    ///
    /// Coverage ends with the 2035-09-02 total solar eclipse (see
    /// `eclipseTableCoverageEnd`); extend the table well before then, or the
    /// upcoming-eclipse list quietly runs dry.
    private static let knownEclipses: [(type: EclipseEvent.EclipseType, year: Int, month: Int, day: Int, hour: Int, minute: Int, visibility: String)] = [
        (.lunarTotal, 2025, 3, 14, 6, 59, "Americas, Europe, Africa"),
        (.solarPartial, 2025, 3, 29, 10, 47, "Europe, N. Africa, N. Russia, NE North America"),
        (.lunarTotal, 2025, 9, 7, 18, 12, "Europe, Africa, Asia, Australia"),
        (.solarPartial, 2025, 9, 21, 19, 42, "New Zealand, Antarctica, S. Pacific"),
        (.solarAnnular, 2026, 2, 17, 12, 12, "Antarctica, S. Africa, S. South America"),
        (.lunarTotal, 2026, 3, 3, 11, 34, "Asia, Australia, Pacific, Americas"),
        (.solarTotal, 2026, 8, 12, 17, 46, "Arctic, Greenland, Iceland, Spain"),
        (.lunarPartial, 2026, 8, 28, 4, 13, "Americas, Europe, Africa"),
        (.solarAnnular, 2027, 2, 6, 16, 0, "South America, Africa, Antarctica"),
        (.lunarPenumbral, 2027, 2, 20, 23, 13, "Americas, Europe, Africa, Asia"),
        (.lunarPenumbral, 2027, 7, 18, 16, 3, "Asia, Australia, Pacific"),
        (.solarTotal, 2027, 8, 2, 10, 7, "Africa, Europe, Middle East"),
        (.lunarPenumbral, 2027, 8, 17, 7, 14, "Americas, Pacific"),
        (.lunarPartial, 2028, 1, 12, 4, 13, "Americas, Europe, Africa"),
        (.solarAnnular, 2028, 1, 26, 15, 8, "Americas, W. Europe, W. Africa"),
        (.lunarPartial, 2028, 7, 6, 18, 20, "Europe, Africa, Asia, Australia"),
        (.solarTotal, 2028, 7, 22, 2, 55, "Australia, New Zealand"),
        (.lunarTotal, 2028, 12, 31, 16, 52, "Europe, Africa, Asia, Australia"),
        (.solarPartial, 2029, 1, 14, 17, 13, "North America, Central America"),
        (.solarPartial, 2029, 6, 12, 4, 5, "Arctic, Scandinavia, Alaska, N. Asia, Canada"),
        (.lunarTotal, 2029, 6, 26, 3, 22, "Americas, Europe, Africa"),
        (.solarPartial, 2029, 7, 11, 15, 36, "Southern South America"),
        (.solarPartial, 2029, 12, 5, 15, 3, "Southern South America, Antarctica"),
        (.lunarTotal, 2029, 12, 20, 22, 42, "Americas, Europe, Africa, Asia"),
        (.solarAnnular, 2030, 6, 1, 6, 28, "N. Africa, Europe, Middle East, Central Asia"),
        (.lunarPartial, 2030, 6, 15, 18, 33, "Europe, Africa, Asia, Australia"),
        (.solarTotal, 2030, 11, 25, 6, 50, "S. Africa, S. Atlantic, S. Australia"),
        (.lunarPenumbral, 2030, 12, 9, 22, 28, "Americas, Europe, Africa, Asia"),
        (.lunarPenumbral, 2031, 5, 7, 3, 51, "Americas, Europe, Africa, Middle East"),
        (.solarAnnular, 2031, 5, 21, 7, 15, "Africa, S. India, SE Asia"),
        (.lunarPenumbral, 2031, 6, 5, 11, 44, "Asia, Australia, Pacific"),
        (.lunarPenumbral, 2031, 10, 30, 7, 45, "Americas, Pacific"),
        (.solarHybrid, 2031, 11, 14, 21, 6, "Pacific, Central America, NW South America"),
        (.lunarTotal, 2032, 4, 25, 15, 14, "Asia, Australia, Pacific"),
        (.solarAnnular, 2032, 5, 9, 13, 25, "S. Atlantic, S. Africa, Antarctica"),
        (.lunarTotal, 2032, 10, 18, 19, 2, "Europe, Africa, Asia, Australia"),
        (.solarPartial, 2032, 11, 3, 5, 33, "Asia"),
        (.solarTotal, 2033, 3, 30, 18, 1, "Alaska, Arctic, N. Russia"),
        (.lunarTotal, 2033, 4, 14, 19, 13, "Europe, Africa, Asia, Australia"),
        (.solarPartial, 2033, 9, 23, 13, 53, "S. South America, Antarctica"),
        (.lunarTotal, 2033, 10, 8, 10, 55, "Asia, Australia, Pacific, Americas"),
        (.solarTotal, 2034, 3, 20, 10, 18, "Africa, Middle East, S. Asia"),
        (.lunarPenumbral, 2034, 4, 3, 19, 6, "Europe, Africa, Asia, Australia"),
        (.solarAnnular, 2034, 9, 12, 16, 18, "Pacific, South America, Atlantic"),
        (.lunarPartial, 2034, 9, 28, 2, 46, "Americas, Europe, Africa"),
        (.lunarPenumbral, 2035, 2, 22, 9, 5, "E. Asia, Australia, Pacific, Americas"),
        (.solarAnnular, 2035, 3, 9, 23, 5, "Australia, New Zealand, Pacific"),
        (.lunarPartial, 2035, 8, 19, 1, 11, "Americas, Europe, Africa"),
        (.solarTotal, 2035, 9, 2, 1, 56, "China, Korea, Japan, Pacific"),
    ]

    /// All table entries as events, in chronological order. Each `date` is the
    /// UT instant of greatest eclipse; `visibility` is localized through the
    /// host app's main bundle (falling back to the English key).
    private static var allEclipses: [EclipseEvent] {
        knownEclipses.compactMap { eclipse in
            var components = DateComponents()
            components.year = eclipse.year
            components.month = eclipse.month
            components.day = eclipse.day
            components.hour = eclipse.hour
            components.minute = eclipse.minute
            guard let eclipseDate = gregorianUTC.date(from: components) else { return nil }
            let visibility = NSLocalizedString(eclipse.visibility, bundle: .main, comment: "Eclipse visibility regions")
            return EclipseEvent(type: eclipse.type, date: eclipseDate, visibility: visibility)
        }
    }

    /// The last instant covered by the eclipse table (2035-09-02 01:56 UT).
    /// Extend the table well before this date, or the upcoming-eclipse list
    /// quietly runs dry.
    public static var eclipseTableCoverageEnd: Date? {
        allEclipses.last?.date
    }

    /// Upcoming eclipses (pre-computed known eclipses) strictly after `date`.
    /// Note: Full eclipse prediction requires complex calculations; this uses known upcoming eclipses
    public static func upcomingEclipses(after date: Date, limit: Int = 5) -> [EclipseEvent] {
        Array(allEclipses.filter { $0.date > date }.prefix(max(0, limit)))
    }

    /// Lunker's variant: an eclipse stays listed for the whole calendar day (in
    /// `calendar`) on which it occurs, rather than vanishing once its instant
    /// has passed. Because each date is the UT instant of greatest eclipse,
    /// it lands on the right local day in every zone (UTC+12…+14 included).
    public static func upcomingEclipses(after date: Date, limit: Int = 5, calendar: Calendar) -> [EclipseEvent] {
        let startOfToday = calendar.startOfDay(for: date)
        return Array(allEclipses.filter { $0.date >= startOfToday }.prefix(max(0, limit)))
    }

    // MARK: - Julian Date Helpers

    /// Julian day of an instant, including fractional seconds.
    /// Unix epoch (1970-01-01 00:00 UTC) = JD 2440587.5.
    private static func julianDay(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
    }
}
