import SwiftUI
import SwiftData

struct iOSSettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    @State private var debugInfo = ""
    @State private var selectedStartModeIndex = 0
    @State private var showingClearAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                // DEBUG SECTION AT TOP
                Section(header: Text("Debug Info").foregroundColor(.red)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(debugInfo)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 150)
                    
                    Button("Refresh Debug Info") {
                        Task {
                            await updateDebugInfo()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Add Test Data") {
                        Task {
                            await generateTestData()
                        }
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
                    Toggle("HealthKit Integration", isOn: $dataManager.useHealthKit)
                        .onChange(of: dataManager.useHealthKit) { _, _ in Task { await updateDebugInfo() } }
                    Toggle("Weather Data", isOn: $dataManager.trackWeather)
                        .onChange(of: dataManager.trackWeather) { _, _ in Task { await updateDebugInfo() } }
                    Toggle("Altitude Tracking", isOn: $dataManager.trackAltitude)
                        .onChange(of: dataManager.trackAltitude) { _, _ in Task { await updateDebugInfo() } }
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
                        
                        if dataManager.useHealthKit {
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
                        
                        if dataManager.trackWeather {
                            Label("Temperature", systemImage: "thermometer")
                            Label("Humidity & Pressure", systemImage: "cloud")
                            Label("Air Quality", systemImage: "aqi.medium")
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
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            dataManager.refresh() // Force refresh on appear
            setupInitialState()
            Task { await updateDebugInfo() }
        }
        // Update UI when DataManager changes
        .onReceive(dataManager.objectWillChange) { _ in
            setupInitialState()
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
    }
    
    private func setupInitialState() {
        // Set the picker index based on current start mode
        if let index = StartMode.allCases.firstIndex(of: dataManager.startMode) {
            selectedStartModeIndex = index
        }
    }
    
    private func updateDebugInfo() async {
        debugInfo = await dataManager.getDebugInfo()
        print(debugInfo)
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
            print("✅ Test data added: 10 x 100m runs and 3 x 200m runs")
            
            // Refresh the UI
            await updateDebugInfo()
        } catch {
            print("❌ Error adding test data: \(error)")
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
            
            print("✅ All data cleared")
            
            // Refresh the UI
            await updateDebugInfo()
        } catch {
            print("❌ Error clearing data: \(error)")
        }
    }
}
