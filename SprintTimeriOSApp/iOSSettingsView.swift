import SwiftUI
import SwiftData
import HealthKit

struct iOSSettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var backupManager = BackupManager.shared
    @State private var debugInfo = ""
    @State private var selectedStartModeIndex = 0
    @State private var showingClearAlert = false
    @State private var showingRestoreSheet = false
    @State private var availableBackups: [BackupManager.BackupInfo] = []
    @State private var weatherAPIKey = ""
    @State private var isHealthConnected = false
    private let healthStore = HKHealthStore()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Start Options")) {
                    Picker("Start Method", selection: $selectedStartModeIndex) {
                        ForEach(0..<StartMode.allCases.count, id: \.self) { index in
                            Text(StartMode.allCases[index].displayName)
                                .tag(index)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: selectedStartModeIndex) { _, newValue in
                        dataManager.startMode = StartMode.allCases[newValue]
                        Task { await updateDebugInfo() }
                    }
                    
                    if dataManager.startMode == .countdown {
                        Picker("Countdown Time", selection: $dataManager.countdownTime) {
                            Text("3 seconds").tag(3)
                            Text("5 seconds").tag(5)
                            Text("10 seconds").tag(10)
                            Text("15 seconds").tag(15)
                            Text("20 seconds").tag(20)
                            Text("30 seconds").tag(30)
                        }
                        .onChange(of: dataManager.countdownTime) { _, _ in
                            Task { await updateDebugInfo() }
                        }
                    }
                    
                    Text(dataManager.startMode.description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section(header: Text("Data Collection")) {
                    Toggle("GPS Verification", isOn: $dataManager.useGPS)
                        .onChange(of: dataManager.useGPS) { _, _ in Task { await updateDebugInfo() } }
                    Text("Records GPS coordinates during sprints to calculate distance and pace.")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Toggle("Altitude Tracking", isOn: $dataManager.trackAltitude)
                        .onChange(of: dataManager.trackAltitude) { _, _ in Task { await updateDebugInfo() } }
                    Text("Captures elevation from GPS during sprints to calculate altitude gain.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Section {
                    NavigationLink {
                        AppleHealthSettingsView()
                    } label: {
                        HStack(spacing: 10) {
                            Image("AppleHealthIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text("Apple Health")
                            Spacer()
                            Text(isHealthConnected ? "Connected" : "Not Connected")
                                .foregroundColor(isHealthConnected ? .green : .secondary)
                                .font(.subheadline)
                        }
                    }
                }

                Section(header: Text("Weather Data")) {
                    TextField("OpenWeather API Key", text: $weatherAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: weatherAPIKey) { _, newValue in
                            WeatherService.shared.apiKey = newValue
                        }

                    if WeatherService.shared.hasAPIKey {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Temperature & Feels Like", systemImage: "thermometer")
                            Label("Humidity & Pressure", systemImage: "cloud")
                            Label("Wind Speed & Direction", systemImage: "wind")
                            Label("UV Index", systemImage: "sun.max")
                            Label("Air Quality (AQI)", systemImage: "aqi.medium")
                            Label("Weather Condition", systemImage: "cloud.sun")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    } else {
                        Text("Enter your OpenWeather API key to enable weather tracking.")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Link(destination: URL(string: "https://openweathermap.org")!) {
                            HStack {
                                Image(systemName: "link")
                                Text("Get a free API key at openweathermap.org")
                            }
                            .font(.caption)
                        }
                    }
                }
                
                Section(header: Text("Save Options")) {
                    Toggle("Save Tap Time", isOn: $dataManager.saveTapTime)
                        .onChange(of: dataManager.saveTapTime) { _, _ in Task { await updateDebugInfo() } }
                    Toggle("Save GPS Time", isOn: $dataManager.saveGPSTime)
                        .onChange(of: dataManager.saveGPSTime) { _, _ in Task { await updateDebugInfo() } }
                    
                    if dataManager.saveTapTime && dataManager.saveGPSTime {
                        Text("Both tap and GPS times will be recorded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Section(header: Text("Data Collected")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Time & Date", systemImage: "clock")
                        Label("Distance & Time", systemImage: "timer")
                        
                        if isHealthConnected {
                            Label("Heart Rate (start/end)", systemImage: "heart")
                            Label("Steps & Stride Length", systemImage: "figure.walk")
                        }
                        
                        if dataManager.useGPS {
                            Label("Location & Speed", systemImage: "location")
                            Label("Actual Distance", systemImage: "map")
                        }
                        
                        if dataManager.trackAltitude {
                            Label("Altitude", systemImage: "arrow.up.and.down")
                        }
                    }
                    .font(.system(size: 14))
                }
                
                Section {
                    Text("Note: Settings sync every few seconds between devices")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Button("Force Refresh") {
                        dataManager.refresh()
                        Task { await updateDebugInfo() }
                    }
                    .buttonStyle(.bordered)
                }

                Section(header: Text("Cloud Backup")) {
                    HStack {
                        Text("Last Backup")
                        Spacer()
                        if let date = backupManager.lastBackupDate {
                            Text(date, style: .relative)
                                .foregroundColor(.secondary)
                            Text("ago")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        Task { await backupManager.performBackup() }
                    } label: {
                        HStack {
                            if backupManager.isBackingUp {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Backing up...")
                            } else {
                                Image(systemName: "icloud.and.arrow.up")
                                Text("Backup Now")
                            }
                        }
                    }
                    .disabled(backupManager.isBackingUp)

                    Button {
                        Task {
                            availableBackups = await backupManager.fetchBackupList()
                            showingRestoreSheet = true
                        }
                    } label: {
                        HStack {
                            if backupManager.isRestoring {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Restoring...")
                            } else {
                                Image(systemName: "icloud.and.arrow.down")
                                Text("Restore from Backup")
                            }
                        }
                    }
                    .disabled(backupManager.isRestoring)

                    if let error = backupManager.backupError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Text("Backups are stored in your iCloud account. Daily backups kept for 1 week, weekly for 3 months, monthly forever.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Section(header: Text("Beta")) {
                    Toggle("Beta Mode", isOn: $dataManager.betaMode)

                    if !dataManager.betaMode {
                        Text("Enable beta mode to access debug tools and experimental features.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                if dataManager.betaMode {
                    Section(header: Text("Debug Tools").foregroundColor(.red)) {
                        Text(debugInfo)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.red)
                            .lineLimit(10)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxHeight: 150)

                        Button("Refresh Debug Info") {
                            Task { await updateDebugInfo() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Add Test Data") {
                            Task { await generateTestData() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Text("Adds 10x100m + 3x200m runs")
                            .font(.caption2)
                            .foregroundColor(.gray)

                        Button("Clear All Data") {
                            showingClearAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            dataManager.refresh() // Force refresh on appear
            setupInitialState()
            checkHealthStatus()
            Task { await updateDebugInfo() }
        }
        .alert("Clear All Data?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                Task {
                    await clearAllData()
                }
            }
        } message: {
            Text("This will permanently delete all run history. This action cannot be undone.")
        }
        .sheet(isPresented: $showingRestoreSheet) {
            RestoreBackupView(backups: availableBackups)
        }
    }
    
    private func checkHealthStatus() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        isHealthConnected = status == .sharingAuthorized
    }

    private func setupInitialState() {
        if let index = StartMode.allCases.firstIndex(of: dataManager.startMode) {
            selectedStartModeIndex = index
        }
        weatherAPIKey = WeatherService.shared.apiKey
    }
    
    private func updateDebugInfo() async {
        debugInfo = await dataManager.getDebugInfo()
    }
    
    @MainActor
    private func generateTestData() async {
        let modelContext = dataManager.modelContainer.mainContext
        let dailyNotesManager = DailyNotesManager.shared
        
        // Generate 10 100m runs over past 3 days
        let now = Date()
        let calendar = Calendar.current
        
        // 100m runs - spread over 3 days
        for i in 0..<10 {
            let daysAgo = Double.random(in: 0...3)
            let hoursOffset = Double.random(in: 8...20) // Between 8am and 8pm
            let runDate = calendar.date(byAdding: .day, value: -Int(daysAgo), to: now)!
            let runDateTime = calendar.date(bySettingHour: Int(hoursOffset), minute: Int.random(in: 0...59), second: 0, of: runDate)!
            
            // Realistic 100m times between 10.5 and 13.5 seconds
            let baseTime = 11.5
            let variation = Double.random(in: -1.0...2.0)
            let elapsedTime = baseTime + variation
            
            let run = Run(distance: 100, elapsedTime: elapsedTime)
            run.date = runDateTime
            
            // Add some optional data randomly
            if Bool.random() {
                run.actualDistance = Double.random(in: 98...102)
                run.averageSpeed = 100.0 / elapsedTime
                run.latitude = 37.7749 + Double.random(in: -0.01...0.01) // San Francisco area
                run.longitude = -122.4194 + Double.random(in: -0.01...0.01)
            }
            
            if Bool.random() {
                run.startHeartRate = Double.random(in: 65...85)
                run.endHeartRate = Double.random(in: 140...180)
                run.steps = Int.random(in: 50...70) // Steps for 100m
                run.strideLength = 100.0 / Double(run.steps ?? 60)
            }
            
            if Bool.random() {
                run.temperature = Double.random(in: 15...25) // Celsius
                run.humidity = Double.random(in: 40...70) // Percentage
                run.pressure = Double.random(in: 1010...1020) // hPa
                run.altitude = Double.random(in: 0...100) // Meters
            }
            
            // Add notes to some runs
            if i % 3 == 0 {
                run.notes = ["Felt good today", "Windy conditions", "New shoes", "Morning run", "Track was wet"].randomElement()!
            }
            
            modelContext.insert(run)
        }
        
        // Add daily notes for some days
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        dailyNotesManager.setNote("Training day - focus on form", for: twoDaysAgo)
        
        // 200m runs - 3 runs yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        
        for i in 0..<3 {
            let hour = 10 + (i * 3) // Spread throughout the day
            let runDateTime = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: yesterday)!
            
            // Realistic 200m times between 23 and 28 seconds
            let baseTime = 25.0
            let variation = Double.random(in: -2.0...3.0)
            let elapsedTime = baseTime + variation
            
            let run = Run(distance: 200, elapsedTime: elapsedTime)
            run.date = runDateTime
            
            // Add data to all 200m runs
            run.actualDistance = Double.random(in: 198...202)
            run.averageSpeed = 200.0 / elapsedTime
            run.latitude = 37.7749 + Double.random(in: -0.01...0.01)
            run.longitude = -122.4194 + Double.random(in: -0.01...0.01)
            run.startHeartRate = Double.random(in: 70...90)
            run.endHeartRate = Double.random(in: 150...190)
            run.steps = Int.random(in: 100...140) // Steps for 200m
            run.strideLength = 200.0 / Double(run.steps ?? 120)
            run.temperature = Double.random(in: 18...22)
            run.humidity = Double.random(in: 50...65)
            run.pressure = Double.random(in: 1012...1018)
            run.altitude = Double.random(in: 10...50)
            
            if i == 0 {
                run.notes = "First sprint"
            } else if i == 1 {
                run.notes = "Feeling stronger"
            } else {
                run.notes = "Last one, pushed hard!"
            }
            
            modelContext.insert(run)
        }
        
        // Add daily note for yesterday's 200m training
        dailyNotesManager.setNote("200m training day - interval session", for: yesterday)
        
        // Save all runs
        do {
            try modelContext.save()
            // Refresh the UI
            await updateDebugInfo()
        } catch {
            // Test data generation failed
        }
    }
    
    @MainActor
    private func clearAllData() async {
        let modelContext = dataManager.modelContainer.mainContext

        do {
            // Fetch all runs
            let descriptor = FetchDescriptor<Run>()
            let allRuns = try modelContext.fetch(descriptor)

            // Delete each run
            for run in allRuns {
                modelContext.delete(run)
            }

            // Save changes
            try modelContext.save()

            // Clear all daily notes
            DailyNotesManager.shared.clearAllNotes()

            // Mark as intentional clear so auto-restore doesn't trigger
            BackupManager.shared.userClearedData = true

            // Refresh the UI
            await updateDebugInfo()
        } catch {
            // Clear data failed
        }
    }
}

struct RestoreBackupView: View {
    let backups: [BackupManager.BackupInfo]
    @StateObject private var backupManager = BackupManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var restoredSuccessfully = false

    var body: some View {
        NavigationView {
            List {
                if backups.isEmpty {
                    Text("No backups found in iCloud")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(backups) { backup in
                        Button {
                            Task {
                                let success = await backupManager.restoreFromBackup(id: backup.id)
                                if success {
                                    restoredSuccessfully = true
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(backup.runCount) runs")
                                        .font(.headline)
                                    Spacer()
                                    Text(backup.deviceName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(backup.date, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(backup.date, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(backupManager.isRestoring)
                    }
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Restore Complete", isPresented: $restoredSuccessfully) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your data has been restored from the backup.")
            }
        }
    }
}

