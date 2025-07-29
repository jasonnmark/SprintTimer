import Foundation
import SwiftData

@Model
final class Run {
    var id: UUID
    var date: Date
    var distance: Int
    var elapsedTime: TimeInterval
    var notes: String
    var dayNotes: String // Deprecated - use DailyNotesManager instead
    
    // GPS & Location Data
    var actualDistance: Double?
    var averageSpeed: Double?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var altitudeGain: Double?
    var locationName: String?
    
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
    
    init(distance: Int, elapsedTime: TimeInterval, notes: String = "", dayNotes: String = "") {
        self.id = UUID()
        self.date = Date()
        self.distance = distance
        self.elapsedTime = elapsedTime
        self.notes = notes
        self.dayNotes = dayNotes
    }
    
    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let milliseconds = Int((elapsedTime.truncatingRemainder(dividingBy: 1)) * 1000)
        
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
}
