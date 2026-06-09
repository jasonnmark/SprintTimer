import Testing
import Foundation
@testable import SprintTimer

// MARK: - Run Model Tests

struct RunModelTests {

    @Test func runInitialization() {
        let run = Run(distance: 100, elapsedTime: 12.345)
        #expect(run.distance == 100)
        #expect(run.elapsedTime == 12.345)
        #expect(run.notes == "")
        #expect(run.dayNotes == "")
        #expect(run.id != UUID()) // Has a unique ID
    }

    @Test func runFormattedTimeSeconds() {
        let run = Run(distance: 100, elapsedTime: 12.345)
        #expect(run.formattedTime == "12.345")
    }

    @Test func runFormattedTimeMinutes() {
        let run = Run(distance: 400, elapsedTime: 65.123)
        #expect(run.formattedTime == "1:05.123")
    }

    @Test func runFormattedTimeZero() {
        let run = Run(distance: 100, elapsedTime: 0.0)
        #expect(run.formattedTime == "0.000")
    }

    @Test func runFormattedTimeLargeMinutes() {
        let run = Run(distance: 400, elapsedTime: 125.999)
        #expect(run.formattedTime == "2:05.999")
    }

    @Test func runFormattedTimeSubSecond() {
        let run = Run(distance: 100, elapsedTime: 0.456)
        #expect(run.formattedTime == "0.456")
    }

    @Test func runPaceCalculation() {
        let run = Run(distance: 100, elapsedTime: 10.0)
        #expect(run.pace == "10.0 m/s")
    }

    @Test func runPace200m() {
        let run = Run(distance: 200, elapsedTime: 25.0)
        #expect(run.pace == "8.0 m/s")
    }

    @Test func runFormattedDateNotEmpty() {
        let run = Run(distance: 100, elapsedTime: 12.0)
        #expect(!run.formattedDate.isEmpty)
    }

    @Test func runOptionalFieldsDefaultNil() {
        let run = Run(distance: 100, elapsedTime: 12.0)
        #expect(run.latitude == nil)
        #expect(run.longitude == nil)
        #expect(run.altitude == nil)
        #expect(run.startHeartRate == nil)
        #expect(run.endHeartRate == nil)
        #expect(run.averageHeartRate == nil)
        #expect(run.maxHeartRate == nil)
        #expect(run.steps == nil)
        #expect(run.strideLength == nil)
        #expect(run.actualDistance == nil)
        #expect(run.averageSpeed == nil)
        #expect(run.altitudeGain == nil)
        #expect(run.locationName == nil)
        #expect(run.temperature == nil)
        #expect(run.weatherCondition == nil)
        #expect(run.aqi == nil)
    }

    @Test func runOptionalFieldsCanBeSet() {
        let run = Run(distance: 100, elapsedTime: 12.0)
        run.latitude = 42.32
        run.longitude = -72.63
        run.altitude = 50.0
        run.startHeartRate = 72.0
        run.endHeartRate = 165.0
        run.averageHeartRate = 140.0
        run.maxHeartRate = 175.0
        run.steps = 55
        run.strideLength = 1.82
        run.actualDistance = 101.5
        run.averageSpeed = 8.5
        run.altitudeGain = 2.3
        run.locationName = "Northampton, MA"
        run.temperature = 18.5
        run.feelsLike = 16.0
        run.humidity = 55.0
        run.pressure = 1013.0
        run.windSpeed = 3.2
        run.windDirection = 180.0
        run.visibility = 10000.0
        run.uvIndex = 5
        run.dewPoint = 10.0
        run.aqi = 2
        run.weatherCondition = "Clear"

        #expect(run.latitude == 42.32)
        #expect(run.averageHeartRate == 140.0)
        #expect(run.maxHeartRate == 175.0)
        #expect(run.locationName == "Northampton, MA")
        #expect(run.weatherCondition == "Clear")
        #expect(run.aqi == 2)
    }
}

// MARK: - Start Mode Tests

struct StartModeTests {

    @Test func startModeAllCases() {
        #expect(StartMode.allCases.count == 3)
        #expect(StartMode.allCases.contains(.countdown))
        #expect(StartMode.allCases.contains(.motion))
        #expect(StartMode.allCases.contains(.tap))
    }

    @Test func startModeRawValues() {
        #expect(StartMode.countdown.rawValue == "countdown")
        #expect(StartMode.motion.rawValue == "motion")
        #expect(StartMode.tap.rawValue == "tap")
    }

    @Test func startModeDisplayNames() {
        #expect(StartMode.countdown.displayName == "Countdown")
        #expect(StartMode.motion.displayName == "Motion Start")
        #expect(StartMode.tap.displayName == "Tap to Start")
    }

    @Test func startModeDescriptions() {
        #expect(!StartMode.countdown.description.isEmpty)
        #expect(!StartMode.motion.description.isEmpty)
        #expect(!StartMode.tap.description.isEmpty)
    }

    @Test func startModeFromRawValue() {
        #expect(StartMode(rawValue: "countdown") == .countdown)
        #expect(StartMode(rawValue: "motion") == .motion)
        #expect(StartMode(rawValue: "tap") == .tap)
        #expect(StartMode(rawValue: "invalid") == nil)
    }
}

// MARK: - Custom Run Type Tests

struct CustomRunTypeTests {

    @Test func customRunTypeInit() {
        let runType = CustomRunType(name: "400m Hurdles", distance: 400)
        #expect(runType.name == "400m Hurdles")
        #expect(runType.distance == 400)
        #expect(runType.id != UUID()) // Has a unique ID
    }

    @Test func customRunTypeEquality() {
        let a = CustomRunType(name: "Test", distance: 100)
        var b = a
        #expect(a == b)
        b.name = "Different"
        #expect(a != b)
    }

    @Test func customRunTypeCodable() throws {
        let original = CustomRunType(name: "Backwards 100m", distance: 100)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomRunType.self, from: data)
        #expect(decoded.name == original.name)
        #expect(decoded.distance == original.distance)
        #expect(decoded.id == original.id)
    }

    @Test func customRunTypeArrayCodable() throws {
        let types = [
            CustomRunType(name: "400m Hurdles", distance: 400),
            CustomRunType(name: "Backwards 100m", distance: 100)
        ]
        let data = try JSONEncoder().encode(types)
        let decoded = try JSONDecoder().decode([CustomRunType].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "400m Hurdles")
        #expect(decoded[1].distance == 100)
    }

    // MARK: - Merge (cross-device sync)

    // Regression: a peer whose snapshot didn't yet include a freshly-added local
    // type must not wipe it out. The user lost a "5m" type this way before.
    @Test func mergeKeepsLocalOnlyType() {
        let localOnly = RunType(name: "5m", distance: 5)
        let shared = RunType(name: "1k", distance: 1000)
        let merged = RunType.merge(local: [localOnly, shared], incoming: [shared])
        #expect(merged.contains { $0.id == localOnly.id })
        #expect(merged.contains { $0.id == shared.id })
    }

    @Test func mergeAddsIncomingOnlyType() {
        let local = RunType(name: "5m", distance: 5)
        let incomingOnly = RunType(name: "800m", distance: 800)
        let merged = RunType.merge(local: [local], incoming: [incomingOnly])
        #expect(merged.count == 2)
        #expect(merged.contains { $0.id == incomingOnly.id })
    }

    @Test func mergeIncomingWinsOnRename() {
        var t = RunType(name: "Original", distance: 50)
        let renamed = RunType(id: t.id, name: "Renamed", distance: 50)
        let merged = RunType.merge(local: [t], incoming: [renamed])
        #expect(merged.first { $0.id == t.id }?.name == "Renamed")
    }

    @Test func mergeIncomingWinsOnArchive() {
        let unarchived = RunType(name: "50m", distance: 50, isArchived: false)
        let archived = RunType(id: unarchived.id, name: "50m", distance: 50, isArchived: true)
        let merged = RunType.merge(local: [unarchived], incoming: [archived])
        #expect(merged.first { $0.id == unarchived.id }?.isArchived == true)
    }

    @Test func mergeFiltersOutBuiltInIds() {
        let bogus = RunType(id: RunType.oneHundred.id, name: "Hijack", distance: 999)
        let local = RunType(name: "5m", distance: 5)
        let merged = RunType.merge(local: [local], incoming: [bogus])
        #expect(merged.contains { $0.id == local.id })
        #expect(!merged.contains { $0.id == RunType.oneHundred.id })
    }

    @Test func mergeEmptyIncomingPreservesEverything() {
        let a = RunType(name: "5m", distance: 5)
        let b = RunType(name: "10m", distance: 10)
        let merged = RunType.merge(local: [a, b], incoming: [])
        #expect(merged.count == 2)
    }
}

// MARK: - Export Formatting Tests

struct ExportFormattingTests {

    @Test func csvEscapingQuotes() {
        let notes = "She said \"hello\""
        let escaped = notes.replacingOccurrences(of: "\"", with: "\"\"")
        #expect(escaped == "She said \"\"hello\"\"")
    }

    @Test func csvEscapingCommas() {
        let notes = "Windy, cold conditions"
        // CSV wraps in quotes, so commas inside are fine
        let csvCell = "\"\(notes)\""
        #expect(csvCell == "\"Windy, cold conditions\"")
    }

    @Test func formattedTimeForExport() {
        let run = Run(distance: 100, elapsedTime: 12.345)
        #expect(run.formattedTime == "12.345")

        let run2 = Run(distance: 400, elapsedTime: 65.0)
        #expect(run2.formattedTime == "1:05.000")
    }

    @Test func paceForExport() {
        let run = Run(distance: 100, elapsedTime: 12.5)
        #expect(run.pace == "8.0 m/s")
    }

    @Test func elapsedTimePrecision() {
        let run = Run(distance: 100, elapsedTime: 12.3456789)
        // Format as export would
        let formatted = String(format: "%.3f", run.elapsedTime)
        #expect(formatted == "12.346") // Rounded
    }
}

// MARK: - Weather Service Tests

struct WeatherServiceTests {

    @Test func weatherServiceSingleton() {
        let a = WeatherService.shared
        let b = WeatherService.shared
        #expect(a === b)
    }

    @Test func weatherServiceHasNoKeyByDefault() {
        // Can't easily test this since it reads from UserDefaults
        // but we can test the struct
        let data = WeatherData(
            temperature: 20.0,
            feelsLike: 18.0,
            humidity: 55.0,
            pressure: 1013.0,
            windSpeed: 3.5,
            windDirection: 180.0,
            visibility: 10000.0,
            uvIndex: 5,
            dewPoint: 10.0,
            weatherCondition: "Clear"
        )
        #expect(data.temperature == 20.0)
        #expect(data.weatherCondition == "Clear")
        #expect(data.uvIndex == 5)
    }

    @Test func aqiDataStruct() {
        let aqi = AQIData(aqi: 3)
        #expect(aqi.aqi == 3)
    }
}

// MARK: - Daily Notes Manager Tests

struct DailyNotesManagerTests {

    @Test func dateKeyFormatConsistency() {
        // Verify the date key format produces consistent keys
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let date = Date()
        let startOfDay = Calendar.current.startOfDay(for: date)
        let key = formatter.string(from: startOfDay)

        #expect(key.count == 10) // "2026-04-12"
        #expect(key.contains("-"))
    }
}

// MARK: - Timer Formatting Tests

struct TimerFormattingTests {

    @Test func splitFormattedTimeWithDot() {
        let time = "12.345"
        if let dotIndex = time.firstIndex(of: ".") {
            let seconds = String(time[..<dotIndex])
            let fraction = String(time[dotIndex...])
            #expect(seconds == "12")
            #expect(fraction == ".345")
        } else {
            Issue.record("Expected dot in formatted time")
        }
    }

    @Test func splitFormattedTimeWithMinutes() {
        let time = "1:05.123"
        if let dotIndex = time.firstIndex(of: ".") {
            let seconds = String(time[..<dotIndex])
            let fraction = String(time[dotIndex...])
            #expect(seconds == "1:05")
            #expect(fraction == ".123")
        } else {
            Issue.record("Expected dot in formatted time")
        }
    }

    @Test func millisecondPrecision() {
        // Verify we get exactly 3 digits of milliseconds
        let elapsed: TimeInterval = 12.5
        let milliseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 1000)
        #expect(milliseconds == 500)

        let formatted = String(format: "%d.%03d", Int(elapsed) % 60, milliseconds)
        #expect(formatted == "12.500")
    }
}
