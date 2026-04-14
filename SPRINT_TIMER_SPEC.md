# Sprint Timer - Product Spec & Roadmap

**Apple Watch sprint timing app with iOS companion**
*Last updated: 2026-04-12*

---

## What's Built (Verified in Code)

### Watch App - Core Timer
- [x] Distance selection (100m, 200m, 400m) on home screen
- [x] Settings button from home screen
- [x] Big "Start Run" button (readable without glasses)
- [x] Three start modes: Tap (instant), Countdown (with beeps/vibration), Motion Detection (accelerometer)
- [x] Configurable countdown time (10, 15, 20, 30 seconds)
- [x] Timer display with millisecond precision (M:SS.mmm), large font
- [x] Long-press (1.5s) to stop/save - shows Save, Save w/Notes, or Delete
- [x] Outlier detection (flags times >50% slower or <60% of median)
- [x] Icon for watch

### Watch App - History & Notes
- [x] History screen with runs grouped by day
- [x] Day detail view with per-run breakdown and stats
- [x] Distance filtering (100m / 200m / 400m / All)
- [x] Per-run notes (watch keyboard input)
- [x] Per-day notes
- [x] Notes icons (blue = has notes, gray = empty)

### Watch App - Settings
- [x] Start mode picker (countdown / motion / tap)
- [x] Countdown time picker
- [x] GPS toggle
- [x] HealthKit toggle
- [x] Weather toggle (enabled when API key is configured)
- [x] Altitude tracking toggle
- [x] Save tap time / GPS time toggles
- [x] Debug info section (collapsible)

### iOS Companion App
- [x] Tab bar: Home, History, Settings, Export
- [x] Home screen with recent runs summary and total stats
- [x] History grouped by day with stats (count, average)
- [x] Distance filtering on history
- [x] Edit run notes and day notes
- [x] Swipe-to-delete runs
- [x] Settings synced with watch (all 8 toggles)
- [x] Export to CSV and JSON with configurable field toggles
- [x] Debug tools (add test data, clear data, refresh)
- [x] Icon

### Data & Sync
- [x] SwiftData persistence (shared via App Group)
- [x] WatchConnectivity bidirectional sync (settings, runs, deletions, notes)
- [x] Offline queuing (transferUserInfo fallback when not reachable)
- [x] Full sync on app activation

### Health Data
- [x] Start heart rate (at timer start)
- [x] End heart rate (at timer stop)
- [x] Steps during run
- [x] Stride length (calculated: distance / steps)
- [x] Average heart rate during run
- [x] Max heart rate during run

### GPS & Location
- [x] Latitude / Longitude captured at stop
- [x] Altitude captured
- [x] Actual distance calculation from GPS route tracking
- [x] Average speed calculation
- [x] Altitude gain (cumulative positive altitude change)
- [x] Location name via reverse geocoding

---

## Bugs & Issues Found in Code

1. **Weather toggle does nothing** - `trackWeather` setting is saved/synced but no code ever collects weather data. Toggle misleads users.
2. **GPS "actual distance" never calculated** - Location is captured at stop but no route tracking or distance calculation exists.
3. **Average/Max HR never collected** - Model fields exist but HealthKit queries for these aren't implemented.
4. **Location name never populated** - Export tries to extract it from notes strings as a workaround (fragile).
5. **Export weather columns are always empty** - Export UI has weather toggles but all weather fields are nil.
6. **WatchTextInput.swift appears unused** - NotesView uses TextField directly instead.
7. **No test coverage** - Both test files are empty stubs.
8. **Long white blank screen on iPhone at startup** - Reported but cause not yet diagnosed (likely SwiftData initialization or sync blocking main thread).
9. **Export may hang on second run** - Reported; possibly a threading/ShareSheet lifecycle issue.

---

## Roadmap

### Phase 1: Fix Bugs & Polish What's Built
*Get the existing features working correctly before adding new ones.*

- [x] **Fix iPhone startup blank screen** - Added loading view during SwiftData init
- [x] **Fix export double-run hang** - Switched to item-based sheet presentation, cleanup temp files
- [x] **Complete health data collection** - Added average HR and max HR queries during run window
- [x] **Complete GPS distance/speed** - Track location samples during run, calculate actual distance and speed
- [x] **Add altitude gain calculation** - Track cumulative positive altitude change during run
- [x] **Add reverse geocoding** - Convert lat/long to human-readable location name (e.g. "Northampton, MA")
- [x] **Remove or disable weather toggle** until Phase 3 (hidden from settings, default off)
- [x] **Remove unused WatchTextInput.swift**
- [x] **Going back to home screen should stop and reset timer**

### Phase 2: User Experience Improvements
*Notes workflow, custom runs, navigation fixes.*

- [x] **Post-run notes flow** - After every run, prompt for optional notes before returning to home
  - [x] Default to dictation input (minimize taps)
  - [ ] Christine: Should notes prompt appear on all runs or only on long-press? Decide and implement
- [ ] **Christine: Layout of notes button on history screen** - Review and improve placement/visibility
- [x] **Custom run types** - Add ability to create runs with custom name + distance (e.g. "400m Hurdles", "Backwards 100m")
  - [x] Settings UI on iOS to manage custom run types
  - [x] Sync custom types to watch
  - [x] Update distance picker on watch
- [x] **Tutorial / onboarding** - Brief explanation of long-press to stop, start modes, etc.

### Phase 3: Weather & Environment Data
*Requires OpenWeather API key - enter in iOS Settings.*

- [ ] **Sign up for OpenWeather API** (must be done from US - openweather.com)
- [x] **Implement WeatherService** - API calls for current conditions at GPS location
- [x] **Capture with each run:**
  - [x] Temperature & feels-like
  - [x] Humidity & barometric pressure
  - [x] Wind speed & direction
  - [x] Air Quality Index (AQI)
  - [x] UV Index
  - [x] Weather condition (sunny, rain, etc.)
- [x] **Update export to include all weather fields**
- [x] **API key input in iOS Settings** - weather toggle re-enabled when key is present

### Phase 4: Watch Complications & Quick Launch
- [x] **Watch complication** views (circular, corner, rectangular, inline)
- [x] Complication shows last run time or daily run count
- [x] Complication data updated on each run save
- [ ] **Widget extension target** needs to be added in Xcode (code is ready in SprintTimerComplication.swift)

### Phase 5: Export & Data Portability
*Make export production-quality.*

- [ ] **True Excel (.xlsx) export** - Needs Swift XLSX library via SPM (CSV with Excel compat for now)
- [x] **Ensure all fields export correctly:**
  - [x] AQI, wind speed/direction, temperature, feels-like, UV, dew point, visibility
  - [x] Location in English (reverse geocoded name)
  - [x] All health data fields (avg/max HR)
- [x] **Compatibility note added** (Strava, TrainingPeaks, Google Sheets, Numbers)
- [x] **Fix double-export hang** (fixed in Phase 1)

### Phase 6: Beta Features & Settings
*Gated behind a "Beta" toggle in Settings.*

- [x] **Beta toggle in Settings** that enables:
  - [x] All debug info moved to bottom of settings, only visible in beta mode
  - [x] Test data generation and clear data tools gated behind beta
  - [x] Beta toggle syncs between devices
  - [ ] Future experimental features

### Phase 7: Testing & Stability
- [x] **Unit tests** for core logic:
  - [x] Run model (formatting, pace, optional fields)
  - [x] Outlier detection (math logic, boundary cases)
  - [x] Start mode (raw values, display names, round-trip)
  - [x] Custom run types (Codable, equality)
  - [x] Export data formatting (CSV escaping, precision)
  - [x] Weather data structs
  - [x] Timer formatting (split time, millisecond precision)
- [ ] **Integration tests** for WatchConnectivity sync (requires device pair)

### Requires Physical Devices (Not Simulator)
*Hold until testing on real Apple Watch + iPhone pair.*

- [ ] Verify history and settings sync end-to-end
- [ ] Clean up debug output that's no longer needed
- [ ] Test and validate the data-wipe script (from Daily Notes Manager)
- [ ] Validate notes with voice dictation on real hardware

---

## Architecture Overview

```
SharedAssets/                  (Shared between watch & iOS)
  RunModel.swift               - SwiftData @Model for Run
  DataManager.swift            - CRUD + UserDefaults settings
  SprintTimerViewModel.swift   - Timer logic, health, GPS, state
  SyncManager.swift            - WatchConnectivity bidirectional sync
  DailyNotesManager.swift      - Per-day notes storage

SprintTimerWatchApp/           (Watch UI)
  ContentView.swift            - Home: distance picker + start
  RunnerView.swift             - Sheet manager during run
  TimerView.swift              - Running display + gestures
  HistoryView.swift            - Run history by day
  NotesView.swift              - Run notes editor
  DayNotesView.swift           - Daily notes editor
  SettingsView.swift           - Watch settings
  WatchTextInput.swift         - (Unused)

SprintTimeriOSApp/             (iPhone UI)
  SprintTimerApp.swift         - App entry point
  iOSContentView.swift         - Tab bar navigation
  iOSHistoryView.swift         - History with filtering
  iOSSettingsView.swift        - Settings + debug tools
  iOSExportView.swift          - CSV/JSON export
```

**Storage:** SwiftData (SQLite) via App Group `group.com.JasonMark.SprintTimer`
**Sync:** WatchConnectivity with immediate + queued fallback

---

## Data Captured Per Run

| Field | Status | Source |
|-------|--------|--------|
| Date/Time | Done | System clock |
| Elapsed Time | Done | Timer |
| Distance (selected) | Done | User picker |
| Run Notes | Done | User input |
| Day Notes | Done | User input |
| Start Heart Rate | Done | HealthKit |
| End Heart Rate | Done | HealthKit |
| Avg Heart Rate | Done | HealthKit |
| Max Heart Rate | Done | HealthKit |
| Steps | Done | HealthKit |
| Stride Length | Done | Calculated |
| Latitude | Done | CoreLocation |
| Longitude | Done | CoreLocation |
| Altitude | Done | CoreLocation |
| Actual GPS Distance | Done | CoreLocation (route tracking) |
| Average Speed | Done | Calculated |
| Altitude Gain | Done | CoreLocation (route tracking) |
| Location Name | Done | Reverse geocoding |
| Temperature | Done (needs API key) | OpenWeather API |
| Feels Like | Done (needs API key) | OpenWeather API |
| Humidity | Done (needs API key) | OpenWeather API |
| Pressure | Done (needs API key) | OpenWeather API |
| Wind Speed/Direction | Done (needs API key) | OpenWeather API |
| AQI | Done (needs API key) | OpenWeather API |
| UV Index | Done (needs API key) | OpenWeather API |
| Weather Condition | Done (needs API key) | OpenWeather API |
| Start Method | Future (Pinch-to-Stop) | System |
| Stop Method | Future (Pinch-to-Stop) | System |
| Pinch Offset | Future (Pinch-to-Stop) | Calibration |

---

## Possible Future Phases

- **Digital Crown view scrubbing during runs** — Use the watch's Digital Crown to cycle between views while in a run (e.g. timer, end run, daily notes, return to home). Currently handled via sheet-based navigation.

### Pinch-to-Stop (Double Tap Gesture)

*Requires Apple Watch Series 9, Ultra 2, or newer. Uses `.handGestureShortcut(.primaryAction)` API (watchOS 10+).*

**Problem:** The system's Double Tap gesture fires ~300-500ms after the actual finger contact, which is too slow for accurate sprint timing. This feature adds a calibrated offset to compensate.

**Settings:**
- Toggle: "Pinch to Stop" (default: OFF)
- Calibrated offset value (stored in ms, e.g. 380ms)
- "Calibrate Pinch Timing" button

**Calibration Flow:**
1. User taps "Calibrate Pinch Timing" in Settings
2. Watch shows a 3-second countdown (3... 2... 1... GO)
3. At "GO" (time zero), user double-taps as fast as possible
4. App records the delay between time zero and when the system reports the gesture (e.g. 350ms)
5. Repeat 3 times total
6. If all 3 measurements are within 20% of each other → suggest the average as the offset
7. If measurements are too inconsistent → show "Try again" (don't save)
8. User can accept the suggested offset or re-calibrate at any time

**Runtime Behavior:**
- If Pinch is ON **and** offset is calibrated: both screen tap and double-tap stop the run
- If Pinch is OFF **or** no offset calibrated: double-tap does nothing
- Both tap and pinch call the same `stopCurrentRun()` function
- Pinch passes the calibrated offset: `stopCurrentRun(pinchOffset: calibratedOffset)`
- The actual recorded elapsed time = system stop time - pinch offset
- The stop method used is recorded on the Run (see below)

**Run Metadata — Start/Stop Method Tracking:**
- New fields on Run model:
  - `startMethod: String?` — "tap", "countdown", "motion"
  - `stopMethod: String?` — "tap", "pinch"
  - `pinchOffset: Double?` — offset subtracted (ms), only set when stopped via pinch
- Exported in CSV/JSON alongside other run data
- Displayed in run detail/notes editor (informational)

**Data Model Changes:**
```swift
// RunModel.swift — new optional fields
var startMethod: String?   // "tap", "countdown", "motion"
var stopMethod: String?    // "tap", "pinch"  
var pinchOffset: Double?   // ms subtracted from elapsed time (only for pinch stops)
```

**Settings Storage:**
```swift
// DataManager.swift — new settings
var usePinchToStop: Bool     // default false
var pinchCalibrationMs: Double?  // nil until calibrated
```

**Sync:** startMethod, stopMethod, and pinchOffset sync via WatchConnectivity and are included in CloudKit backup. Pinch settings (toggle + calibration) sync between devices.

**Export:** Three new columns: "Start Method", "Stop Method", "Pinch Offset (ms)"

---

## TODO / Investigate

1. **Speech-to-text for notes on watch** — The current notes flow requires tap to edit → tap for keyboard → tap for microphone, which is too many steps. Users will never want the keyboard on the watch; they will always want speech-to-text. Investigate options for going straight to voice/dictation input for notes (skip the keyboard entirely).
2. **Make notes text bigger on watch** — Notes are too small on the watch screen. Increase the font size / display area so they're actually readable.

---

## Questions to Decide

1. **Notes flow after runs** - Should every run prompt for notes, or only on long-press? (Christine input needed)
2. **Notes button layout on history** - What does Christine prefer?
3. **Export target apps** - Which third-party apps should we support importing to?
4. **Beta scope** - What other features belong behind the beta toggle?
5. **Git workflow** - Squash merging (`git merge --squash branch-name`) will combine all branch commits into one commit on main. Is that what you want?
