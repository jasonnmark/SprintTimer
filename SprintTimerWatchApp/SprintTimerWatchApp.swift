import SwiftUI
import SwiftData

@main
struct SprintTimerWatchApp: App {
    let dataManager = DataManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(dataManager.modelContainer)
    }
}
