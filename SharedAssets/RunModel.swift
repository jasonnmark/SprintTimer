import Foundation
import SwiftData

/// How the sprint timer was stopped. Stored as a String on Run for SwiftData
/// compatibility — use `Run.stopMethodKind` for the typed view.
enum StopMethod: String, Codable, CaseIterable {
    case tap        // Screen tap (DragGesture)
    case pinch      // Apple Watch Double Tap / pinch hand-gesture shortcut
    case button     // Explicit hardware/UI button (reserved for future)
    case auto       // Motion-based auto-stop (reserved for future)
    case unknown    // Legacy or unrecorded
}

@Model
final class Run {
    var id: UUID
    var date: Date
    var distance: Int
    var elapsedTime: TimeInterval
    var notes: String
    var dayNotes: String // Deprecated - use DailyNotesManager instead

    // How the timer stopped (e.g. "tap", "pinch"). Optional because legacy
    // rows predate this field. See StopMethod for valid values.
    var stopMethod: String?

    // GPS & Location Data
    var actualDistance: Double?
    var averageSpeed: Double?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var altitudeGain: Double?
    var locationName: String?
    /// Seconds elapsed (per GPS route) when cumulative distance first crossed the
    /// selected `distance`. Nil for legacy rows, indoor runs, or when GPS is off.
    /// Useful when a failed stop inflates `elapsedTime` — this is the unbiased read.
    var gpsTimeToTarget: TimeInterval?
    
    // Health Data
    var startHeartRate: Double?
    var endHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var steps: Int?
    var strideLength: Double?
    
    // Weather Data
    var temperature: Double?
    var feelsLike: Double?
    var humidity: Double?
    var pressure: Double?
    var windSpeed: Double?
    var windDirection: Double?
    var visibility: Double?
    var uvIndex: Int?
    var dewPoint: Double?
    var aqi: Int?
    var weatherCondition: String?

    // Originally recorded values — captured at sprint completion, never edited.
    // Optional for backward compatibility with rows created before this field existed.
    var originalElapsedTime: TimeInterval?
    var originalDistance: Int?

    /// Foreign key into `DataManager.customRunTypes` or `RunType.builtIns`.
    /// Optional for legacy rows that predate this field; they fall back to the
    /// integer distance for display.
    var runTypeId: UUID?

    init(distance: Int, elapsedTime: TimeInterval, runTypeId: UUID? = nil, notes: String = "", dayNotes: String = "", stopMethod: StopMethod? = nil) {
        self.id = UUID()
        self.date = Date()
        self.distance = distance
        self.originalDistance = distance
        self.elapsedTime = elapsedTime
        self.originalElapsedTime = elapsedTime
        self.runTypeId = runTypeId
        self.notes = notes
        self.dayNotes = dayNotes
        self.stopMethod = stopMethod?.rawValue
    }

    /// Typed accessor for the stored `stopMethod` String. Returns `.unknown`
    /// for legacy rows or values that don't map to a known case.
    var stopMethodKind: StopMethod {
        guard let raw = stopMethod, let kind = StopMethod(rawValue: raw) else {
            return .unknown
        }
        return kind
    }

    /// Falls back to current `elapsedTime` for legacy rows that predate `originalElapsedTime`.
    var originalRecordedTime: TimeInterval { originalElapsedTime ?? elapsedTime }

    /// Falls back to current `distance` for legacy rows that predate `originalDistance`.
    var originalRecordedDistance: Int { originalDistance ?? distance }

    var formattedTime: String { Run.formatTime(elapsedTime) }

    var formattedOriginalRecordedTime: String { Run.formatTime(originalRecordedTime) }

    static func formatTime(_ interval: TimeInterval) -> String {
        // Round to the nearest millisecond (matches CSV export's %.3f formatting,
        // so the displayed time and the exported time always agree on the last
        // digit). Splitting off minutes/seconds from the rounded total handles
        // the .9995s → 1.000s carry correctly.
        let totalMs = Int((interval * 1000).rounded())
        let minutes = totalMs / 60_000
        let seconds = (totalMs / 1000) % 60
        let milliseconds = totalMs % 1000

        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
        } else {
            return String(format: "%d.%03d", seconds, milliseconds)
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var pace: String {
        let metersPerSecond = Double(distance) / elapsedTime
        return String(format: "%.1f m/s", metersPerSecond)
    }

    /// "200m Hurdles" when a type is joined; falls back to "200m" from the
    /// integer distance for legacy untyped runs. Resolves archived types too.
    @MainActor
    func displayLabel(using dataManager: DataManager = .shared) -> String {
        if let id = runTypeId, let type = dataManager.runType(for: id) {
            return type.name
        }
        return "\(distance)m"
    }
}
