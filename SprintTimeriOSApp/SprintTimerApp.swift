import SwiftUI
import SwiftData

@main
struct SprintTimerApp: App {
    @State private var isReady = false
    @State private var showRestorePrompt = false
    @State private var showWeatherPrompt = false

    private let dataManager = DataManager.shared
    private let syncManager = SyncManager.shared
    private let hasShownWeatherPromptKey = "hasShownWeatherPrompt"

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    iOSContentView()
                } else {
                    LaunchLoadingView()
                        .onAppear {
                            DispatchQueue.main.async {
                                isReady = true
                            }
                        }
                }
            }
            .preferredColorScheme(.dark)
            .task {
                // Check for auto-restore on launch (empty database + cloud backup available)
                if await BackupManager.shared.checkForAutoRestore() {
                    showRestorePrompt = true
                }
                // Daily backup check
                BackupManager.shared.backupIfNeeded()

                // Backfill locationName for any runs that synced from the Watch
                // without one (or whose in-flight geocode failed). Throttled to
                // 24h internally so repeated launches are cheap.
                Task { await LocationBackfillService.shared.runIfNeeded() }

                // One-time weather API prompt for new users
                let defaults = UserDefaults(suiteName: "group.com.JasonMark.SprintTimer")
                if defaults?.bool(forKey: hasShownWeatherPromptKey) != true,
                   !WeatherService.shared.hasAPIKey {
                    showWeatherPrompt = true
                    defaults?.set(true, forKey: hasShownWeatherPromptKey)
                }
            }
            .alert("Restore from Backup?", isPresented: $showRestorePrompt) {
                Button("Restore") {
                    Task {
                        let backups = await BackupManager.shared.fetchBackupList()
                        if let latest = backups.first {
                            _ = await BackupManager.shared.restoreFromBackup(id: latest.id)
                        }
                    }
                }
                Button("Start Fresh", role: .cancel) {
                    BackupManager.shared.userClearedData = true
                }
            } message: {
                Text("A cloud backup was found. Would you like to restore your run history?")
            }
            .alert("Track Weather Data?", isPresented: $showWeatherPrompt) {
                Button("Open Settings") {
                    // Switch to settings tab
                    NotificationCenter.default.post(name: Notification.Name("SwitchToSettings"), object: nil)
                }
                Button("Maybe Later", role: .cancel) { }
            } message: {
                Text("Sprint Timer can record weather conditions with each run. To enable this, get a free API key from openweathermap.org and enter it in Settings.")
            }
        }
        .modelContainer(dataManager.modelContainer)
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "figure.run")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("Sprint Timer")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                ProgressView()
                    .tint(.green)
            }
        }
    }
}
