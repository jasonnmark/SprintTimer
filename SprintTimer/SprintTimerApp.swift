import SwiftUI
import SwiftData

@main
struct SprintTimerApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Run.self
        ])
        
        // Use App Group for shared data with Watch
        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.jasonmark.SprintTimer" // Update with your actual app group ID
        )!
        let databaseURL = groupURL.appendingPathComponent("SprintTimer.sqlite")
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: databaseURL,
            allowsSave: true
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView() // This will be your main iOS view
                .modelContainer(sharedModelContainer)
        }
    }
}
