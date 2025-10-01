import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedStartModeIndex = 0
    @State private var debugInfo = ""
    @State private var showDebugInfo = false
    @State private var showingClearAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // START OPTIONS - MOVED TO TOP
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
                            
                            Picker("", selection: $dataManager.countdownTime) {
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
                
                Divider()
                    .padding(.vertical, 5)
                
                // DATA COLLECTION
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data Collection")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Group {
                        Toggle("GPS Verification", isOn: $dataManager.useGPS)
                        Toggle("HealthKit Integration", isOn: $dataManager.useHealthKit)
                        Toggle("Weather Data", isOn: $dataManager.trackWeather)
                        Toggle("Altitude Tracking", isOn: $dataManager.trackAltitude)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                    .padding(.vertical, 5)
                
                // SAVE OPTIONS
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save Options")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Group {
                        Toggle("Save Tap Time", isOn: $dataManager.saveTapTime)
                        Toggle("Save GPS Time", isOn: $dataManager.saveGPSTime)
                    }
                    .padding(.horizontal)
                    
                    if dataManager.saveTapTime && dataManager.saveGPSTime {
                        Text("Both tap and GPS times will be recorded")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                    }
                }
                
                // Refresh Button
                Button(action: {
                    dataManager.refresh()
                    Task { await updateDebugInfo() }
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
                
                // DEBUG INFO AT BOTTOM - COLLAPSIBLE
                VStack(alignment: .leading, spacing: 5) {
                    Button(action: {
                        showDebugInfo.toggle()
                        if showDebugInfo {
                            Task { await updateDebugInfo() }
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
                        ScrollView {
                            Text(debugInfo)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxHeight: 100)
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 10)
                
                // DELETE ALL DATA - AT BOTTOM
                Divider()
                    .padding(.vertical, 8)

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
            .padding(.vertical)
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
