import SwiftUI
import SwiftData

@main
struct SprintTimerApp: App {
    let dataManager = DataManager.shared
    
    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .preferredColorScheme(.dark) // Force dark mode
        }
        .modelContainer(dataManager.modelContainer)
    }
}
