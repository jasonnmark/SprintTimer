import SwiftUI
import SwiftData

@main
struct SprintTimerApp: App {
    let dataManager: DataManager
    let syncManager: SyncManager
    
    init() {
        // Initialize in controlled order
        self.dataManager = DataManager.shared
        self.syncManager = SyncManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .preferredColorScheme(.dark) // Force dark mode
        }
        .modelContainer(dataManager.modelContainer)
    }
}
