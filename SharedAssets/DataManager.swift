import Foundation
import SwiftData
import Combine

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

// Add this file to BOTH iPhone and Watch targets
enum StartMode: String, CaseIterable {
    case countdown = "countdown"
    case motion = "motion"
    case tap = "tap"
    
    var displayName: String {
        switch self {
        case .countdown:
            return "Countdown"
        case .motion:
            return "Motion Start"
        case .tap:
            return "Tap to Start"
        }
    }
    
    var description: String {
        switch self {
        case .countdown:
            return "Timer starts after countdown with audio cues"
        case .motion:
            return "Timer starts when motion is detected"
        case .tap:
            return "Timer starts immediately when you tap Start"
        }
    }
}

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    private let defaults: UserDefaults
    private let appGroupID = "group.com.JasonMark.SprintTimer"
    private var refreshTimer: Timer?
    
    // Model container for SwiftData
    let modelContainer: ModelContainer
    
    // Settings Keys
    private let startModeKey = "settings.startMode"
    private let countdownTimeKey = "settings.countdownTime"
    private let useGPSKey = "settings.useGPS"
    private let useHealthKitKey = "settings.useHealthKit"
    private let trackWeatherKey = "settings.trackWeather"
    private let trackAltitudeKey = "settings.trackAltitude"
    private let saveTapTimeKey = "settings.saveTapTime"
    private let saveGPSTimeKey = "settings.saveGPSTime"
    
    // Settings Properties
    @Published var startMode: StartMode = .tap {
        didSet {
            defaults.set(startMode.rawValue, forKey: startModeKey)
            defaults.synchronize()
            print("DataManager: Set startMode to \(startMode.rawValue)")
        }
    }
    
    @Published var countdownTime: Int = 10 {
        didSet {
            defaults.set(countdownTime, forKey: countdownTimeKey)
            defaults.synchronize()
        }
    }
    
    @Published var useGPS: Bool = true {
        didSet {
            defaults.set(useGPS, forKey: useGPSKey)
            defaults.synchronize()
        }
    }
    
    @Published var useHealthKit: Bool = true {
        didSet {
            defaults.set(useHealthKit, forKey: useHealthKitKey)
            defaults.synchronize()
        }
    }
    
    @Published var trackWeather: Bool = true {
        didSet {
            defaults.set(trackWeather, forKey: trackWeatherKey)
            defaults.synchronize()
        }
    }
    
    @Published var trackAltitude: Bool = true {
        didSet {
            defaults.set(trackAltitude, forKey: trackAltitudeKey)
            defaults.synchronize()
        }
    }
    
    @Published var saveTapTime: Bool = true {
        didSet {
            defaults.set(saveTapTime, forKey: saveTapTimeKey)
            defaults.synchronize()
        }
    }
    
    @Published var saveGPSTime: Bool = false {
        didSet {
            defaults.set(saveGPSTime, forKey: saveGPSTimeKey)
            defaults.synchronize()
        }
    }
    
    private init() {
        // Initialize UserDefaults
        guard let groupDefaults = UserDefaults(suiteName: appGroupID) else {
            fatalError("Failed to create UserDefaults for app group: \(appGroupID)")
        }
        self.defaults = groupDefaults
        
        // Initialize SwiftData
        let schema = Schema([Run.self])
        
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            fatalError("App Group container could not be created.")
        }
        
        let databaseURL = groupURL.appendingPathComponent("SprintTimer.sqlite")
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: databaseURL,
            allowsSave: true
        )
        
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("✅ DataManager: SwiftData initialized at \(databaseURL.path)")
        } catch {
            print("❌ DataManager: Failed to create ModelContainer: \(error)")
            print("Attempting to delete existing database and retry...")
            
            // Try to delete the existing database
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("sqlite-shm"))
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("sqlite-wal"))
            
            // Try again
            do {
                self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ DataManager: SwiftData initialized after database reset")
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
        
        // Initialize settings with defaults
        initializeDefaults()
        
        // Load current values
        loadSettings()
        
        // Set up periodic refresh for settings sync
        startPeriodicRefresh()
        
        print("✅ DataManager initialized successfully")
    }
    
    private func startPeriodicRefresh() {
        // Refresh every 2 seconds to catch changes from other device
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.loadSettings()
        }
    }
    
    private func initializeDefaults() {
        // Set defaults if never saved
        if defaults.object(forKey: useGPSKey) == nil {
            defaults.set(true, forKey: useGPSKey)
            print("DataManager: Initialized useGPS to true")
        }
        if defaults.object(forKey: useHealthKitKey) == nil {
            defaults.set(true, forKey: useHealthKitKey)
            print("DataManager: Initialized useHealthKit to true")
        }
        if defaults.object(forKey: trackWeatherKey) == nil {
            defaults.set(true, forKey: trackWeatherKey)
            print("DataManager: Initialized trackWeather to true")
        }
        if defaults.object(forKey: trackAltitudeKey) == nil {
            defaults.set(true, forKey: trackAltitudeKey)
            print("DataManager: Initialized trackAltitude to true")
        }
        if defaults.object(forKey: saveTapTimeKey) == nil {
            defaults.set(true, forKey: saveTapTimeKey)
            print("DataManager: Initialized saveTapTime to true")
        }
        if defaults.object(forKey: saveGPSTimeKey) == nil {
            defaults.set(false, forKey: saveGPSTimeKey)
            print("DataManager: Initialized saveGPSTime to false")
        }
        if defaults.object(forKey: startModeKey) == nil {
            defaults.set(StartMode.tap.rawValue, forKey: startModeKey)
            print("DataManager: Initialized startMode to tap")
        }
        if defaults.object(forKey: countdownTimeKey) == nil {
            defaults.set(10, forKey: countdownTimeKey)
            print("DataManager: Initialized countdownTime to 10")
        }
        
        defaults.synchronize()
    }
    
    private func loadSettings() {
        // Load and check if values changed
        let oldStartMode = startMode
        let oldCountdown = countdownTime
        let oldGPS = useGPS
        let oldHealthKit = useHealthKit
        let oldWeather = trackWeather
        let oldAltitude = trackAltitude
        let oldTapTime = saveTapTime
        let oldGPSTime = saveGPSTime
        
        // Load new values
        let savedMode = defaults.string(forKey: startModeKey) ?? StartMode.tap.rawValue
        startMode = StartMode(rawValue: savedMode) ?? .tap
        countdownTime = defaults.integer(forKey: countdownTimeKey) > 0 ? defaults.integer(forKey: countdownTimeKey) : 10
        useGPS = defaults.bool(forKey: useGPSKey)
        useHealthKit = defaults.bool(forKey: useHealthKitKey)
        trackWeather = defaults.bool(forKey: trackWeatherKey)
        trackAltitude = defaults.bool(forKey: trackAltitudeKey)
        saveTapTime = defaults.bool(forKey: saveTapTimeKey)
        saveGPSTime = defaults.bool(forKey: saveGPSTimeKey)
        
        // If anything changed, notify UI
        if oldStartMode != startMode || oldCountdown != countdownTime ||
           oldGPS != useGPS || oldHealthKit != useHealthKit ||
           oldWeather != trackWeather || oldAltitude != trackAltitude ||
           oldTapTime != saveTapTime || oldGPSTime != saveGPSTime {
            objectWillChange.send()
            print("Settings changed from other device")
        }
    }
    
    func refresh() {
        defaults.synchronize()
        loadSettings()
        objectWillChange.send()
        print("DataManager: Settings refreshed")
    }
    
    func getDebugInfo() -> String {
        defaults.synchronize()
        
        var info = "=== DataManager Debug ===\n"
        info += "App Group: \(appGroupID)\n"
        #if os(iOS)
        info += "Platform: iOS\n"
        #else
        info += "Platform: watchOS\n"
        #endif
        info += "--- Settings ---\n"
        info += "Start Mode: \(startMode.rawValue)\n"
        info += "Countdown: \(countdownTime)s\n"
        info += "--- Data Collection ---\n"
        info += "GPS: \(useGPS)\n"
        info += "HealthKit: \(useHealthKit)\n"
        info += "Weather: \(trackWeather)\n"
        info += "Altitude: \(trackAltitude)\n"
        info += "--- Save Options ---\n"
        info += "Tap Time: \(saveTapTime)\n"
        info += "GPS Time: \(saveGPSTime)\n"
        info += "========================"
        
        return info
    }
    
    @MainActor
    func getRunCount() async -> Int {
        do {
            let descriptor = FetchDescriptor<Run>()
            let runs = try modelContainer.mainContext.fetch(descriptor)
            return runs.count
        } catch {
            print("Error fetching runs: \(error)")
            return -1
        }
    }
    
    // History Management
    @MainActor
    func saveRun(_ run: Run) {
        modelContainer.mainContext.insert(run)
        do {
            try modelContainer.mainContext.save()
            print("✅ DataManager: Run saved successfully")
        } catch {
            print("❌ DataManager: Failed to save run: \(error)")
        }
    }
    
    @MainActor
    func deleteRun(_ run: Run) {
        modelContainer.mainContext.delete(run)
        do {
            try modelContainer.mainContext.save()
        } catch {
            print("❌ DataManager: Failed to delete run: \(error)")
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
}
