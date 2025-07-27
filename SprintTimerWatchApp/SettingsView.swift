import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedStartModeIndex = 0
    @State private var debugInfo = ""
    @State private var runCount = 0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // DEBUG INFO AT TOP
                VStack(alignment: .leading, spacing: 5) {
                    Text("DEBUG")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(debugInfo)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Runs: \(runCount)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
                
                // START OPTIONS
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
                        updateDebugInfo()
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
                            .onChange(of: dataManager.countdownTime) { _, _ in
                                updateDebugInfo()
                            }
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
                    .onChange(of: dataManager.useGPS) { _, _ in updateDebugInfo() }
                    .onChange(of: dataManager.useHealthKit) { _, _ in updateDebugInfo() }
                    .onChange(of: dataManager.trackWeather) { _, _ in updateDebugInfo() }
                    .onChange(of: dataManager.trackAltitude) { _, _ in updateDebugInfo() }
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
                    .onChange(of: dataManager.saveTapTime) { _, _ in updateDebugInfo() }
                    .onChange(of: dataManager.saveGPSTime) { _, _ in updateDebugInfo() }
                    
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
                    updateDebugInfo()
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
            .padding(.vertical)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupInitialState()
            updateDebugInfo()
        }
    }
    
    private func setupInitialState() {
        // Set the picker index based on current start mode
        if let index = StartMode.allCases.firstIndex(of: dataManager.startMode) {
            selectedStartModeIndex = index
        }
    }
    
    private func updateDebugInfo() {
        debugInfo = dataManager.getDebugInfo()
        print(debugInfo)
        
        Task {
            runCount = await dataManager.getRunCount()
        }
    }
}
