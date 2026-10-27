import Foundation

/// Solunar periods — the astronomy half of John Alden Knight's Solunar Theory
/// (1926), ported from Lunker's `SolunarCalculator` with the fishing score
/// (day score, `DayRating`, per-period score) deliberately left out.
///
/// - **Major periods (2 h)** — centred on lunar transit (moon overhead) and
///   anti-transit (moon underfoot, opposite side of Earth).
/// - **Minor periods (1 h)** — centred on moonrise and moonset.
///
/// Apps layer their own domain rating (fish, game, …) on top of `Solunar.Day`.
/// Everything here is pure geometry from `MoonCalculator` / `SolarCalculator`.
public enum Solunar {

    // MARK: - Period

    public enum PeriodKind: String, Sendable, Hashable, CaseIterable {
        case majorOverhead   // moon transit (highest in local sky)
        case majorUnderfoot  // moon anti-transit (lowest, opposite side of Earth)
        case minorMoonrise
        case minorMoonset

        public var isMajor: Bool {
            self == .majorOverhead || self == .majorUnderfoot
        }

        /// Total period duration in minutes (period spans ±half this around center).
        public var durationMinutes: Int { isMajor ? 120 : 60 }
    }

    public struct Period: Sendable, Hashable, Identifiable {
        public let kind: PeriodKind
        public let center: Date

        public init(kind: PeriodKind, center: Date) {
            self.kind = kind
            self.center = center
        }

        /// Stable ID derived from the period's logical identity so that recomputing
        /// the same day yields the same IDs (SwiftUI diffs, notification identifiers).
        public var id: String { "\(kind.rawValue)-\(Int(center.timeIntervalSinceReferenceDate / 60))" }

        /// The window is centred on `center` and spans `durationMinutes`, so each
        /// side is half that: (durationMinutes / 2) minutes × 60 s = durationMinutes × 30 s.
        public var start: Date {
            center.addingTimeInterval(-Double(kind.durationMinutes) * 30)
        }

        public var end: Date {
            center.addingTimeInterval(Double(kind.durationMinutes) * 30)
        }

        public func contains(_ date: Date) -> Bool {
            date >= start && date <= end
        }
    }

    // MARK: - Day

    public struct Day: Sendable, Hashable {
        /// Start of the calendar day (in the `calendar` passed to `day(for:…)`).
        public let date: Date
        /// Chronological; only periods whose *center* falls within the day.
        public let periods: [Period]
        /// Moonrise/moonset inside the day (nil if none or outside the day).
        public let moonrise: Date?
        public let moonset: Date?

        public init(date: Date, periods: [Period], moonrise: Date?, moonset: Date?) {
            self.date = date
            self.periods = periods
            self.moonrise = moonrise
            self.moonset = moonset
        }

        public var majorPeriods: [Period] { periods.filter { $0.kind.isMajor } }
        public var minorPeriods: [Period] { periods.filter { !$0.kind.isMajor } }

        /// The active period containing `now`, if any.
        public func activePeriod(at now: Date) -> Period? {
            periods.first { $0.contains(now) }
        }

        /// Next upcoming period: the one that *starts* soonest strictly after
        /// `now`. `periods` is ordered by center, and a 2 h major can start
        /// before a 1 h minor centred earlier, so pick by start time.
        public func nextPeriod(after now: Date) -> Period? {
            periods
                .filter { $0.start > now }
                .min { $0.start < $1.start }
        }
    }

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let dayStart: Date
        let latitude: Double
        let longitude: Double
        let timeZoneId: String
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [CacheKey: Day] = [:]
    /// Cache keys from least to most recently used (guarded by `cacheLock`).
    nonisolated(unsafe) private static var cacheAccessOrder: [CacheKey] = []
    private static let maxCacheEntries = 90  // ~3 months of daily entries

    // MARK: - Public API

    /// Solunar periods for the calendar day containing `date` (in `calendar`).
    ///
    /// All returned periods have their *center* within that day; start/end may
    /// extend slightly before midnight or after the next midnight. Coordinates
    /// are rounded to 0.01° (~1 km) and results memoized (LRU, 90 entries), so
    /// repeated calls from several screens share one computation. The result
    /// depends only on the day, never on the time of day passed in.
    public static func day(
        for date: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> Day {
        let dayStart = calendar.startOfDay(for: date)
        let roundedLat = (latitude * 100).rounded() / 100
        let roundedLon = (longitude * 100).rounded() / 100
        let key = CacheKey(dayStart: dayStart, latitude: roundedLat, longitude: roundedLon, timeZoneId: calendar.timeZone.identifier)

        cacheLock.lock()
        if let cached = cache[key] {
            touch(key)
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = computeDay(dayStart: dayStart, latitude: roundedLat, longitude: roundedLon, calendar: calendar)

        cacheLock.lock()
        if cache.updateValue(result, forKey: key) == nil {
            cacheAccessOrder.append(key)
        } else {
            touch(key)
        }
        while cache.count > maxCacheEntries, !cacheAccessOrder.isEmpty {
            let oldest = cacheAccessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        cacheLock.unlock()
        return result
    }

    /// Smallest |Δt| between any sun rise/set and any moon rise/set, or nil
    /// when no pair exists. The raw input for "sun/moon alignment" ratings.
    public static func closestSunMoonAlignment(
        sunrise: Date?,
        sunset: Date?,
        moonrise: Date?,
        moonset: Date?
    ) -> TimeInterval? {
        let pairs: [(Date?, Date?)] = [
            (sunrise, moonrise), (sunrise, moonset),
            (sunset, moonrise), (sunset, moonset)
        ]
        var best: TimeInterval?
        for (a, b) in pairs {
            guard let a, let b else { continue }
            let d = abs(a.timeIntervalSince(b))
            if best == nil || d < best! { best = d }
        }
        return best
    }

    /// Forward-searches for the next day on which a sun↔moon rise/set pair falls
    /// within `withinMinutes` — i.e. the next strong sun/moon alignment. Returns
    /// the moment of the aligning solar event, or `nil` if none within `maxDays`.
    public static func nextStrongAlignment(
        after date: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone,
        withinMinutes: Int = 30,
        maxDays: Int = 60
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let threshold = TimeInterval(withinMinutes * 60)
        guard maxDays >= 1 else { return nil }

        for offset in 1...maxDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let sun = SolarCalculator.sunTimes(date: day, latitude: latitude, longitude: longitude, timeZone: timeZone)
            let moon = MoonCalculator.moonTimes(date: day, latitude: latitude, longitude: longitude, timeZone: timeZone)
            let pairs: [(Date?, Date?)] = [
                (sun?.sunrise, moon.moonrise), (sun?.sunrise, moon.moonset),
                (sun?.sunset, moon.moonrise), (sun?.sunset, moon.moonset)
            ]
            var best: (delta: TimeInterval, solar: Date)?
            for (s, m) in pairs {
                guard let s, let m else { continue }
                let d = abs(s.timeIntervalSince(m))
                if d <= threshold, best == nil || d < best!.delta {
                    best = (d, s)
                }
            }
            if let best { return best.solar }
        }
        return nil
    }

    // MARK: - Internals

    /// Moves `key` to the most-recently-used end. Caller holds `cacheLock`.
    private static func touch(_ key: CacheKey) {
        if let index = cacheAccessOrder.lastIndex(of: key) {
            cacheAccessOrder.remove(at: index)
        }
        cacheAccessOrder.append(key)
    }

    private static func computeDay(dayStart: Date, latitude: Double, longitude: Double, calendar: Calendar) -> Day {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)

        let extrema = lunarAltitudeExtrema(dayStart: dayStart, dayEnd: dayEnd, latitude: latitude, longitude: longitude)

        // Moonrise / moonset (scanned in the location's own zone, so they land on the right day)
        let moonTimes = MoonCalculator.moonTimes(date: dayStart, latitude: latitude, longitude: longitude, timeZone: calendar.timeZone)
        let isInDay = { (t: Date) -> Bool in t >= dayStart && t < dayEnd }
        let moonrise = moonTimes.moonrise.flatMap { isInDay($0) ? $0 : nil }
        let moonset = moonTimes.moonset.flatMap { isInDay($0) ? $0 : nil }

        var candidates: [Period] = []
        candidates += extrema.transits.map { Period(kind: .majorOverhead, center: $0) }
        candidates += extrema.antiTransits.map { Period(kind: .majorUnderfoot, center: $0) }
        if let moonrise { candidates.append(Period(kind: .minorMoonrise, center: moonrise)) }
        if let moonset { candidates.append(Period(kind: .minorMoonset, center: moonset)) }

        let periods = candidates
            .filter { isInDay($0.center) }
            .sorted { $0.center < $1.center }

        return Day(date: dayStart, periods: periods, moonrise: moonrise, moonset: moonset)
    }

    private struct AltitudeExtrema {
        let transits: [Date]      // local maxima of altitude inside the day
        let antiTransits: [Date]  // local minima of altitude inside the day
    }

    /// Padding scanned on both sides of the day so an extremum just after midnight (or just
    /// before the next one) is still recognised as a local extremum rather than a window edge.
    private static let extremaScanPadding: TimeInterval = 60 * 60

    /// Scan lunar altitude across `[dayStart − 1 h, dayEnd + 1 h]` at 5-minute resolution, find the
    /// local maxima (transit) and minima (anti-transit), refine each with 1-minute precision, and
    /// keep only those inside `[dayStart, dayEnd)`.
    ///
    /// The scan grid is aligned to local midnight and the refinement is deterministic, so an
    /// extremum near a day boundary resolves to the same instant from both neighbouring days and
    /// is kept by exactly the day it falls in — never by both, never by neither.
    private static func lunarAltitudeExtrema(dayStart: Date, dayEnd: Date, latitude: Double, longitude: Double) -> AltitudeExtrema {
        let windowStart = dayStart.addingTimeInterval(-extremaScanPadding)
        let windowEnd = dayEnd.addingTimeInterval(extremaScanPadding)
        let totalMinutes = Int((windowEnd.timeIntervalSince(windowStart) / 60).rounded())

        func altitude(_ t: Date) -> Double {
            MoonCalculator.lunarPosition(at: t, latitude: latitude, longitude: longitude).altitude
        }

        var samples: [(time: Date, altitude: Double)] = []
        samples.reserveCapacity(totalMinutes / 5 + 1)
        for minutes in stride(from: 0, through: totalMinutes, by: 5) {
            let t = windowStart.addingTimeInterval(Double(minutes) * 60)
            samples.append((t, altitude(t)))
        }

        var maxima: [(time: Date, altitude: Double)] = []
        var minima: [(time: Date, altitude: Double)] = []
        if samples.count >= 3 {
            for i in 1..<(samples.count - 1) {
                let prev = samples[i - 1].altitude
                let cur = samples[i].altitude
                let next = samples[i + 1].altitude
                if cur > prev && cur >= next {
                    let t = refineExtremum(around: samples[i].time, isMaximum: true, altitude: altitude)
                    maxima.append((t, altitude(t)))
                }
                if cur < prev && cur <= next {
                    let t = refineExtremum(around: samples[i].time, isMaximum: false, altitude: altitude)
                    minima.append((t, altitude(t)))
                }
            }
        }

        return AltitudeExtrema(
            transits: selectExtrema(maxima, dayStart: dayStart, dayEnd: dayEnd, preferHigher: true),
            antiTransits: selectExtrema(minima, dayStart: dayStart, dayEnd: dayEnd, preferHigher: false)
        )
    }

    /// Keeps the in-day extrema, dropping spurious ones (e.g. sampling noise when the altitude
    /// curve is nearly flat at polar latitudes) that lie within 20 h of a stronger one. Real
    /// transits are ~24 h 50 min apart, so a 25 h DST day can legitimately keep two.
    private static func selectExtrema(
        _ candidates: [(time: Date, altitude: Double)],
        dayStart: Date,
        dayEnd: Date,
        preferHigher: Bool
    ) -> [Date] {
        let minSeparation: TimeInterval = 20 * 3600
        let ranked = candidates
            .filter { $0.time >= dayStart && $0.time < dayEnd }
            .sorted { preferHigher ? $0.altitude > $1.altitude : $0.altitude < $1.altitude }
        var accepted: [Date] = []
        for candidate in ranked where !accepted.contains(where: { abs($0.timeIntervalSince(candidate.time)) < minSeparation }) {
            accepted.append(candidate.time)
        }
        return accepted.sorted()
    }

    /// Refine an altitude extremum around `center` by sampling at 1-minute steps in a ±5-minute window.
    private static func refineExtremum(around center: Date, isMaximum: Bool, altitude: (Date) -> Double) -> Date {
        var bestTime = center
        var bestAlt = altitude(center)
        for delta in stride(from: -5, through: 5, by: 1) {
            let t = center.addingTimeInterval(Double(delta) * 60)
            let alt = altitude(t)
            if isMaximum ? (alt > bestAlt) : (alt < bestAlt) {
                bestAlt = alt
                bestTime = t
            }
        }
        return bestTime
    }
}
