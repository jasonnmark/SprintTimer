import SwiftUI
import SwiftData

@main
struct SprintTimerApp: App {
    @State private var isReady = false
    @State private var showRestorePrompt = false

    private let dataManager = DataManager.shared
    private let syncManager = SyncManager.shared

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
