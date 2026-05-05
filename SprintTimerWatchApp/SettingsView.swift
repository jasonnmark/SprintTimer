import SwiftUI
import SwiftData
import HealthKit

// MARK: - Main Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var dataManager = DataManager.shared
    @State private var debugInfo = ""
    @State private var showingClearAlert = false
    @State private var isHealthConnected = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: Start Options
                Section("Start") {
                    NavigationLink {
                        StartModePicker(dataManager: dataManager)
                    } label: {
                        HStack {
                            Text("Mode")
                            Spacer()
                            Text(dataManager.startMode.displayName)
                                .foregroundColor(.secondary)
                        }
                    }

                    if dataManager.startMode == .countdown {
                        NavigationLink {
                            CountdownTimePicker(dataManager: dataManager)
                        } label: {
                            HStack {
                                Text("Countdown")
                                Spacer()
                                Text("\(dataManager.countdownTime)s")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // MARK: Data Collection
                Section("Data") {
                    Toggle("GPS", isOn: Binding(
                        get: { dataManager.useGPS },
                        set: { dataManager.useGPS = $0 }
                    ))
                    Text("Distance and pace via GPS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image("AppleHealthIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text("Apple Health")
                        Spacer()
                        Text(isHealthConnected ? "Connected" : "Off")
                            .foregroundColor(isHealthConnected ? .green : .secondary)
                            .font(.caption)
                    }
                    Toggle("Altitude", isOn: Binding(
                        get: { dataManager.trackAltitude },
                        set: { dataManager.trackAltitude = $0 }
                    ))
                    Text("Elevation gain via GPS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // MARK: Save Options
                Section("Save") {
                    Toggle("Tap Time", isOn: Binding(
                        get: { dataManager.saveTapTime },
                        set: { dataManager.saveTapTime = $0 }
                    ))
                    Toggle("GPS Time", isOn: Binding(
                        get: { dataManager.saveGPSTime },
                        set: { dataManager.saveGPSTime = $0 }
                    ))
                }

                // MARK: Beta
                Section {
                    Toggle("Beta Mode", isOn: Binding(
                        get: { dataManager.betaMode },
                        set: { dataManager.betaMode = $0 }
                    ))
                }

                // MARK: Beta Tools
                if dataManager.betaMode {
                    Section("Debug") {
                        Button("Show Debug Info") {
                            Task {
                                debugInfo = await dataManager.getDebugInfo()
                            }
                        }

                        if !debugInfo.isEmpty {
                            Text(debugInfo)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.red)
                        }

                        Button("Delete All Data", role: .destructive) {
                            showingClearAlert = true
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if HKHealthStore.isHealthDataAvailable() {
                    let status = HKHealthStore().authorizationStatus(for: HKObjectType.workoutType())
                    isHealthConnected = status == .sharingAuthorized
                }
            }
        }
        .alert("Delete All Data?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await clearAllData() }
            }
        } message: {
            Text("This will permanently delete all runs and daily notes.")
        }
    }

    @MainActor
    private func clearAllData() async {
        let modelContext = dataManager.modelContainer.mainContext
        do {
            let descriptor = FetchDescriptor<Run>()
            let runs = try modelContext.fetch(descriptor)
            for run in runs { modelContext.delete(run) }
            try modelContext.save()
            DailyNotesManager.shared.clearAllNotes()
        } catch {
            // Clear failed
        }
    }
}

// MARK: - Start Mode Picker (pushed screen with checkmark list)
struct StartModePicker: View {
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(StartMode.allCases, id: \.self) { mode in
                Button {
                    dataManager.startMode = mode
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                            Text(mode.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if dataManager.startMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Start Mode")
    }
}

// MARK: - Countdown Time Picker (pushed screen with checkmark list)
struct CountdownTimePicker: View {
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    private let options = [3, 5, 10, 15, 20, 30]

    var body: some View {
        List {
            ForEach(options, id: \.self) { seconds in
                Button {
                    dataManager.countdownTime = seconds
                    dismiss()
                } label: {
                    HStack {
                        Text("\(seconds) seconds")
                        Spacer()
                        if dataManager.countdownTime == seconds {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Countdown")
    }
}
