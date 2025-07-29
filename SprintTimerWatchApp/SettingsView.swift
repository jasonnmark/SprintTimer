import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedStartModeIndex = 0
    @State private var debugInfo = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // DEBUG INFO AT TOP
                VStack(alignment: .leading, spacing: 5) {
                    Text("DEBUG")
                        .font(.caption2)
                        .foregroundColor(.red)
                    ScrollView {
                        Text(debugInfo)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 80)
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
                        Task { await updateDebugInfo() }
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
                                Task { await updateDebugInfo() }
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
                    .onChange(of: dataManager.useGPS) { _, _ in Task { await updateDebugInfo() } }
                    .onChange(of: dataManager.useHealthKit) { _, _ in Task { await updateDebugInfo() } }
                    .onChange(of: dataManager.trackWeather) { _, _ in Task { await updateDebugInfo() } }
                    .onChange(of: dataManager.trackAltitude) { _, _ in Task { await updateDebugInfo() } }
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
                    .onChange(of: dataManager.saveTapTime) { _, _ in Task { await updateDebugInfo() } }
                    .onChange(of: dataManager.saveGPSTime) { _, _ in Task { await updateDebugInfo() } }
                    
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
            }
            .padding(.vertical)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupInitialState()
            Task { await updateDebugInfo() }
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
}
