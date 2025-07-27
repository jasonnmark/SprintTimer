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
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Format")) {
                    Picker("Format", selection: $selectedFormat) {
                        Text("CSV (Excel Compatible)").tag(0)
                        Text("JSON").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Include Data")) {
                    Toggle("Notes", isOn: $includeNotes)
                    Toggle("GPS Data", isOn: $includeGPSData)
                    Toggle("Health Data", isOn: $includeHealthData)
                    Toggle("Weather Data", isOn: $includeWeatherData)
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL: URL
            
            if selectedFormat == 0 {
                fileURL = createCSVFile()
            } else {
                fileURL = createJSONFile()
            }
            
            DispatchQueue.main.async {
                self.exportURL = fileURL
                self.isExporting = false
                self.showingShareSheet = true
            }
        }
    }
    
    private func createCSVFile() -> URL {
        var csvString = "Date,Time,Distance (m),Elapsed Time (s),Formatted Time,Pace (m/s)"
        
        if includeNotes {
            csvString += ",Notes"
        }
        
        if includeGPSData {
            csvString += ",GPS Distance (m),Average Speed (m/s),Latitude,Longitude"
        }
        
        if includeHealthData {
            csvString += ",Start Heart Rate,End Heart Rate,Steps,Stride Length (m)"
        }
        
        if includeWeatherData {
            csvString += ",Temperature (°C),Humidity (%),Pressure (hPa),Altitude (m)"
        }
        
        csvString += "\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        for run in runs {
            // Basic data
            csvString += "\"\(dateFormatter.string(from: run.date))\","
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            csvString += "\"\(timeFormatter.string(from: run.date))\","
            csvString += "\(run.distance),"
            csvString += "\(String(format: "%.3f", run.elapsedTime)),"
            csvString += "\"\(run.formattedTime)\","
            csvString += "\"\(run.pace)\""
            
            if includeNotes {
                let escapedNotes = run.notes.replacingOccurrences(of: "\"", with: "\"\"")
                csvString += ",\"\(escapedNotes)\""
            }
            
            if includeGPSData {
                csvString += ",\(run.actualDistance ?? 0)"
                csvString += ",\(run.averageSpeed ?? 0)"
                csvString += ",\(run.latitude ?? 0)"
                csvString += ",\(run.longitude ?? 0)"
            }
            
            if includeHealthData {
                csvString += ",\(run.startHeartRate ?? 0)"
                csvString += ",\(run.endHeartRate ?? 0)"
                csvString += ",\(run.steps ?? 0)"
                csvString += ",\(run.strideLength ?? 0)"
            }
            
            if includeWeatherData {
                csvString += ",\(run.temperature ?? 0)"
                csvString += ",\(run.humidity ?? 0)"
                csvString += ",\(run.pressure ?? 0)"
                csvString += ",\(run.altitude ?? 0)"
            }
            
            csvString += "\n"
        }
        
        let fileName = "SprintTimer_Export_\(Date().timeIntervalSince1970).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            print("Error creating CSV: \(error)")
        }
        
        return path
    }
    
    private func createJSONFile() -> URL {
        var jsonArray: [[String: Any]] = []
        
        let dateFormatter = ISO8601DateFormatter()
        
        for run in runs {
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
            }
            
            if includeGPSData {
                var gpsData: [String: Any] = [:]
                if let actualDistance = run.actualDistance { gpsData["actualDistance"] = actualDistance }
                if let averageSpeed = run.averageSpeed { gpsData["averageSpeed"] = averageSpeed }
                if let latitude = run.latitude { gpsData["latitude"] = latitude }
                if let longitude = run.longitude { gpsData["longitude"] = longitude }
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
