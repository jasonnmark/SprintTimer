import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct iOSExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @State private var isExporting = false
    @State private var exportURL: IdentifiableURL?
    @State private var selectedFormat = 0
    @State private var includeNotes = true
    @State private var includeGPSData = true
    @State private var includeHealthData = true
    @State private var includeWeatherData = true
    @State private var includeLocationData = true
    @State private var showingImporter = false
    @State private var importResult: ImportResult?
    @State private var importError: String?
    @StateObject private var dailyNotesManager = DailyNotesManager.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Format")) {
                    Picker("Format", selection: $selectedFormat) {
                        Text("CSV").tag(0)
                        Text("JSON").tag(1)
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

                Section(header: Text("Import")) {
                    Button(action: { showingImporter = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import from File")
                            Spacer()
                        }
                    }
                    Text("Pick a CSV or JSON file previously exported from SprintTimer. Rows with a matching UID update existing runs; rows with a blank UID create new runs. Edit in Google Sheets, then reimport.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Import / Export")
            .sheet(item: $exportURL) { item in
                ShareSheet(activityItems: [item.url])
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import Complete", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {
                Button("OK", role: .cancel) { importResult = nil }
            } message: {
                if let r = importResult {
                    Text("Updated \(r.updated) run\(r.updated == 1 ? "" : "s"). Created \(r.created) new run\(r.created == 1 ? "" : "s")." + (r.skipped > 0 ? " Skipped \(r.skipped) row\(r.skipped == 1 ? "" : "s")." : ""))
                }
            }
            .alert("Import Failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }
    
    private func exportData() {
        isExporting = true
        
        // Extract all data on main thread first
        let runsData = extractRunsData()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL: URL = (selectedFormat == 0)
                ? self.createCSVFile(from: runsData)
                : self.createJSONFile(from: runsData)

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

    private func createCSVFile(from runsData: [RunData]) -> URL {
        // UID is the last column so it stays out of the way while editing in
        // Sheets. On import: UID matches an existing run -> update it; blank
        // UID -> new run. Run type is matched on name on import.

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

        csvString += ",UID\n"

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

            csvString += ",\"\(run.id.uuidString)\"\n"
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

            if includeNotes {
                if !run.notes.isEmpty { runDict["notes"] = run.notes }
                if !run.dayNote.isEmpty { runDict["dayNotes"] = run.dayNote }
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

    // MARK: - Import

    struct ImportResult {
        var updated: Int = 0
        var created: Int = 0
        var skipped: Int = 0
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension.lowercased()
                let rows: [ImportedRow]
                if ext == "json" {
                    rows = try parseJSON(data)
                } else {
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "File is not UTF-8 text."])
                    }
                    rows = try parseCSV(text)
                }
                importResult = applyImport(rows)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    // Subset of fields the importer reads. Computed/display-only columns are ignored.
    private struct ImportedRow {
        var id: UUID?
        var runTypeId: UUID?
        var runTypeName: String?
        var date: Date?
        var distance: Int?
        var elapsedTime: TimeInterval?
        var notes: String?
        var dayNote: String?
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var altitudeGain: Double?
        var actualDistance: Double?
        var startHeartRate: Double?
        var endHeartRate: Double?
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var steps: Int?
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
    }

    @MainActor
    private func applyImport(_ rows: [ImportedRow]) -> ImportResult {
        var result = ImportResult()
        let existing = (try? modelContext.fetch(FetchDescriptor<Run>())) ?? []
        var byId: [UUID: Run] = [:]
        for r in existing { byId[r.id] = r }

        for row in rows {
            // Need at minimum a distance and elapsedTime to identify a valid run.
            guard let distance = row.distance, let elapsed = row.elapsedTime else {
                result.skipped += 1
                continue
            }

            let resolvedTypeId = resolveRunTypeId(row: row, distance: distance)

            if let id = row.id, let run = byId[id] {
                apply(row, distance: distance, elapsed: elapsed, typeId: resolvedTypeId, to: run)
                result.updated += 1
            } else {
                let run = Run(distance: distance, elapsedTime: elapsed, runTypeId: resolvedTypeId, notes: row.notes ?? "")
                if let id = row.id { run.id = id }
                apply(row, distance: distance, elapsed: elapsed, typeId: resolvedTypeId, to: run)
                modelContext.insert(run)
                result.created += 1
            }
        }

        try? modelContext.save()
        return result
    }

    /// Resolves a non-nil `runTypeId` for an imported row. Match priority:
    /// 1. Exact (case-insensitive) name match against existing types.
    /// 2. If the row has a name but no match, create a new custom type with
    ///    that name + the row's distance.
    /// 3. If the row has no name, match an existing type by distance.
    /// 4. If still nothing, create a custom "<distance>m" type.
    /// Result: every imported run has its `runTypeId` set.
    @MainActor
    private func resolveRunTypeId(row: ImportedRow, distance: Int) -> UUID {
        let dm = DataManager.shared
        let all = dm.allRunTypesIncludingArchived

        // JSON round-trip: trust an existing runTypeId only if it matches a
        // known type. CSV doesn't carry runTypeId, so this path is JSON-only.
        if let id = row.runTypeId, all.contains(where: { $0.id == id }) {
            return id
        }

        let trimmedName = row.runTypeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedName.isEmpty {
            if let match = all.first(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
                return match.id
            }
            return dm.addCustomType(name: trimmedName, distance: distance).id
        }

        if let match = all.first(where: { $0.distance == distance }) {
            return match.id
        }
        return dm.addCustomType(name: "\(distance)m", distance: distance).id
    }

    @MainActor
    private func apply(_ row: ImportedRow, distance: Int, elapsed: TimeInterval, typeId: UUID, to run: Run) {
        run.distance = distance
        run.elapsedTime = elapsed
        if let date = row.date { run.date = date }
        run.runTypeId = typeId
        if let notes = row.notes { run.notes = notes }
        if let dayNote = row.dayNote { dailyNotesManager.setNote(dayNote, for: run.date) }
        if let v = row.locationName { run.locationName = v.isEmpty ? nil : v }
        if let v = row.latitude { run.latitude = v }
        if let v = row.longitude { run.longitude = v }
        if let v = row.altitude { run.altitude = v }
        if let v = row.altitudeGain { run.altitudeGain = v }
        if let v = row.actualDistance { run.actualDistance = v }
        if let v = row.startHeartRate { run.startHeartRate = v }
        if let v = row.endHeartRate { run.endHeartRate = v }
        if let v = row.averageHeartRate { run.averageHeartRate = v }
        if let v = row.maxHeartRate { run.maxHeartRate = v }
        if let v = row.steps { run.steps = v }
        if let v = row.temperature { run.temperature = v }
        if let v = row.feelsLike { run.feelsLike = v }
        if let v = row.humidity { run.humidity = v }
        if let v = row.pressure { run.pressure = v }
        if let v = row.windSpeed { run.windSpeed = v }
        if let v = row.windDirection { run.windDirection = v }
        if let v = row.visibility { run.visibility = v }
        if let v = row.uvIndex { run.uvIndex = v }
        if let v = row.dewPoint { run.dewPoint = v }
        if let v = row.aqi { run.aqi = v }
        if let v = row.weatherCondition { run.weatherCondition = v.isEmpty ? nil : v }
    }

    // MARK: - JSON parsing

    private func parseJSON(_ data: Data) throws -> [ImportedRow] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON root must be an array of run objects."])
        }
        let iso = ISO8601DateFormatter()
        return array.map { dict in
            var row = ImportedRow()
            if let s = dict["id"] as? String { row.id = UUID(uuidString: s) }
            if let s = dict["runTypeId"] as? String { row.runTypeId = UUID(uuidString: s) }
            if let s = dict["runType"] as? String { row.runTypeName = s }
            if let s = dict["date"] as? String { row.date = iso.date(from: s) }
            if let v = dict["distance"] as? Int { row.distance = v }
            else if let v = dict["distance"] as? Double { row.distance = Int(v) }
            if let v = dict["elapsedTime"] as? Double { row.elapsedTime = v }
            else if let v = dict["elapsedTime"] as? Int { row.elapsedTime = TimeInterval(v) }
            if let v = dict["notes"] as? String { row.notes = v }
            if let v = dict["dayNotes"] as? String { row.dayNote = v }
            if let loc = dict["locationName"] as? String { row.locationName = loc }
            if let health = dict["healthData"] as? [String: Any] {
                row.startHeartRate = health["startHeartRate"] as? Double
                row.endHeartRate = health["endHeartRate"] as? Double
                row.averageHeartRate = health["averageHeartRate"] as? Double
                row.maxHeartRate = health["maxHeartRate"] as? Double
                row.steps = health["steps"] as? Int
            }
            if let gps = dict["gpsData"] as? [String: Any] {
                row.latitude = gps["latitude"] as? Double
                row.longitude = gps["longitude"] as? Double
                row.altitude = gps["altitude"] as? Double
                row.altitudeGain = gps["altitudeGain"] as? Double
                row.actualDistance = gps["gpsDistance"] as? Double
                if let loc = gps["locationName"] as? String { row.locationName = loc }
            }
            if let w = dict["weatherData"] as? [String: Any] {
                row.weatherCondition = w["condition"] as? String
                row.temperature = w["temperature"] as? Double
                row.feelsLike = w["feelsLike"] as? Double
                row.humidity = w["humidity"] as? Double
                row.pressure = w["pressure"] as? Double
                row.windSpeed = w["windSpeed"] as? Double
                row.windDirection = w["windDirectionDegrees"] as? Double
                row.visibility = w["visibility"] as? Double
                row.uvIndex = w["uvIndex"] as? Int
                row.dewPoint = w["dewPoint"] as? Double
                row.aqi = w["aqi"] as? Int
            }
            return row
        }
    }

    // MARK: - CSV parsing

    private func parseCSV(_ text: String) throws -> [ImportedRow] {
        // Strip a leading UTF-8 BOM (Sheets/Excel often prepend "\u{FEFF}" when
        // re-exporting). Without this, the first header cell becomes
        // "\u{FEFF}date" and every column-name lookup misses.
        var cleaned = text
        if cleaned.hasPrefix("\u{FEFF}") { cleaned.removeFirst() }
        // Normalize line endings. Swift iterates "\r\n" as a single Character
        // (extended grapheme cluster), so the parser's switch matches neither
        // "\r" nor "\n" — every CRLF row would be folded into one giant line.
        // Collapse CRLF and lone CR down to LF before parsing.
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")

        let records = splitCSV(cleaned)
        guard let header = records.first, records.count > 1 else { return [] }

        // Normalize header cells: strip BOM, trim whitespace, lowercase.
        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
        }
        let columns: [String: Int] = Dictionary(
            header.enumerated().map { (normalize($1), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        func col(_ row: [String], _ key: String) -> String? {
            guard let i = columns[normalize(key)], i < row.count else { return nil }
            let v = row[i].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }

        let shortDate = DateFormatter(); shortDate.dateStyle = .short
        let shortTime = DateFormatter(); shortTime.timeStyle = .short
        let iso = ISO8601DateFormatter()

        var rows: [ImportedRow] = []
        for record in records.dropFirst() {
            if record.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            var row = ImportedRow()
            if let s = col(record, "UID") { row.id = UUID(uuidString: s) }
            row.runTypeName = col(record, "Run Type")

            // Date may be ISO8601 or shortDate; combine with "Time of Day" if present.
            if let d = col(record, "Date") {
                if let parsed = iso.date(from: d) {
                    row.date = parsed
                } else if let day = shortDate.date(from: d) {
                    if let t = col(record, "Time of Day"), let time = shortTime.date(from: t) {
                        let cal = Calendar.current
                        let dayComp = cal.dateComponents([.year, .month, .day], from: day)
                        let timeComp = cal.dateComponents([.hour, .minute, .second], from: time)
                        var merged = DateComponents()
                        merged.year = dayComp.year; merged.month = dayComp.month; merged.day = dayComp.day
                        merged.hour = timeComp.hour; merged.minute = timeComp.minute; merged.second = timeComp.second
                        row.date = cal.date(from: merged)
                    } else {
                        row.date = day
                    }
                }
            }

            row.distance = col(record, "Distance (m)").flatMap { Int($0) }
            row.elapsedTime = col(record, "Elapsed Time (s)").flatMap { Double($0) }
            row.notes = col(record, "Run Notes")
            row.dayNote = col(record, "Day Notes")
            row.locationName = col(record, "Location")
            row.latitude = col(record, "Latitude").flatMap { Double($0) }
            row.longitude = col(record, "Longitude").flatMap { Double($0) }
            row.altitude = col(record, "Altitude (m)").flatMap { Double($0) }
            row.altitudeGain = col(record, "Altitude Gain (m)").flatMap { Double($0) }
            row.actualDistance = col(record, "GPS Distance (m)").flatMap { Double($0) }
            row.startHeartRate = col(record, "Start HR").flatMap { Double($0) }
            row.endHeartRate = col(record, "End HR").flatMap { Double($0) }
            row.averageHeartRate = col(record, "Avg HR").flatMap { Double($0) }
            row.maxHeartRate = col(record, "Max HR").flatMap { Double($0) }
            row.steps = col(record, "Steps").flatMap { Int($0) }
            row.weatherCondition = col(record, "Condition")
            row.temperature = col(record, "Temperature (°C)").flatMap { Double($0) }
            row.feelsLike = col(record, "Feels Like (°C)").flatMap { Double($0) }
            row.humidity = col(record, "Humidity (%)").flatMap { Double($0) }
            row.pressure = col(record, "Pressure (hPa)").flatMap { Double($0) }
            row.windSpeed = col(record, "Wind Speed (m/s)").flatMap { Double($0) }
            row.windDirection = col(record, "Wind Direction (°)").flatMap { Double($0) }
            row.visibility = col(record, "Visibility (m)").flatMap { Double($0) }
            row.uvIndex = col(record, "UV Index").flatMap { Int($0) }
            row.dewPoint = col(record, "Dew Point (°C)").flatMap { Double($0) }
            row.aqi = col(record, "AQI").flatMap { Int($0) }
            rows.append(row)
        }
        return rows
    }

    // RFC-4180-ish CSV record splitter: handles quoted fields, embedded commas, "" escape, embedded newlines.
    private func splitCSV(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    record.append(field); field = ""
                case "\r":
                    break
                case "\n":
                    record.append(field); field = ""
                    records.append(record); record = []
                default:
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
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
