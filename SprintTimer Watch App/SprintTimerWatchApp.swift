import SwiftUI
import SwiftData

@main
struct SprintTimerWatchApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Run.self
        ])
        
        // Use App Group for shared data with iPhone
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.JasonMark.SprintTimer" // UPDATE THIS with your actual app group ID from Xcode
        ) else {
            fatalError("App Group container could not be created. Make sure App Groups capability is enabled and the identifier matches exactly.")
        }
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
            ContentView() // This is your existing Watch ContentView
        }
        .modelContainer(sharedModelContainer)
    }
}
