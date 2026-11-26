# Changelog

AstroKit follows semantic versioning; while it is 0.x, a minor release may
change numbers. Apps pin `upToNextMinor`, so they opt in to each minor release
explicitly.

## 0.2.0 — 2026-11-26

Adopts **Lunker's** math wherever the three original implementations
disagreed (0.1 kept Equinox's). Lunker can now replace its own calculators
with no change in its numbers: a differential harness compiling Lunker's
original files next to 0.2 found every compared value bit-identical across
every day of 2026 at six locations and three process time zones (5.37 M
comparisons; the only difference is the 2031-11-14 eclipse type, below).
**Equinox's and Otta's numbers change** when they move to 0.2; see README
"0.2 behaviour vs 0.1" for magnitudes and "Equinox" for what to re-baseline.
The public API is source-compatible with 0.1 (all changes are additive).

### Changed (numbers)

- **Sun times are anchored to the location's calendar day.** `sunTimes`,
  `polarState`, `polarCondition`, `twilightTimes`, `goldenHourTimes`,
  `eventTime` and `eventTimeClampingPolar` evaluate declination and the
  equation of time at the local solar noon of the day containing `date` in the
  given `timeZone`, and add UTC minutes to UTC midnight. Results no longer
  depend on the device time zone or the time of day passed in, and are exact on
  23 h/25 h DST days. Sunrise/sunset move p50 0.7 min, max ~14 min near polar
  night.
- `polarCondition` is now derived from `polarState`, so the two always agree.
- **Golden/blue hour during polar night:** `goldenHourTimes` returns the
  boundaries that do occur (e.g. blue hour at Tromsø in December) instead of
  nil. It is nil only when no boundary is crossed.
- `solarElevation`, `solarPosition`, `sunPath` and `subsolarPoint` evaluate
  declination and the equation of time at the exact instant (0.1: 0 h UT of
  the date). `subsolarPoint` longitude is in [−180, 180).
- `sunPath` samples from local midnight to the next local midnight (23 h/25 h
  on DST days) instead of a fixed 24 h.
- `lastEvent`/`nextEvent` take the year from UTC (0.1: device zone). The
  results are the same.
- **Moon phase name, age and next new/full moon** derive from the sun–moon
  elongation (as illumination already did); the eight bins are centred on
  their events. The name changes on ~1 day in 10, age by p50 0.34 d.
- **Moonrise/moonset** scan to the next local midnight (DST-exact) and keep
  the **last** crossing of each kind; `transitTime` excludes the
  next-midnight sample. The rise altitude stays at −0.12°.
- **Lunar distance** uses Meeus eq. 47 (385 000.56 km base, corrected terms
  `79.661·cos(M−2F)` and `−152.138·cos(2D−Ms−M)`, no duplicated `48.888` term,
  seven more terms). About +600 km; `distanceStatus`/`isSupermoon` can flip
  near thresholds.
- The julian day of an instant keeps its sub-second part (moon calculations).
- **Eclipse table** (Lunker's): each `date` is the UT instant of greatest
  eclipse (0.1: 12:00 device-local), so it lands on the right local day in
  every zone. Adds 2025-03-29, 2025-09-21, 2026-02-17, 2026-03-03 and the
  2027-07-18 penumbral eclipse (49 entries; 0.1 had 44). 17 visibility strings
  were reworded; visibility is now looked up in the host app's main bundle.
  2031-11-14 stays `.solarHybrid` (Lunker lists it as annular because it has no
  hybrid case). `eclipseTableCoverageEnd` is 2035-09-02 01:56 UT.

### Added

- `SolarCalculator.twilightBoundaries(date:latitude:longitude:timeZone:)` and
  `SolarCalculator.TwilightBoundaries`: Lunker's all-optional twilight, which
  also reports twilight during polar night. (`twilightTimes` keeps its
  non-optional `sunrise`/`sunset` and still returns nil when the sun does not
  rise.)
- `MoonCalculator.dayPhase(for:)`: the phase at the day's midday (from
  Lunker).
- `MoonCalculator.MoonPhase.symbolName`: the phase-accurate `moonphase.*` SF
  Symbol. `icon` keeps Equinox's generic symbols.
- `MoonCalculator.MoonPhase.isWaxing`.
- `Tests/AstroKitTests/LunkerPortTests.swift`: Lunker's astronomy tests,
  ported to Swift Testing.

### Tests re-baselined (Equinox-origin, `Tests/AstroKitTests/Equinox`)

- `EclipseTests.test_upcomingEclipses_firstLunarEclipse2025_march14`: expects
  the greatest-eclipse instant 2025-03-14 06:59 UT and checks the day in UTC
  (it read `Calendar.current`, and west of UTC−7 the local date of the UT
  instant is March 13).
- `EclipseTests.test_upcomingEclipses_before2025_includesAllKnown`: also pins
  the whole table at 49 entries (was 44).
- `MoonTimesTests.test_moonTimes_dailyProgression_shiftsLater`: scans New
  York's own day and reads hours in New York's zone. It used the process time
  zone and failed under `TZ=America/Los_Angeles` in 0.1 as well.
- `MoonPhaseTests.test_moonPhase_knownFullMoonJan2025_returnsNearFullMoon` and
  `…Feb2025…`: expect exactly `.fullMoon` (0.1 accepted the gibbous
  neighbours because the name came from the mean-lunation age).
- `MoonPhaseTests.test_moonPhase_fullMoon_ageNear15Days`: tolerance 2 d →
  0.5 d (age is now 14.96 d at the full-moon instant; 0.1 gave 14.22 d).
- `MoonPhaseTests.test_moonPhase_newMoon_ageNearZero`: also requires the age
  to be within 0.5 d of the wrap (29.34 d; 0.1 gave 0.28 d).
- `LunarDistanceTests.test_lunarDistance_averageDistanceCorrect`: also checks
  the three-year mean against the series' base, 385 000.56 ± 150 km (0.2:
  384 953 km; 0.1's was 384 350 km on a 384 400 km base).
- Extended: `TwilightTests.test_twilightTimes_polarRegion_returnsNil` also
  checks `twilightBoundaries` (nil too in midnight sun at 78°N).

All Equinox-origin tests pass under `TZ=Europe/Stockholm`,
`America/Los_Angeles` and `Pacific/Kiritimati`.

## 0.1.0 — 2026-10-27

First release. Sun, moon and solunar astronomy extracted from Equinox's
`SolarCalculator`/`MoonCalculator` (algorithms kept verbatim), with the API a
superset of what Equinox, Lunker and Otta call:

- `SolarCalculator`: NOAA sun times, twilight, golden hour, elevation/azimuth,
  sun path, UV estimate, subsolar point, Meeus equinoxes/solstices; plus
  `polarState` (Lunker) and `eventTimeClampingPolar` (Otta).
- `MoonCalculator`: phase, illumination, moon times, position, distance,
  eclipse table 2025–2035; plus `phaseAngle`/`illuminatedFraction`,
  `transits` and `moonPosition` (Otta), and
  `upcomingEclipses(after:limit:calendar:)`, `eclipseTableCoverageEnd` and
  `EclipseEvent: Identifiable` (Lunker).
- `Solunar`: Knight's solunar periods from Lunker's `SolunarCalculator`,
  without the fishing/hunting score.
- Equinox's 163 Solar/Moon XCTest cases plus Swift Testing suites for the
  added API.
