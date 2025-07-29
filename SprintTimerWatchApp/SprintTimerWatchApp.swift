import SwiftUI
import SwiftData

@main
struct SprintTimerWatchApp: App {
    let dataManager: DataManager
    let syncManager: SyncManager
    
    init() {
        // Initialize in controlled order
        self.dataManager = DataManager.shared
        self.syncManager = SyncManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView() // Or whatever your main watch view is called
                .preferredColorScheme(.dark) // Force dark mode
        }
        .modelContainer(dataManager.modelContainer)
    }
}
