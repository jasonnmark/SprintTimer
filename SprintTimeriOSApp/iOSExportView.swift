import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct iOSExportView: View {
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @State private var isExporting = false
    @State private var exportURL: IdentifiableURL?
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

                Section(header: Text("Compatibility")) {
                    Text("CSV files can be imported into Excel, Google Sheets, Numbers, Strava, and TrainingPeaks. JSON files work with custom analysis tools and databases.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Export")
            .sheet(item: $exportURL) { item in
                ShareSheet(activityItems: [item.url])
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
                self.isExporting = false
                self.exportURL = IdentifiableURL(url: fileURL)
            }
        }
    }
    
    // Data structure to hold extracted run data
    private struct RunData {
        let id: UUID
        let date: Date
        let distance: Int
        let originalDistance: Int
        let elapsedTime: TimeInterval
        let originalElapsedTime: TimeInterval
        let runTypeId: UUID?
        let runTypeName: String?
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
        let locationName: String?

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
                originalDistance: run.originalRecordedDistance,
                elapsedTime: run.elapsedTime,
                originalElapsedTime: run.originalRecordedTime,
                runTypeId: run.runTypeId,
                runTypeName: run.runTypeId.flatMap { DataManager.shared.runType(for: $0)?.name },
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
                locationName: run.locationName,
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
    
    private func optionalDouble(_ val: Double?) -> String {
        guard let v = val else { return "" }
        return String(format: "%.1f", v)
    }

    private func optionalInt(_ val: Double?) -> String {
        guard let v = val else { return "" }
        return "\(Int(v))"
    }

    private func compassDirection(from degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let index = Int((degrees + 11.25).truncatingRemainder(dividingBy: 360) / 22.5)
        return dirs[index % 16]
    }

    private func createExcelFile(from runsData: [RunData]) -> URL {
        // Column order:
        // Core: Date, Time of Day, Day, Distance, Elapsed (s), Time (formatted), Avg Speed (m/s)
        // Notes: Run Notes, Day Notes
        // Health: Start HR, End HR, Avg HR, Max HR, Steps, Stride Length (race)
        // GPS: Latitude, Longitude, Location, Altitude, Alt Gain, GPS Distance, GPS Avg Speed, GPS Stride Length
        // Weather: Condition, Temp, Feels Like, Humidity, Pressure, Wind Speed, Wind Dir (°), Wind Dir, Visibility, UV, Dew Point, AQI

        var csvString = "Date,Time of Day,Day of Week,Run Type,Distance (m),Original Recorded Distance (m),Elapsed Time (s),Original Recorded Time (s),Avg Speed (m/s)"

        if includeNotes {
            csvString += ",Run Notes,Day Notes"
        }

        if includeHealthData {
            csvString += ",Start HR,End HR,Avg HR,Max HR,Steps,Stride Length (m)"
        }

        if includeGPSData {
            csvString += ",Latitude,Longitude"
            if includeLocationData {
                csvString += ",Location"
            }
            csvString += ",Altitude (m),Altitude Gain (m),GPS Distance (m),GPS Avg Speed (m/s),GPS Stride Length (m)"
        } else if includeLocationData {
            csvString += ",Location"
        }

        if includeWeatherData {
            csvString += ",Condition,Temperature (°C),Feels Like (°C),Humidity (%),Pressure (hPa),Wind Speed (m/s),Wind Direction (°),Wind Direction,Visibility (m),UV Index,Dew Point (°C),AQI"
        }

        csvString += "\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"

        for run in runsData {
            // Avg speed based on race distance (not GPS)
            let avgSpeed = run.elapsedTime > 0 ? Double(run.distance) / run.elapsedTime : 0

            // Core data
            let escapedRunType = (run.runTypeName ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csvString += "\"\(dateFormatter.string(from: run.date))\","
            csvString += "\"\(timeFormatter.string(from: run.date))\","
            csvString += "\"\(dayFormatter.string(from: run.date))\","
            csvString += "\"\(escapedRunType)\","
            csvString += "\(run.distance),"
            csvString += "\(run.originalDistance),"
            csvString += "\(String(format: "%.3f", run.elapsedTime)),"
            csvString += "\(String(format: "%.3f", run.originalElapsedTime)),"
            csvString += "\(String(format: "%.2f", avgSpeed))"

            if includeNotes {
                let escapedNotes = run.notes.replacingOccurrences(of: "\"", with: "\"\"")
                csvString += ",\"\(escapedNotes)\""
                let escapedDayNotes = run.dayNote.replacingOccurrences(of: "\"", with: "\"\"")
                csvString += ",\"\(escapedDayNotes)\""
            }

            if includeHealthData {
                csvString += ",\(optionalInt(run.startHeartRate))"
                csvString += ",\(optionalInt(run.endHeartRate))"
                csvString += ",\(optionalInt(run.averageHeartRate))"
                csvString += ",\(optionalInt(run.maxHeartRate))"
                csvString += ",\(run.steps.map { "\($0)" } ?? "")"
                // Stride length based on race distance
                let raceStride: String
                if let steps = run.steps, steps > 0 {
                    raceStride = String(format: "%.2f", Double(run.distance) / Double(steps))
                } else {
                    raceStride = ""
                }
                csvString += ",\(raceStride)"
            }

            if includeGPSData {
                csvString += ",\(run.latitude.map { String(format: "%.6f", $0) } ?? "")"
                csvString += ",\(run.longitude.map { String(format: "%.6f", $0) } ?? "")"
                if includeLocationData {
                    csvString += ",\"\(run.locationName ?? "")\""
                }
                csvString += ",\(run.altitude.map { String(format: "%.1f", $0) } ?? "")"
                csvString += ",\(run.altitudeGain.map { String(format: "%.1f", $0) } ?? "")"
                csvString += ",\(run.actualDistance.map { String(format: "%.1f", $0) } ?? "")"
                // GPS avg speed
                let gpsAvgSpeed: String
                if let dist = run.actualDistance, run.elapsedTime > 0 {
                    gpsAvgSpeed = String(format: "%.2f", dist / run.elapsedTime)
                } else {
                    gpsAvgSpeed = ""
                }
                csvString += ",\(gpsAvgSpeed)"
                // GPS stride length
                let gpsStride: String
                if let dist = run.actualDistance, let steps = run.steps, steps > 0 {
                    gpsStride = String(format: "%.2f", dist / Double(steps))
                } else {
                    gpsStride = ""
                }
                csvString += ",\(gpsStride)"
            } else if includeLocationData {
                csvString += ",\"\(run.locationName ?? "")\""
            }

            if includeWeatherData {
                csvString += ",\"\(run.weatherCondition ?? "")\""
                csvString += ",\(optionalDouble(run.temperature))"
                csvString += ",\(optionalDouble(run.feelsLike))"
                csvString += ",\(optionalInt(run.humidity))"
                csvString += ",\(optionalInt(run.pressure))"
                csvString += ",\(optionalDouble(run.windSpeed))"
                csvString += ",\(run.windDirection.map { String(format: "%.0f", $0) } ?? "")"
                csvString += ",\"\(run.windDirection.map { compassDirection(from: $0) } ?? "")\""
                csvString += ",\(run.visibility.map { "\(Int($0))" } ?? "")"
                csvString += ",\(run.uvIndex.map { "\($0)" } ?? "")"
                csvString += ",\(optionalDouble(run.dewPoint))"
                csvString += ",\(run.aqi.map { "\($0)" } ?? "")"
            }

            csvString += "\n"
        }

        let fileName = "SprintTimer_Export_\(Date().timeIntervalSince1970).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csvString.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            // CSV creation failed
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
            let avgSpeed = run.elapsedTime > 0 ? Double(run.distance) / run.elapsedTime : 0

            var runDict: [String: Any] = [
                "id": run.id.uuidString,
                "date": dateFormatter.string(from: run.date),
                "distance": run.distance,
                "originalRecordedDistance": run.originalDistance,
                "elapsedTime": run.elapsedTime,
                "originalRecordedTime": run.originalElapsedTime,
                "avgSpeed": avgSpeed
            ]
            if let id = run.runTypeId {
                runDict["runTypeId"] = id.uuidString
            }
            if let name = run.runTypeName {
                runDict["runType"] = name
            }

            if includeNotes && !run.notes.isEmpty {
                runDict["notes"] = run.notes
                runDict["dayNotes"] = run.dayNote
            }

            if includeHealthData {
                var healthData: [String: Any] = [:]
                if let startHR = run.startHeartRate { healthData["startHeartRate"] = startHR }
                if let endHR = run.endHeartRate { healthData["endHeartRate"] = endHR }
                if let avgHR = run.averageHeartRate { healthData["averageHeartRate"] = avgHR }
                if let maxHR = run.maxHeartRate { healthData["maxHeartRate"] = maxHR }
                if let steps = run.steps {
                    healthData["steps"] = steps
                    if steps > 0 {
                        healthData["strideLength"] = Double(run.distance) / Double(steps)
                    }
                }
                if !healthData.isEmpty { runDict["healthData"] = healthData }
            }

            if includeGPSData {
                var gpsData: [String: Any] = [:]
                if let latitude = run.latitude { gpsData["latitude"] = latitude }
                if let longitude = run.longitude { gpsData["longitude"] = longitude }
                if includeLocationData, let loc = run.locationName, !loc.isEmpty { gpsData["locationName"] = loc }
                if let altitude = run.altitude { gpsData["altitude"] = altitude }
                if let altitudeGain = run.altitudeGain { gpsData["altitudeGain"] = altitudeGain }
                if let actualDistance = run.actualDistance {
                    gpsData["gpsDistance"] = actualDistance
                    if run.elapsedTime > 0 {
                        gpsData["gpsAvgSpeed"] = actualDistance / run.elapsedTime
                    }
                    if let steps = run.steps, steps > 0 {
                        gpsData["gpsStrideLength"] = actualDistance / Double(steps)
                    }
                }
                if !gpsData.isEmpty { runDict["gpsData"] = gpsData }
            } else if includeLocationData, let loc = run.locationName, !loc.isEmpty {
                runDict["locationName"] = loc
            }

            if includeWeatherData {
                var weatherData: [String: Any] = [:]
                if let condition = run.weatherCondition { weatherData["condition"] = condition }
                if let temp = run.temperature { weatherData["temperature"] = temp }
                if let feelsLike = run.feelsLike { weatherData["feelsLike"] = feelsLike }
                if let humidity = run.humidity { weatherData["humidity"] = humidity }
                if let pressure = run.pressure { weatherData["pressure"] = pressure }
                if let windSpeed = run.windSpeed { weatherData["windSpeed"] = windSpeed }
                if let windDirection = run.windDirection {
                    weatherData["windDirectionDegrees"] = windDirection
                    weatherData["windDirectionCompass"] = compassDirection(from: windDirection)
                }
                if let visibility = run.visibility { weatherData["visibility"] = visibility }
                if let uvIndex = run.uvIndex { weatherData["uvIndex"] = uvIndex }
                if let dewPoint = run.dewPoint { weatherData["dewPoint"] = dewPoint }
                if let aqi = run.aqi { weatherData["aqi"] = aqi }
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
            // JSON creation failed
        }

        return path
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Clean up temp files after share completes or cancels
            for item in activityItems {
                if let url = item as? URL {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
