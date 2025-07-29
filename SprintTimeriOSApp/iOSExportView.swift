import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct iOSExportView: View {
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var selectedFormat = 0
    @State private var includeNotes = true
    @State private var includeGPSData = true
    @State private var includeHealthData = true
    @State private var includeWeatherData = true
    @State private var includeLocationData = true
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Format")) {
                    Picker("Format", selection: $selectedFormat) {
                        Text("Excel (.xlsx)").tag(0)
                        Text("CSV").tag(1)
                        Text("JSON").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Include Data")) {
                    Toggle("Notes", isOn: $includeNotes)
                    Toggle("GPS & Location", isOn: $includeGPSData)
                    Toggle("Health Data", isOn: $includeHealthData)
                    Toggle("Weather & AQI", isOn: $includeWeatherData)
                    Toggle("Location Names", isOn: $includeLocationData)
                }
                
                Section(header: Text("Summary")) {
                    HStack {
                        Text("Total Runs:")
                        Spacer()
                        Text("\(runs.count)")
                            .foregroundColor(.gray)
                    }
                    
                    if let firstRun = runs.last, let lastRun = runs.first {
                        HStack {
                            Text("Date Range:")
                            Spacer()
                            Text("\(firstRun.date, style: .date) - \(lastRun.date, style: .date)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section {
                    Button(action: exportData) {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export Data")
                            }
                            Spacer()
                        }
                    }
                    .disabled(runs.isEmpty || isExporting)
                }
                
                if runs.isEmpty {
                    Section {
                        Text("No runs to export yet")
                            .foregroundColor(.gray)
                            .italic()
                    }
                }
            }
            .navigationTitle("Export")
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
    
    private func exportData() {
        isExporting = true
        
        // Extract all data on main thread first
        let runsData = extractRunsData()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL: URL
            
            switch selectedFormat {
            case 0:
                fileURL = self.createExcelFile(from: runsData)
            case 1:
                fileURL = self.createCSVFile(from: runsData)
            default:
                fileURL = self.createJSONFile(from: runsData)
            }
            
            DispatchQueue.main.async {
                self.exportURL = fileURL
                self.isExporting = false
                self.showingShareSheet = true
            }
        }
    }
    
    // Data structure to hold extracted run data
    private struct RunData {
        let id: UUID
        let date: Date
        let distance: Int
        let elapsedTime: TimeInterval
        let formattedTime: String
        let pace: String
        let notes: String
        let dayNote: String
        
        // Optional GPS data
        let actualDistance: Double?
        let averageSpeed: Double?
        let latitude: Double?
        let longitude: Double?
        let altitude: Double?
        let altitudeGain: Double?
        
        // Optional health data
        let startHeartRate: Double?
        let endHeartRate: Double?
        let averageHeartRate: Double?
        let maxHeartRate: Double?
        let steps: Int?
        let strideLength: Double?
        
        // Optional weather data
        let temperature: Double?
        let feelsLike: Double?
        let humidity: Double?
        let pressure: Double?
        let windSpeed: Double?
        let windDirection: Double?
        let visibility: Double?
        let uvIndex: Int?
        let dewPoint: Double?
        let aqi: Int?
        let weatherCondition: String?
    }
    
    // Extract all data on main thread
    private func extractRunsData() -> [RunData] {
        return runs.map { run in
            RunData(
                id: run.id,
                date: run.date,
                distance: run.distance,
                elapsedTime: run.elapsedTime,
                formattedTime: run.formattedTime,
                pace: run.pace,
                notes: run.notes,
                dayNote: dailyNotesManager.getDailyNote(for: run),
                actualDistance: run.actualDistance,
                averageSpeed: run.averageSpeed,
                latitude: run.latitude,
                longitude: run.longitude,
                altitude: run.altitude,
                altitudeGain: run.altitudeGain,
                startHeartRate: run.startHeartRate,
                endHeartRate: run.endHeartRate,
                averageHeartRate: run.averageHeartRate,
                maxHeartRate: run.maxHeartRate,
                steps: run.steps,
                strideLength: run.strideLength,
                temperature: run.temperature,
                feelsLike: run.feelsLike,
                humidity: run.humidity,
                pressure: run.pressure,
                windSpeed: run.windSpeed,
                windDirection: run.windDirection,
                visibility: run.visibility,
                uvIndex: run.uvIndex,
                dewPoint: run.dewPoint,
                aqi: run.aqi,
                weatherCondition: run.weatherCondition
            )
        }
    }
    
    private func createExcelFile(from runsData: [RunData]) -> URL {
        // For now, create an enhanced CSV that Excel can open
        // Note: For true .xlsx support, you'd need a library like XLSXWriter
        
        var csvString = "Date,Time,Day of Week,Distance (m),Elapsed Time (s),Formatted Time,Pace (m/s)"
        
        if includeNotes {
            csvString += ",Run Notes,Day Notes"
        }
        
        if includeLocationData {
            csvString += ",Location"
        }
        
        if includeGPSData {
            csvString += ",GPS Distance (m),Average Speed (m/s),Latitude,Longitude,Altitude (m),Altitude Gain (m)"
        }
        
        if includeHealthData {
            csvString += ",Start Heart Rate,End Heart Rate,Average Heart Rate,Max Heart Rate,Steps,Stride Length (m)"
        }
        
        if includeWeatherData {
            csvString += ",Temperature (°C),Feels Like (°C),Humidity (%),Pressure (hPa),Wind Speed (m/s),Wind Direction (°),Visibility (m),UV Index,Dew Point (°C),Condition,AQI"
        }
        
        csvString += "\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        
        for run in runsData {
            // Basic data
            csvString += "\"\(dateFormatter.string(from: run.date))\","
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            csvString += "\"\(timeFormatter.string(from: run.date))\","
            csvString += "\"\(dayFormatter.string(from: run.date))\","
            csvString += "\(run.distance),"
            csvString += "\(String(format: "%.3f", run.elapsedTime)),"
            csvString += "\"\(run.formattedTime)\","
            csvString += "\"\(run.pace)\""
            
            if includeNotes {
                let escapedNotes = run.notes.replacingOccurrences(of: "\"", with: "\"\"")
                csvString += ",\"\(escapedNotes)\""
                
                // Add day notes
                let escapedDayNotes = run.dayNote.replacingOccurrences(of: "\"", with: "\"\"")
                csvString += ",\"\(escapedDayNotes)\""
            }
            
            if includeLocationData {
                // Extract location name from notes if it contains "Location: "
                var locationName = ""
                if run.notes.contains("Location: ") {
                    let components = run.notes.components(separatedBy: " | ")
                    for component in components {
                        if component.hasPrefix("Location: ") {
                            locationName = component.replacingOccurrences(of: "Location: ", with: "")
                            break
                        }
                    }
                }
                csvString += ",\"\(locationName)\""
            }
            
            if includeGPSData {
                csvString += ",\(run.actualDistance ?? 0)"
                csvString += ",\(String(format: "%.2f", run.averageSpeed ?? 0))"
                csvString += ",\(String(format: "%.6f", run.latitude ?? 0))"
                csvString += ",\(String(format: "%.6f", run.longitude ?? 0))"
                csvString += ",\(String(format: "%.1f", run.altitude ?? 0))"
                csvString += ",0" // Altitude gain - not stored per run yet
            }
            
            if includeHealthData {
                csvString += ",\(Int(run.startHeartRate ?? 0))"
                csvString += ",\(Int(run.endHeartRate ?? 0))"
                csvString += ",0" // Average HR - not stored
                csvString += ",0" // Max HR - not stored
                csvString += ",\(run.steps ?? 0)"
                csvString += ",\(String(format: "%.2f", run.strideLength ?? 0))"
            }
            
            if includeWeatherData {
                csvString += ",\(String(format: "%.1f", run.temperature ?? 0))"
                csvString += ",0" // Feels like - not stored
                csvString += ",\(Int(run.humidity ?? 0))"
                csvString += ",\(Int(run.pressure ?? 0))"
                csvString += ",0" // Wind speed - not stored in Run model
                csvString += ",0" // Wind direction - not stored
                csvString += ",0" // Visibility - not stored
                csvString += ",0" // UV Index - not stored
                csvString += ",0" // Dew Point - not stored
                
                // Extract weather condition from notes if available
                var condition = ""
                if run.notes.contains("Weather: ") {
                    let components = run.notes.components(separatedBy: " | ")
                    for component in components {
                        if component.hasPrefix("Weather: ") {
                            condition = component.replacingOccurrences(of: "Weather: ", with: "")
                            break
                        }
                    }
                }
                csvString += ",\"\(condition)\""
                csvString += ",0" // AQI - not stored in Run model
            }
            
            csvString += "\n"
        }
        
        let fileName = "SprintTimer_Export_\(Date().timeIntervalSince1970).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating Excel/CSV: \(error)")
        }
        
        return path
    }
    
    private func createCSVFile(from runsData: [RunData]) -> URL {
        // Same as Excel for now
        return createExcelFile(from: runsData)
    }
    
    private func createJSONFile(from runsData: [RunData]) -> URL {
        var jsonArray: [[String: Any]] = []
        
        let dateFormatter = ISO8601DateFormatter()
        
        for run in runsData {
            var runDict: [String: Any] = [
                "id": run.id.uuidString,
                "date": dateFormatter.string(from: run.date),
                "distance": run.distance,
                "elapsedTime": run.elapsedTime,
                "formattedTime": run.formattedTime,
                "pace": run.pace
            ]
            
            if includeNotes && !run.notes.isEmpty {
                runDict["notes"] = run.notes
                runDict["dayNotes"] = run.dayNote
            }
            
            // Extract location name from notes
            if includeLocationData && run.notes.contains("Location: ") {
                let components = run.notes.components(separatedBy: " | ")
                for component in components {
                    if component.hasPrefix("Location: ") {
                        runDict["locationName"] = component.replacingOccurrences(of: "Location: ", with: "")
                        break
                    }
                }
            }
            
            if includeGPSData {
                var gpsData: [String: Any] = [:]
                if let actualDistance = run.actualDistance { gpsData["actualDistance"] = actualDistance }
                if let averageSpeed = run.averageSpeed { gpsData["averageSpeed"] = averageSpeed }
                if let latitude = run.latitude { gpsData["latitude"] = latitude }
                if let longitude = run.longitude { gpsData["longitude"] = longitude }
                if let altitude = run.altitude { gpsData["altitude"] = altitude }
                if !gpsData.isEmpty { runDict["gpsData"] = gpsData }
            }
            
            if includeHealthData {
                var healthData: [String: Any] = [:]
                if let startHR = run.startHeartRate { healthData["startHeartRate"] = startHR }
                if let endHR = run.endHeartRate { healthData["endHeartRate"] = endHR }
                if let steps = run.steps { healthData["steps"] = steps }
                if let strideLength = run.strideLength { healthData["strideLength"] = strideLength }
                if !healthData.isEmpty { runDict["healthData"] = healthData }
            }
            
            if includeWeatherData {
                var weatherData: [String: Any] = [:]
                if let temp = run.temperature { weatherData["temperature"] = temp }
                if let humidity = run.humidity { weatherData["humidity"] = humidity }
                if let pressure = run.pressure { weatherData["pressure"] = pressure }
                if let altitude = run.altitude { weatherData["altitude"] = altitude }
                
                // Extract weather condition from notes
                if run.notes.contains("Weather: ") {
                    let components = run.notes.components(separatedBy: " | ")
                    for component in components {
                        if component.hasPrefix("Weather: ") {
                            weatherData["condition"] = component.replacingOccurrences(of: "Weather: ", with: "")
                            break
                        }
                    }
                }
                
                if !weatherData.isEmpty { runDict["weatherData"] = weatherData }
            }
            
            jsonArray.append(runDict)
        }
        
        let fileName = "SprintTimer_Export_\(Date().timeIntervalSince1970).json"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted)
            try jsonData.write(to: path)
        } catch {
            print("Error creating JSON: \(error)")
        }
        
        return path
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
