import SwiftUI
import SwiftData

// MARK: - Individual Section Components
struct StartOptionsSection: View {
    let dataManager: DataManager
    @Binding var selectedStartModeIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start Method")
                .font(.headline)
                .padding(.horizontal)
            
            // Scrolling picker for start method
            Picker("Start Method", selection: $selectedStartModeIndex) {
                ForEach(0..<StartMode.allCases.count, id: \.self) { index in
                    Text(StartMode.allCases[index].displayName)
                        .tag(index)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 80)
            .labelsHidden()
            .onChange(of: selectedStartModeIndex) { _, newValue in
                dataManager.startMode = StartMode.allCases[newValue]
            }
            
            if dataManager.startMode == .countdown {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Countdown Time")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    Picker("", selection: .constant(dataManager.countdownTime)) {
                        Text("10 sec").tag(10)
                        Text("15 sec").tag(15)
                        Text("20 sec").tag(20)
                        Text("30 sec").tag(30)
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 70)
                    .labelsHidden()
                }
            }
            
            Text(dataManager.startMode.description)
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
        }
    }
}

struct DataCollectionSection: View {
    let useGPS: Bool
    let useHealthKit: Bool
    let trackWeather: Bool
    let trackAltitude: Bool
    let onToggleGPS: (Bool) -> Void
    let onToggleHealthKit: (Bool) -> Void
    let onToggleWeather: (Bool) -> Void
    let onToggleAltitude: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Collection")
                .font(.headline)
                .padding(.horizontal)
            
            Group {
                Toggle("GPS Verification", isOn: Binding(
                    get: { useGPS },
                    set: onToggleGPS
                ))
                Toggle("HealthKit Integration", isOn: Binding(
                    get: { useHealthKit },
                    set: onToggleHealthKit
                ))
                Toggle("Weather Data", isOn: Binding(
                    get: { trackWeather },
                    set: onToggleWeather
                ))
                Toggle("Altitude Tracking", isOn: Binding(
                    get: { trackAltitude },
                    set: onToggleAltitude
                ))
            }
            .padding(.horizontal)
        }
    }
}

struct SaveOptionsSection: View {
    let saveTapTime: Bool
    let saveGPSTime: Bool
    let onToggleTapTime: (Bool) -> Void
    let onToggleGPSTime: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save Options")
                .font(.headline)
                .padding(.horizontal)
            
            Group {
                Toggle("Save Tap Time", isOn: Binding(
                    get: { saveTapTime },
                    set: onToggleTapTime
                ))
                Toggle("Save GPS Time", isOn: Binding(
                    get: { saveGPSTime },
                    set: onToggleGPSTime
                ))
            }
            .padding(.horizontal)
            
            if saveTapTime && saveGPSTime {
                Text("Both tap and GPS times will be recorded")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }
        }
    }
}

struct RefreshButtonSection: View {
    let dataManager: DataManager
    let onUpdateDebugInfo: () async -> Void
    
    var body: some View {
        Button(action: {
            dataManager.refresh()
            Task { await onUpdateDebugInfo() }
        }) {
            Text("Refresh Settings")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

struct DebugInfoSection: View {
    @Binding var showDebugInfo: Bool
    let debugInfo: String
    let onUpdateDebugInfo: () async -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: {
                showDebugInfo.toggle()
                if showDebugInfo {
                    Task { await onUpdateDebugInfo() }
                }
            }) {
                HStack {
                    Text("DEBUG INFO")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Spacer()
                    Image(systemName: showDebugInfo ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            if showDebugInfo {
                Text(debugInfo)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.red)
                    .lineLimit(15)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 100)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 10)
    }
}

struct DeleteDataSection: View {
    @Binding var showingClearAlert: Bool
    
    var body: some View {
        VStack {
            Divider().padding(.vertical, 8)
            
            Button(action: {
                showingClearAlert = true
            }) {
                Text("Delete All Data")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }
}

// MARK: - Settings Content View (Isolated Component)
struct SettingsContentView: View {
    let dataManager: DataManager
    @Binding var selectedStartModeIndex: Int
    @Binding var showDebugInfo: Bool
    @Binding var debugInfo: String
    @Binding var showingClearAlert: Bool
    
    let onUpdateDebugInfo: () async -> Void
    let onClearAllData: () async -> Void
    let onToggleGPS: (Bool) -> Void
    let onToggleHealthKit: (Bool) -> Void
    let onToggleWeather: (Bool) -> Void
    let onToggleAltitude: (Bool) -> Void
    let onToggleTapTime: (Bool) -> Void
    let onToggleGPSTime: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // START OPTIONS - MOVED TO TOP
            StartOptionsSection(
                dataManager: dataManager,
                selectedStartModeIndex: $selectedStartModeIndex
            )
            
            Divider().padding(.vertical, 5)
            
            // DATA COLLECTION
            DataCollectionSection(
                useGPS: dataManager.useGPS,
                useHealthKit: dataManager.useHealthKit,
                trackWeather: dataManager.trackWeather,
                trackAltitude: dataManager.trackAltitude,
                onToggleGPS: onToggleGPS,
                onToggleHealthKit: onToggleHealthKit,
                onToggleWeather: onToggleWeather,
                onToggleAltitude: onToggleAltitude
            )
            
            Divider().padding(.vertical, 5)
            
            // SAVE OPTIONS
            SaveOptionsSection(
                saveTapTime: dataManager.saveTapTime,
                saveGPSTime: dataManager.saveGPSTime,
                onToggleTapTime: onToggleTapTime,
                onToggleGPSTime: onToggleGPSTime
            )
            
            // Refresh Button
            RefreshButtonSection(
                dataManager: dataManager,
                onUpdateDebugInfo: onUpdateDebugInfo
            )
            
            // DEBUG INFO AT BOTTOM - COLLAPSIBLE
            DebugInfoSection(
                showDebugInfo: $showDebugInfo,
                debugInfo: debugInfo,
                onUpdateDebugInfo: onUpdateDebugInfo
            )
            
            // DELETE ALL DATA - AT BOTTOM
            DeleteDataSection(showingClearAlert: $showingClearAlert)
        }
        .padding(.vertical)
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedStartModeIndex = 0
    @State private var debugInfo = ""
    @State private var showDebugInfo = false
    @State private var showingClearAlert = false
    
    var body: some View {
        ScrollView {
            SettingsContentView(
                dataManager: dataManager,
                selectedStartModeIndex: $selectedStartModeIndex,
                showDebugInfo: $showDebugInfo,
                debugInfo: $debugInfo,
                showingClearAlert: $showingClearAlert,
                onUpdateDebugInfo: updateDebugInfo,
                onClearAllData: clearAllData,
                onToggleGPS: { dataManager.useGPS = $0 },
                onToggleHealthKit: { dataManager.useHealthKit = $0 },
                onToggleWeather: { dataManager.trackWeather = $0 },
                onToggleAltitude: { dataManager.trackAltitude = $0 },
                onToggleTapTime: { dataManager.saveTapTime = $0 },
                onToggleGPSTime: { dataManager.saveGPSTime = $0 }
            )
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            // Force save when view disappears
            dataManager.defaults.synchronize()
        }
        .alert("Delete All Data?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await clearAllData() }
            }
        } message: {
            Text("This will permanently delete all runs and daily notes. This action cannot be undone.")
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
    private func clearAllData() async {
        let modelContext = dataManager.modelContainer.mainContext
        do {
            // Delete all runs
            let descriptor = FetchDescriptor<Run>()
            let runs = try modelContext.fetch(descriptor)
            for run in runs { modelContext.delete(run) }
            try modelContext.save()

            // Clear daily notes
            DailyNotesManager.shared.clearAllNotes()

            // Refresh debug info
            await updateDebugInfo()
            print("✅ All data cleared (watch settings)")
        } catch {
            print("❌ Error clearing all data: \(error)")
        }
    }
}
