# AstroKit

Sun, moon and solunar astronomy for the Apps-AppStore family, shared by
**Equinox**, **Lunker** and **Otta**. It is pure Foundation, with no
dependencies, no resources, no networking and no backend. All entry points are
static, `Sendable` and deterministic. That means the repo can be **public**:
Xcode Cloud resolves it without a GitHub token or deploy key:
`.package(url: "https://github.com/Cliefden/AstroKit.git", from: "0.1.0")`.

- swift-tools 6.0, Swift 6 language mode
- iOS 17 / watchOS 10 / macOS 14 / visionOS 1
- Tests: 163 XCTest cases (ported unchanged from Equinox) plus 31 Swift Testing
  cases (for the API added for Lunker and Otta). Run them with `swift test`.

The math comes from **Equinox's** `Shared/SolarCalculator.swift` and
`Shared/MoonCalculator.swift`. Equinox was the most complete of the three and
had the most tests, and its algorithms are kept verbatim. The public API is a
**superset** of what the three apps call, so in most files adopting it only
means adding `import AstroKit`.

The **Kotlin port in Equinox Android (`EquinoxAndroid/`) stays separate.** It is
not generated from this package. When an algorithm changes here, port the change
to Kotlin by hand, as Equinox's CLAUDE.md already requires.

## API overview

### `SolarCalculator` (NOAA solar calculator + Meeus equinox/solstice)

| Member | Notes |
|---|---|
| `solarEvent(_:year:)`, `allEvents(year:)` | Meeus equinox/solstice JDE. Cached per year behind an `NSLock`. |
| `lastEvent(before:ofType:)`, `nextEvent(after:ofType:)` | Optional type filter. Passing an empty filter is a precondition failure. |
| `lastEquinox/nextEquinox/lastSolstice/nextSolstice` | |
| `solsticeMirrorDate(for:)` | The date with the same daylight on the other side of the next solstice. |
| `sunTimes(date:latitude:longitude:timeZone:) -> SunTimes?` | Sunrise, sunset, solar noon and `daylightDuration`. Returns nil at the poles. |
| `polarCondition(...) -> PolarCondition?` | `.midnightSun` / `.polarNight` (Equinox naming). |
| `polarState(...) -> PolarState?` | `.polarDay` / `.polarNight` (Lunker naming). Non-nil exactly when `sunTimes` is nil. |
| `twilightTimes(...) -> TwilightTimes?` | Civil 96°, nautical 102°, astronomical 108°. Returns nil when there is no sunrise. |
| `goldenHourTimes(...) -> GoldenHourTimes?` | Blue hour −6°…−4°, golden hour −4°…+6°, with durations. |
| `eventTime(date:…zenith:isSunrise:timeZone:) -> Date?` | Crossing time for any zenith angle. |
| `eventTimeClampingPolar(...) -> Date` | From Otta. Never nil: in polar day it returns noon ± 12 h, in polar night it returns solar noon. Used for legal hunting hours. |
| `solarElevation(at:…)`, `solarPosition(at:…) -> SunPosition` | Elevation, plus azimuth clockwise from north. |
| `sunPath(date:…intervalMinutes:timeZone:)` | Sun positions sampled across the local day. |
| `maxSolarElevation`, `estimateUVIndex(elevation:)`, `uvLevel(from:)`, `UVLevel` | |
| `subsolarPoint(date:) -> SubsolarPoint`, `daylightHours(latitude:date:)` | |

### `MoonCalculator` (Meeus, simplified)

| Member | Notes |
|---|---|
| `moonPhase(for:) -> MoonPhaseInfo` | Contains `phase` (8 named phases), `illumination` (alias `illuminatedFraction`), `age`, **`phaseAngle`** (sun→moon elongation, added for Otta), `nextNewMoon`, `nextFullMoon` and `synodicMonth`. |
| `moonTimes(...) -> MoonTimes` | Moonrise, moonset and `transitTime` (the highest 5-minute sample). |
| `transits(...) -> MoonTransits` | From Otta. Upper (overhead) and lower (underfoot) meridian transits, from a 6-minute scan with parabolic refinement. |
| `lunarPosition(at:…) -> LunarPosition` | Ecliptic longitude, RA/Dec, altitude/azimuth and zodiac sign. |
| `moonPosition(at:…) -> MoonPosition` | From Otta. Elevation and azimuth in the same shape as `SunPosition`. |
| `lunarDistance(for:) -> LunarDistanceInfo` | Distance in km, perigee/apogee status, next perigee and apogee, supermoon flag. |
| `upcomingEclipses(after:limit:)` | Built-in table covering 2025–2035. Returns eclipses strictly after the given instant. |
| `upcomingEclipses(after:limit:calendar:)` | From Lunker. Keeps an eclipse listed for its whole calendar day. |
| `eclipseTableCoverageEnd` | From Lunker. Lets tests catch a table that has run out. |
| `EclipseEvent` | Now `Identifiable`, with the stable id `type@date`. Enums: `MoonPhase`, `ZodiacConstellation`, `LunarDistanceStatus`, `EclipseType` (includes `.solarHybrid`). |

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

`localizedName` and `description` on the enums look up their **English
`rawValue` keys in the host app's main bundle**
(`NSLocalizedString(_, bundle: .main)` / `String(localized:bundle: .main)`).
These are the same keys Equinox and Lunker already have in their string
catalogs, so existing translations keep working. Xcode no longer *extracts*
those keys from app code, so it may mark them "stale". Keep them in the catalog
anyway. The package has no string catalog of its own.

## Accuracy notes

- **Sun:** NOAA's low-precision series. Sunrise and sunset are within about
  1–2 min of USNO/NOAA at mid-latitudes, as covered by the tests. Declination
  and the equation of time are evaluated at **0 h UT of the Gregorian date of
  `date` in the device time zone**, which is Equinox's behaviour. Near the
  polar-day and polar-night boundary this can move sunrise or sunset by up to
  about 14 min compared with evaluating at solar noon (see the discrepancy
  table). Equinoxes and solstices use Meeus' mean-JDE polynomials, with
  results truncated to the minute. That is within about 1–2 min of USNO for
  2000–2050, without the periodic-term correction.
- **Moon:** Equinox's simplified Meeus model, with 5 longitude terms and one
  latitude term. Expect positions within 1–3° and moonrise/moonset within about
  5–20 min of an almanac. The phase name comes from a linear mean-lunation age
  measured from the 2000-01-06 new moon. Illumination comes from the true
  sun–moon elongation of the same simplified model. `moonTimes` scans exactly
  1440 min from local midnight and reports the *first* crossing of each kind.
- **Eclipses** are a hand-curated table, not computed. Each entry's date is
  12:00 device-local time on the eclipse day. The table must be extended before
  `eclipseTableCoverageEnd` (2035-09-02).
- Time zones: pass the **location's** `TimeZone` to every per-day function.
  `Calendar` arithmetic is always Gregorian.

## Numeric discrepancies between the three original implementations

Where two implementations disagreed, **Equinox's numbers were kept**, as
instructed. The figures below come from a side-by-side harness that ran the
original files from all three apps over every day of 2026 at Stockholm,
New York, Sydney, Tromsø, Kiruna and Honolulu, with the process time zone set to
Europe/Stockholm. "AK" means AstroKit, which equals Equinox.

| Quantity | AK vs Lunker | AK vs Otta | Cause |
|---|---|---|---|
| Sunrise/sunset | p50 0.7 min, p95 2.5 min, **max 13.7 min** (Tromsø, late Nov); 2 days where only one returns nil | identical | Lunker's `DayAnchor` evaluates declination and equation of time at local solar noon and anchors to the location's day. Equinox evaluates them at 0 h UT of the device-zone date. |
| Solar noon | p50 0.07 min, max 0.5 min | identical | Same cause. |
| Civil dawn | p50 0.7 min, max 12 min; 72 day-location pairs where only Lunker has a value | identical | Same cause. Lunker also reports twilight and blue hour during **polar night**, where Equinox and AstroKit return nil. |
| Solar elevation | p50 0.06°, max 0.37° | p50 0.05°, max 0.13° | Lunker evaluates declination at the exact instant. Otta drops the seconds field. |
| UV estimate | — | 30°: AK 6.0 vs Otta 3.0; 10°: 2.1 vs 0.4 | Otta uses `12·sin²(elev)`, Equinox uses `12·sin(elev)`. |
| `eventTimeClampingPolar` | — | identical | Ported unchanged. |
| Subsolar point | lat max 0.18°, lon max 0.06° | — | Lunker evaluates at the instant, Equinox at 0 h UT. Lunker returns a tuple, AK a struct; `.latitude` and `.longitude` work with both. |
| Equinox/solstice dates | identical | identical (same code) | |
| Moon illumination | identical | p50 0.008, max 0.026 | Otta uses Schlyter's lunar theory (12+5 perturbation terms). |
| Moon **phase name** | differs on 34/365 days | differs on 36/365 days | Lunker and Otta derive the name from elongation. Equinox uses the linear mean age, which can be off by up to about 0.8 day. |
| Moon age | p50 0.34 d, p95 0.84 d | p50 0.34 d, p95 0.76 d | Same cause. Next full and new moon move by p50 8 h, p95 20 h. |
| Moon altitude | identical | p50 0.7°, p95 2.2°, max 3.2° | Different lunar theory. |
| Moonrise/moonset | p50 0, p95 0.02 min; on a few days a different event (~24 h) | p50 7.6 min, p95 22 min; ~33 nil mismatches | Lunker scans to the next local midnight (DST-exact) and keeps the **last** crossing. Otta uses Schlyter positions and a rise altitude of **+0.125°**. Equinox uses **−0.12°**: it subtracts parallax where it should add it, so its rises are a few minutes late. |
| Upper transit | — | p50 6.8 min, p95 12.5 min | Different lunar theory (same scan method). |
| Lunar distance | p50 606 km, max 1030 km | — | Lunker uses Meeus' 385 000.56 km base and corrected terms. Equinox uses 384 400 km, `79.661·cos(2D−2F)` (should be `M−2F`) and a duplicated `48.888·cos(Ms−M)`. |
| Eclipse table | Lunker has 49 entries, Equinox 44 | — | Lunker also has 2025-03-29, 2025-09-21, 2026-02-17 and 2026-03-03. All four are before Oct 2026, so the upcoming lists are unaffected. Lunker includes the 2027-07-18 penumbral eclipse, which Equinox deliberately leaves out. 2031-11-14 is `.solarHybrid` in Equinox and `.solarAnnular` in Lunker. Lunker stores the greatest-eclipse UT instant, Equinox 12:00 device-local. |
| Non-Gregorian locales | — | — | Otta's `SolarCalculator` uses `Calendar.current`, which gives wrong years under Buddhist or Japanese calendars. AK is always Gregorian, so this is a bug fix for Otta. |

**Candidates for a 0.2 accuracy release** (they change Equinox's numbers, so
re-baseline Equinox's tests and the Android port at the same time):

- Lunker's day anchoring for sun times
- the moon rise altitude sign
- Lunker's distance series
- elongation-based phase names
- Lunker's DST-exact last-crossing moon times and polar-night twilight
- the four missing eclipses with UT instants

## Adoption per app

The calculators are value types with static members. Adopting the package means
adding the package to every target that compiled the old file, deleting the old
file, and adding `import AstroKit` wherever the types are used.

### Equinox: easy (drop-in)

- **Replace:** `Equinox/Shared/SolarCalculator.swift`,
  `Equinox/Shared/MoonCalculator.swift`. They are compiled into four targets
  (app, widget, Watch app, Watch widget), so add the package product to all
  four.
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
- **Behaviour:** identical. Results are bit-for-bit the same apart from summation order in
  `lunarDistance`. `upcomingEclipses(limit: 0)` now returns `[]`; the original
  returned one element.
- **Tests:** the Solar/ and Moon/ suites now live here
  (`Tests/AstroKitTests/Equinox/`). Delete them from EquinoxTests, or keep them
  with `@testable import AstroKit`.
- **Android:** no change. The Kotlin port stays separate.

### Lunker: medium

- **Replace:** `Lunker/Models/SolarCalculator.swift`,
  `Lunker/Models/MoonCalculator.swift`.
- **Slim down** `Lunker/Models/SolunarCalculator.swift` to its scoring layer.
  Keep `SolunarDay`, `SolunarPeriod` (with `periodScore`), `DayRating`,
  `ScoreFactors`, `scoreFactors(...)` and `computePeriodScore`. Get periods,
  moonrise and moonset from `Solunar.day(for:latitude:longitude:calendar:)`, map
  `Solunar.Period` to `SolunarPeriod`, and remove the private extrema scan.
  `nextStrongAlignment` can forward to `Solunar.nextStrongAlignment`. Move the
  `PeriodKind.displayName`/`caption` strings into a Lunker extension on
  `Solunar.PeriodKind` (or keep Lunker's enum and map it).
- **Link AstroKit into:** Lunker app, LunkerWidget, LunkerWatch Watch App and
  LunkerWatchWidget. All four compile `SolunarCalculator.swift`, which now
  imports AstroKit.
- **Call sites that compile unchanged once imported:**
  - SunView and SunArcView (`PolarState`, `polarState`, `sunTimes`,
    `goldenHourTimes`, `solarPosition`, `sunPath`, `nextEvent`, `SolarEventType`)
  - MoonView (`moonPhase`, `lunarDistance`, `moonTimes`,
    `upcomingEclipses(after:limit:calendar:)`, `MoonPhaseInfo`, `MoonTimes`,
    `LunarDistanceInfo`, `EclipseEvent`)
  - EclipseAlertCard (`EclipseEvent`, `type.localizedName`)
  - SolunarZoneMap (`lunarPosition`; `subsolarPoint(date:).latitude/.longitude`
    still works because the struct has the same property names)
  - CatchInsights (`MoonPhase`, `moonPhase`)
  - TodayView (`moonPhase`, `lunarDistance`)
- **Behaviour changes** (Lunker loses its own accuracy fixes, see the table):
  - sun times move by ~1 min (up to 14 near polar night)
  - phase names change on ~1 day in 10
  - lunar distance shifts by about −600 km, which can move the distance score
    factor by about 1 of its 30 points
  - golden and blue hour are no longer reported on polar-night days
  - `moonTimes` reports the first crossing and a fixed 24 h scan instead of the
    last crossing and a DST-exact scan
  - eclipse dates are 12:00 local instead of the UT instant
- **Tests that will need re-baselining or removal** in LunkerTests:
  - DST-day solar-noon independence
  - `testSunPathSpansShortDstDay`
  - `testTwilightExistsDuringTromsoPolarNight`
  - `testMoonTimesStayWithinShortDstDay`
  - moonrise/moonset last-crossing assertions
  - eclipse greatest-instant and far-east-zone tests
  - `testEclipseTableCoversThrough2035` (the end is now 2035-09-02 12:00
    device-local)

  The remaining Solunar tests have equivalents here.
- **Watch out:** `EclipseType` gains `.solarHybrid`. Lunker currently has no
  exhaustive switch on it.

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
- **Name clash:** `extension LunarCalculator.Phase { var localizedName }` in
  `SolunarViews.swift` collides with AstroKit's `MoonPhase.localizedName`, which
  uses Equinox's English keys. Rename Otta's to `solunarLocalizedName` (it uses
  the `solunar.phase.*` keys) and update the two `day.phase.localizedName`
  uses. `symbolName` has no clash.
- **Behaviour changes:**
  - the moon model switches from Schlyter to the simplified Meeus model:
    moonrise/moonset p50 ±8 min, transits p50 ±7 min, illumination ±0.03, phase
    name on ~1 day in 10
  - Otta's 0…4 rating can move by 1 on borderline days
  - the UV estimate rises (sin instead of sin²), though no Otta call site uses
    UV
  - sun times are unchanged, and are now correct under non-Gregorian calendars
- **Tests:** OttaTests `SolarCalculatorTests` should pass unchanged. Its
  `testUVIndexIncreasesWithElevation` only checks that UV increases.
  `LunarCalculatorTests` move here (see `AdditionsTests.swift`); its
  rise-altitude check (`0.125 ± 0.4`) would need −0.12. `SolunarPredictorTests`
  stays in Otta.

## Layout

```
Sources/AstroKit/SolarCalculator.swift   NOAA/Meeus sun (Equinox + polarState + eventTimeClampingPolar)
Sources/AstroKit/MoonCalculator.swift    Meeus moon (Equinox + transits/moonPosition/phaseAngle + eclipse helpers)
Sources/AstroKit/Solunar.swift           Knight solunar periods (Lunker, scoring removed)
Tests/AstroKitTests/Equinox/             Equinox's Solar/Moon XCTest suites + fixtures (verbatim)
Tests/AstroKitTests/AdditionsTests.swift Swift Testing suites for the added API (from Lunker/Otta)
```
