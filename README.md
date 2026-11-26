# AstroKit

Sun, moon and solunar astronomy for the Apps-AppStore family, shared by
**Equinox**, **Lunker** and **Otta**. It is pure Foundation, with no
dependencies, no resources, no networking and no backend. All entry points are
static, `Sendable` and deterministic. That means the repo can be **public**:
Xcode Cloud resolves it without a GitHub token or deploy key:
`.package(url: "https://github.com/Cliefden/AstroKit.git", from: "0.2.0")`.

- swift-tools 6.0, Swift 6 language mode
- iOS 17 / watchOS 10 / macOS 14 / visionOS 1
- Tests: 163 XCTest cases (Equinox's suites; eight re-baselined and one
  extended for 0.2, see CHANGELOG) plus Swift Testing suites for the API added for Lunker and Otta
  and a full port of Lunker's astronomy tests. Run them with `swift test`.
- See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

The public API comes from **Equinox's** `Shared/SolarCalculator.swift` and
`Shared/MoonCalculator.swift` and is a **superset** of what the three apps
call, so in most files adopting it only means adding `import AstroKit`.

**Since 0.2 the numbers are Lunker's.** Where the three original
implementations disagreed, 0.1 kept Equinox's math; 0.2 adopts Lunker's, which
is more accurate in every place they differed (see "0.2 behaviour vs 0.1").
A differential harness that compiles Lunker's original files next to AstroKit
shows identical results for every function Lunker calls (see "Lunker").

The **Kotlin port in Equinox Android (`EquinoxAndroid/`) stays separate.** It is
not generated from this package. When an algorithm changes here, port the change
to Kotlin by hand, as Equinox's CLAUDE.md already requires. **It still has 0.1's
math**, so it diverges from 0.2 until it is ported (see "Equinox").

## API overview

### `SolarCalculator` (NOAA solar calculator + Meeus equinox/solstice)

| Member | Notes |
|---|---|
| `solarEvent(_:year:)`, `allEvents(year:)` | Meeus equinox/solstice JDE. Cached per year behind an `NSLock`. |
| `lastEvent(before:ofType:)`, `nextEvent(after:ofType:)` | Optional type filter. Passing an empty filter is a precondition failure. |
| `lastEquinox/nextEquinox/lastSolstice/nextSolstice` | |
| `solsticeMirrorDate(for:)` | The date with the same daylight on the other side of the next solstice. |
| `sunTimes(date:latitude:longitude:timeZone:) -> SunTimes?` | Sunrise, sunset, solar noon and `daylightDuration` on the location's calendar day. Returns nil at the poles. |
| `polarState(...) -> PolarState?` | `.polarDay` / `.polarNight` (Lunker naming). Non-nil exactly when `sunTimes` is nil. |
| `polarCondition(...) -> PolarCondition?` | `.midnightSun` / `.polarNight` (Equinox naming). Same answer as `polarState`. |
| `twilightTimes(...) -> TwilightTimes?` | Civil 96°, nautical 102°, astronomical 108°. `sunrise`/`sunset` are non-optional, so it returns nil when the sun does not rise. |
| `twilightBoundaries(...) -> TwilightBoundaries?` | **0.2.** Lunker's all-optional shape: also reports twilight during polar night. Nil only when no boundary is crossed. |
| `goldenHourTimes(...) -> GoldenHourTimes?` | Blue hour −6°…−4°, golden hour −4°…+6°, with durations. Since 0.2 also reported on polar-night days (each boundary optional). |
| `eventTime(date:…zenith:isSunrise:timeZone:) -> Date?` | Crossing time for any zenith angle. |
| `eventTimeClampingPolar(...) -> Date` | From Otta. Never nil: in polar day it returns noon ± 12 h, in polar night it returns solar noon. Used for legal hunting hours. |
| `solarElevation(at:…)`, `solarPosition(at:…) -> SunPosition` | Elevation, plus azimuth clockwise from north. |
| `sunPath(date:…intervalMinutes:timeZone:)` | Sun positions sampled from local midnight to the next local midnight (23/25 h on DST days). |
| `maxSolarElevation`, `estimateUVIndex(elevation:)`, `uvLevel(from:)`, `UVLevel` | |
| `subsolarPoint(date:) -> SubsolarPoint`, `daylightHours(latitude:date:)` | `SubsolarPoint` has `.latitude`/`.longitude` (Lunker's tuple has the same member names). |

### `MoonCalculator` (Meeus, simplified)

| Member | Notes |
|---|---|
| `moonPhase(for:) -> MoonPhaseInfo` | Contains `phase` (8 named phases), `illumination` (alias `illuminatedFraction`), `age`, **`phaseAngle`** (sun→moon elongation, added for Otta), `nextNewMoon`, `nextFullMoon` and `synodicMonth`. |
| `dayPhase(for:) -> MoonPhaseInfo` | **0.2.** From Lunker: the phase at the day's midday (pass the location's start of day). |
| `MoonPhase.symbolName`, `MoonPhase.isWaxing` | **0.2.** Phase-accurate `moonphase.*` SF Symbol and waxing flag. `MoonPhase.icon` keeps Equinox's generic symbols. |
| `moonTimes(...) -> MoonTimes` | Moonrise, moonset and `transitTime` (the highest 5-minute sample). |
| `transits(...) -> MoonTransits` | From Otta. Upper (overhead) and lower (underfoot) meridian transits, from a 6-minute scan with parabolic refinement. |
| `lunarPosition(at:…) -> LunarPosition` | Ecliptic longitude, RA/Dec, altitude/azimuth and zodiac sign. |
| `moonPosition(at:…) -> MoonPosition` | From Otta. Elevation and azimuth in the same shape as `SunPosition`. |
| `lunarDistance(for:) -> LunarDistanceInfo` | Distance in km, perigee/apogee status, next perigee and apogee, supermoon flag. |
| `upcomingEclipses(after:limit:)` | Built-in table covering 2025–2035. Returns eclipses strictly after the given instant. |
| `upcomingEclipses(after:limit:calendar:)` | From Lunker. Keeps an eclipse listed for its whole calendar day. |
| `eclipseTableCoverageEnd` | From Lunker. Lets tests catch a table that has run out. |
| `EclipseEvent` | `Identifiable`, with the stable id `type@date`. Enums: `MoonPhase`, `ZodiacConstellation`, `LunarDistanceStatus`, `EclipseType` (includes `.solarHybrid`). |

### `Solunar` (Knight's solunar periods, astronomy only)

This is ported from Lunker's `SolunarCalculator`. **The fishing and hunting
ratings were left out on purpose** (day score, `DayRating`, `ScoreFactors`,
per-period score, localized captions). Each app keeps its own domain rating as
a layer on top.

| Member | Notes |
|---|---|
| `Solunar.day(for:latitude:longitude:calendar:) -> Solunar.Day` | Returns the periods whose *centre* falls inside the calendar day, plus that day's moonrise and moonset. Coordinates are rounded to 0.01° and results are kept in a 90-entry LRU cache. The result does not depend on the time of day passed in. |
| `Solunar.Period` | `kind`, `center`, `start`, `end`, `contains(_:)` and a stable `id`. |
| `Solunar.PeriodKind` | `.majorOverhead`, `.majorUnderfoot` (120 min), `.minorMoonrise`, `.minorMoonset` (60 min). |
| `Day.majorPeriods`, `minorPeriods`, `activePeriod(at:)`, `nextPeriod(after:)` | |
| `closestSunMoonAlignment(sunrise:sunset:moonrise:moonset:)` | Smallest gap between a solar and a lunar rise/set. This is the raw input to an alignment rating. |
| `nextStrongAlignment(after:…withinMinutes:maxDays:)` | The next day on which a sun event and a moon event fall within the threshold of each other. |

Transits and anti-transits are found as **local altitude extrema** in a 5-minute
scan over the day ± 1 h, refined to the nearest minute. An extremum just past
midnight is therefore kept by exactly one day.

#### How Otta's `SolunarPredictor` differs (it is not ported)

Otta's `SolunarPredictor` (`Otta/Services/SolunarPredictor.swift`) models the
same theory with different choices:

- **Transits** come from `LunarCalculator.transits`: the highest and lowest
  6-minute sample of the 24 h day. That gives one of each per day, and the day
  edge can be returned as the "transit". `Solunar` uses true local extrema in a
  padded window, which means 0–2 per day with no duplicates across days.
  `MoonCalculator.transits` reproduces Otta's method on AstroKit's moon model,
  so Otta can switch without changing behaviour.
- **Windows** are the same (major ±60 min, minor ±30 min). Otta sorts peaks by
  *start*. `Solunar` sorts by *centre* and offers `nextPeriod(after:)` by start.
- **Sun coincidence:** Otta flags peaks within 60 min of sunrise or sunset
  (`nearSunEvent`), using its polar-clamped `SolarTimeProvider`. `Solunar`
  exposes `closestSunMoonAlignment` for that, and the flag itself stays in Otta.
- **Rating:** Otta uses a 0…4 heuristic (base 1, +0…2 for phase, +1 when a major
  period coincides with dawn or dusk). Lunker uses a 0…100 score (phase 50 +
  distance 30 + alignment 20). Both stay in their apps.
- Otta works from `CLLocationCoordinate2D` and an injected `SolarTimeProvider`.
  `Solunar` takes plain `Double` coordinates, so AstroKit does not import
  CoreLocation.

## Localization

`localizedName` and `description` on the enums, and each eclipse's
`visibility`, look up their **English keys in the host app's main bundle**
(`NSLocalizedString(_, bundle: .main)` / `String(localized:bundle: .main)`).
These are the same keys Equinox and Lunker already have in their string
catalogs, so existing translations keep working. Xcode no longer *extracts*
those keys from app code, so it may mark them "stale". Keep them in the catalog
anyway. The package has no string catalog of its own.

## Accuracy notes

- **Sun:** NOAA's low-precision series. Sunrise and sunset are within about
  1–2 min of USNO/NOAA at mid-latitudes, as covered by the tests. Per-day
  results (sun times, polar state, twilight, golden hour, event times) are
  anchored to the **location's calendar day** in the `timeZone` you pass, with
  declination and the equation of time evaluated at that day's **solar noon**;
  they do not depend on the time of day passed in or on the device time zone,
  and are exact on 23 h/25 h DST days. Elevation, position and the subsolar
  point evaluate declination and the equation of time at the **exact instant**.
  `daylightHours(latitude:date:)` still uses 0 h UT of the UTC date (it has no
  longitude). Equinoxes and solstices use Meeus' mean-JDE polynomials, with
  results truncated to the minute. That is within about 1–2 min of USNO for
  2000–2050, without the periodic-term correction.
- **Moon:** a simplified Meeus model, with 5 longitude terms and one latitude
  term. Expect positions within 1–3° and moonrise/moonset within about
  5–20 min of an almanac. Illumination, age, phase name and the next new/full
  moon all derive from the sun–moon **elongation** of that model; the eight
  phase bins are centred on their events. `moonTimes` scans from local
  midnight to the next local midnight (DST-exact) and reports the **last**
  crossing of each kind. The distance is Meeus eq. 47 (385 000.56 km + the 20
  largest Σr terms of table 47.A); the 2025-11-05 perigee comes out at
  356 835 km against 356 833 km.
- **Eclipses** are a hand-curated table, not computed (NASA/Espenak). Each
  entry's date is the **UT instant of greatest eclipse**, rounded to the
  minute, so it lands on the right local day in every zone. The table must be
  extended before `eclipseTableCoverageEnd` (2035-09-02 01:56 UT).
- Time zones: pass the **location's** `TimeZone` to every per-day function.
  `Calendar` arithmetic is always Gregorian.

## 0.2 behaviour vs 0.1

0.1 kept Equinox's math wherever the three original implementations
disagreed; 0.2 takes Lunker's. Because 0.2 reproduces Lunker bit for bit (see
"Lunker"), the 0.2-vs-0.1 differences are the ones the 0.1 side-by-side
harness measured between Equinox and Lunker: every day of 2026 at Stockholm,
New York, Sydney, Tromsø, Kiruna and Honolulu, process time zone
Europe/Stockholm. The Otta column compares the original Otta code with 0.1;
Otta's sun math equals 0.1, so for Otta the sun rows of the 0.2 column apply.

| Quantity | 0.2 vs 0.1 | Otta (original) vs 0.1 | What 0.2 does |
|---|---|---|---|
| Sunrise/sunset | p50 0.7 min, p95 2.5 min, **max 13.7 min** (Tromsø, late Nov); 2 days where only one returns nil | identical | Lunker's day anchoring: declination and equation of time at local solar noon of the location's day (0.1: 0 h UT of the device-zone date). |
| Solar noon | p50 0.07 min, max 0.5 min | identical | Same cause. |
| Civil dawn | p50 0.7 min, max 12 min; 72 day-location pairs where only 0.2 has a value | identical | Same cause. `twilightBoundaries` and `goldenHourTimes` also report twilight and blue hour during **polar night**, where 0.1 returned nil. `twilightTimes` still returns nil when the sun does not rise (its `sunrise` is non-optional). |
| Solar elevation/azimuth | p50 0.06°, max 0.37° | p50 0.05°, max 0.13° (Otta drops the seconds field) | Declination and equation of time at the exact instant. |
| Subsolar point | lat max 0.18°, lon max 0.06° | — | At the instant (0.1: 0 h UT). Longitude now in [−180, 180). |
| `sunPath` | sample count on DST days (23 h: 139 at 10 min, 0.1: 145) | — | Samples to the next local midnight. |
| `polarCondition` | can differ on the 2 boundary days above | — | Derived from `polarState` (0.1 sampled the elevation at 12:00). |
| UV estimate | unchanged | 30°: AK 6.0 vs Otta 3.0; 10°: 2.1 vs 0.4 | Otta uses `12·sin²(elev)`, AstroKit `12·sin(elev)`. |
| `eventTime`, `eventTimeClampingPolar` | same shifts as sunrise/sunset | identical to 0.1 | Day-anchored like `sunTimes`. |
| Equinox/solstice dates | identical | identical | |
| Moon illumination | identical up to float rounding (0.1 dropped the sub-second part of the instant) | p50 0.008, max 0.026 | Otta uses Schlyter's lunar theory (12+5 perturbation terms). |
| Moon **phase name** | differs on 34/365 days | (vs 0.1) 36/365 days | From the elongation, bins centred on the events (0.1: linear mean age from the 2000-01-06 new moon, off by up to ~0.8 day). |
| Moon age | p50 0.34 d, p95 0.84 d | p50 0.34 d, p95 0.76 d | `age = elongation / 360° × synodic month`. Next full and new moon move by p50 8 h, p95 20 h. |
| Moon altitude | identical up to float rounding (same cause) | p50 0.7°, p95 2.2°, max 3.2° | Different lunar theory in Otta. |
| Moonrise/moonset | p50 0, p95 0.02 min; on a few days a different event (~24 h) | p50 7.6 min, p95 22 min; ~33 nil mismatches | Scan to the next local midnight (DST-exact) and keep the **last** crossing (0.1: fixed 1440 min, first crossing). The transit excludes the next-midnight sample. Rise altitude is unchanged at −0.12° (Otta: +0.125°). |
| Upper transit (`transits`) | identical | p50 6.8 min, p95 12.5 min | Different lunar theory in Otta (same scan method). |
| Lunar distance | p50 606 km, max 1030 km | — | Meeus' 385 000.56 km base and corrected terms (0.1: 384 400 km, `79.661·cos(2D−2F)` instead of `M−2F`, a duplicated `48.888·cos(Ms−M)`, `2D+M−Ms` instead of `2D−Ms−M`). Can flip `distanceStatus`/`isSupermoon` near thresholds. |
| Eclipse table | 49 entries, 0.1 had 44 | — | Adds 2025-03-29, 2025-09-21, 2026-02-17, 2026-03-03 and the 2027-07-18 penumbral eclipse. Dates are the UT greatest-eclipse instant (0.1: 12:00 device-local). 17 visibility strings were reworded. 2031-11-14 stays `.solarHybrid` (Lunker lists it as annular only because it had no hybrid case). |
| `upcomingEclipses(after:limit:)` | an eclipse drops out once its greatest instant passes (0.1: at 12:00 local) | — | Strictly after the instant, as before. |
| Non-Gregorian locales | — | — | Always Gregorian (fixes Otta's `Calendar.current` use under Buddhist/Japanese calendars). |

**Candidates for a later accuracy release** (each changes numbers for every
app, so re-baseline all apps' tests and the Android port together):

- the moon rise altitude sign: −0.12° subtracts parallax where it should add
  it (textbook +0.125°, as Otta uses). Lunker and Equinox both ship −0.12°, so
  0.2 keeps it; rises are a few minutes late.
- Otta's Schlyter lunar theory (12+5 perturbation terms) for positions and
  illumination
- Meeus' periodic-term correction for equinoxes/solstices
- `daylightHours(latitude:date:)` on the same day anchoring as `sunTimes`

## Adoption per app

The calculators are value types with static members. Adopting the package means
adding the package to every target that compiled the old file, deleting the old
file, and adding `import AstroKit` wherever the types are used.

### Lunker: easy, no behaviour change

0.2 is Lunker's math. A throwaway differential harness compiled Lunker's three
original files (unchanged copies, checksums verified) next to AstroKit 0.2 and
compared every function Lunker calls, for every day of 2026 at Stockholm, New
York, Sydney, Tromsø, Kiruna and Honolulu (each with its own time zone; four
instants per day including one with fractional seconds, plus hourly
positions), under process time zones Europe/Stockholm, America/Los_Angeles and
Pacific/Kiritimati, in release and debug builds: 5,367,685 comparisons, all
bit-identical (Dates exact, doubles to the bit) except the 2031-11-14 eclipse
type (`.solarHybrid` vs Lunker's `.solarAnnular`), which only a list of 100
upcoming eclipses reaches before 2031.

- **Replace:** `Lunker/Models/SolarCalculator.swift`,
  `Lunker/Models/MoonCalculator.swift`.
- **Slim down** `Lunker/Models/SolunarCalculator.swift` to its scoring layer.
  Keep `SolunarDay`, `SolunarPeriod` (with `periodScore`), `DayRating`,
  `ScoreFactors`, `scoreFactors(...)` and `computePeriodScore`. Get periods,
  moonrise and moonset from `Solunar.day(for:latitude:longitude:calendar:)`, map
  `Solunar.Period` to `SolunarPeriod`, and remove the private extrema scan.
  `nextStrongAlignment` can forward to `Solunar.nextStrongAlignment`. Move the
  `PeriodKind.displayName`/`caption` strings into a Lunker extension on
  `Solunar.PeriodKind` (or keep Lunker's enum and map it). The harness checked
  this slim layer too (score, rating, factors, period scores, active/next
  period): identical.
- **Link AstroKit into:** Lunker app, LunkerWidget, LunkerWatch Watch App and
  LunkerWatchWidget. All four compile `SolunarCalculator.swift`, which now
  imports AstroKit.
- **Call sites compile unchanged once imported** (checked by compiling them
  against 0.2): SunView and SunArcView (`PolarState`, `polarState`, `sunTimes`,
  `goldenHourTimes`, `solarPosition`, `solarElevation`, `sunPath`,
  `nextEvent(after:ofType:)`, `SolarEventType`), MoonView (`moonPhase`,
  `dayPhase`, `lunarDistance`, `moonTimes`,
  `upcomingEclipses(after:limit:calendar:)`), MoonPhaseVisual
  (`phase.isWaxing`), EclipseAlertCard, SolunarZoneMap (`lunarPosition`;
  `subsolarPoint(date:).latitude/.longitude` works because the struct has the
  tuple's member names), CatchInsights (`[MoonPhase: Int]`), TodayView,
  CalendarView, UpcomingDaysStrip (`dayPhase`, `moonPhase`, `lunarDistance`).
- **One semantic change to make:** `MoonPhase.icon` exists in AstroKit with
  Equinox's generic symbols (`moon.fill`, `moon.stars.fill`, `moon.haze.fill`,
  `moon.circle.fill`), so `day.phase.phase.icon` (MoonView) and `phase.icon`
  (CatchInsightsCard) would compile but show different symbols. Change them to
  `.symbolName`, which returns Lunker's `moonphase.*` symbols. (A Lunker-side
  `extension MoonCalculator.MoonPhase { var icon: String { symbolName } }`
  also compiles and wins inside Lunker's module, but shadowing a library
  member is fragile; prefer the rename.)
- **Strings:** eclipse visibility, phase and eclipse-type names are looked up
  in Lunker's main bundle with the same English keys. Add "Hybrid Solar
  Eclipse" to the catalog for the 2031-11-14 entry.
- **Watch out:** `EclipseType` gains `.solarHybrid`. Lunker has no exhaustive
  switch on it.
- **Tests:** LunkerTests' astronomy assertions are ported to
  `Tests/AstroKitTests/LunkerPortTests.swift`; delete them from LunkerTests
  and keep only the scoring tests (`scoreFactors`, `DayRating`, `fishCount`,
  day score). If you keep any: Lunker's all-optional `twilightTimes` is
  `twilightBoundaries` here, and `upcomingEclipses(after:limit:)` without a
  calendar resolves to the strictly-after variant (Lunker's defaulted to
  `calendar: .current`).

### Equinox: medium (drop-in API, numbers change)

Equinox pins `upToNextMinor(from: "0.1.0")`, so nothing changes until it opts
in to 0.2.

- **Replace / link:** as for 0.1 — `Equinox/Shared/SolarCalculator.swift` and
  `Equinox/Shared/MoonCalculator.swift`, compiled into four targets (app,
  widget, Watch app, Watch widget).
- **`import AstroKit` needed in 28 files:** Models/{NotificationManager,
  DoppelgangerCalculator, ChartDataGenerator, SunsetQualityForecaster,
  AuroraForecaster, SolarEventData, AlmanacStore, MoonEventData}; Views/{TwilightTimelineView,
  ARSunPathView, UVIndexView, SolarEclipseCard, MoonPhaseCard, SolarView,
  LocationDashboardCard, ZodiacPositionCard, MoonDistanceCard, DoppelgangerView,
  EclipseAlertCard, MoonArcView, SunGlobeView, MoonTimesCard};
  Widget/{MoonPhaseWidget, SunTimesWidget}; EquinoxWatch/WatchContentView;
  EquinoxWatchWidget/{MoonPhaseComplication, NextSunEventComplication};
  WatchShared/WatchAstronomy (its `MoonPhase.watchSymbolName` extension still
  compiles).
- **API:** source-compatible with 0.1 (everything is additive). `icon` keeps
  Equinox's symbols.
- **Behaviour changes** (see "0.2 behaviour vs 0.1"): sun times ~1 min (up to
  14 near polar night) and now independent of the device zone; polar-night
  golden/blue hour now reported by `goldenHourTimes` (`twilightTimes` is still
  nil then); phase name on ~1 day in 10, age and next full/new moon by hours;
  lunar distance ~+600 km (status/supermoon can flip near thresholds); last
  instead of first moonrise/moonset, DST-exact scan; eclipse dates at the UT
  instant of greatest eclipse (the local date shown can be a day earlier or
  later than 0.1's 12:00-local date in far-west/far-east zones); five more
  eclipses in the list; 2028–2035 visibility strings reworded.
- **What to re-baseline:**
  - The eight Equinox-origin tests re-baselined here (see CHANGELOG):
    `test_upcomingEclipses_firstLunarEclipse2025_march14`,
    `test_upcomingEclipses_before2025_includesAllKnown`,
    `test_moonTimes_dailyProgression_shiftsLater`,
    the two `test_moonPhase_knownFullMoon…` tests, the two age tests and
    `test_lunarDistance_averageDistanceCorrect`. Apply the same edits to any
    copies still in EquinoxTests.
  - Re-run `SunsetQualityForecasterTests` and `AuroraForecastTests`; they use
    sun times indirectly.
  - Snapshot or screenshot fixtures that show sun/moon times, phase names,
    distances or eclipse dates.
  - **String catalog:** new visibility keys (the reworded 2028–2035 strings and
    the five new entries) fall back to English until translated, and "Hybrid
    Solar Eclipse" is unchanged.
- **Android:** the Kotlin port (`EquinoxAndroid/…/SolarCalculator.kt`,
  `MoonCalculator.kt`) still has 0.1's math, so after the iOS app moves to 0.2
  the two platforms show different numbers (sun times by ~1 min, up to 14 min
  near polar night; phase names on ~1 day in 10; distance by ~600 km; eclipse
  dates and table). Port the 0.2 changes by hand (day anchoring, instant-based
  elevation, elongation-based age/phase, Meeus distance terms, last-crossing
  DST-exact moon times, eclipse table with UT instants) and update
  `SolarCalculatorTest.kt` at the same time.

### Otta: medium (mostly mechanical renames)

- **Replace:** `Otta/Models/SolarCalculator.swift` (drop-in, including
  `eventTimeClampingPolar`) and `Otta/Models/LunarCalculator.swift` (replaced by
  `MoonCalculator`, which needs renames). **Keep**
  `Otta/Services/SolunarPredictor.swift`, which is Otta's rating, and point it
  at `MoonCalculator`.
- **Link AstroKit into:** Otta app and OttaWidget. `WidgetModels.swift` and
  `WidgetSolunar.swift` use these types.
- **SolarCalculator call sites (unchanged once imported):**
  `OttaResolver.swift` (`EquinoxSolarTimeProvider` → `eventTimeClampingPolar`),
  `OttaWidget/WidgetModels.swift:221`, `Views/Today/TodayView.swift:267`,
  `Views/Today/TodayDetailsView.swift:34` (`sunTimes`).
- **LunarCalculator → MoonCalculator renames:**
  - `LunarCalculator.phase(on:)` → `MoonCalculator.moonPhase(for:)`:
    SolunarPredictor.swift:96, OttaWidget/WidgetSolunar.swift:22
  - `LunarCalculator.MoonPhase` (struct) → `MoonCalculator.MoonPhaseInfo`.
    `.illuminatedFraction`, `.phaseAngle`, `.age` and `.phase` keep their names.
    Sites: SolunarPredictor.swift:62,175; BestTimesPredictor.swift:117;
    SolunarViews.swift:35,233
  - `LunarCalculator.Phase` → `MoonCalculator.MoonPhase`. The case names match;
    the raw values differ (`"New Moon"` vs `"newMoon"`) but Otta never uses raw
    values. Sites: SolunarViews.swift:6, WidgetSolunar.swift:35
  - `LunarCalculator.transits(...)` → `MoonCalculator.transits(...)`.
    `.upper` and `.lower` are unchanged. Sites: SolunarPredictor.swift:106,
    WidgetSolunar.swift:26
  - `LunarCalculator.moonTimes(...)` → `MoonCalculator.moonTimes(...)`. It
    gains `transitTime`. Site: SolunarPredictor.swift:110
  - `LunarCalculator.moonPosition` → `MoonCalculator.moonPosition`, which has
    the same shape. Otta has no external callers.
- **Name clashes:**
  - `extension LunarCalculator.Phase { var localizedName }` in
    `SolunarViews.swift` collides with AstroKit's `MoonPhase.localizedName`,
    which uses Equinox's English keys. Rename Otta's to
    `solunarLocalizedName` (it uses the `solunar.phase.*` keys) and update the
    two `day.phase.localizedName` uses.
  - **0.2:** Otta's `extension LunarCalculator.Phase { var symbolName }`
    returns exactly AstroKit's new `MoonPhase.symbolName` values; delete it.
- **Behaviour changes:**
  - the moon model switches from Schlyter to the simplified Meeus model:
    moonrise/moonset p50 ±8 min, transits p50 ±7 min, illumination ±0.03, phase
    name on ~1 day in 10
  - sun times move like Equinox's (0.2 day anchoring: ~1 min, up to 14 min near
    polar night), and are now correct under non-Gregorian calendars
  - Otta's 0…4 rating can move by 1 on borderline days
  - the UV estimate rises (sin instead of sin²), though no Otta call site uses
    UV
- **Tests:** OttaTests `SolarCalculatorTests` should pass with its tolerances
  (re-check the DST and polar fixtures). Its `testUVIndexIncreasesWithElevation`
  only checks that UV increases. `LunarCalculatorTests` move here (see
  `AdditionsTests.swift`); its rise-altitude check (`0.125 ± 0.4`) would need
  −0.12. `SolunarPredictorTests` stays in Otta.

## Layout

```
Sources/AstroKit/SolarCalculator.swift      NOAA/Meeus sun (Lunker's math, Equinox's API + polarState/twilightBoundaries + eventTimeClampingPolar)
Sources/AstroKit/MoonCalculator.swift       Meeus moon (Lunker's math, Equinox's API + transits/moonPosition/phaseAngle + dayPhase/symbolName + eclipse helpers)
Sources/AstroKit/Solunar.swift              Knight solunar periods (Lunker, scoring removed)
Tests/AstroKitTests/Equinox/                Equinox's Solar/Moon XCTest suites + fixtures (eight tests re-baselined for 0.2)
Tests/AstroKitTests/AdditionsTests.swift    Swift Testing suites for the added API (from Lunker/Otta)
Tests/AstroKitTests/LunkerPortTests.swift   Lunker's astronomy tests, ported to Swift Testing
```
