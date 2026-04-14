import Foundation
import SwiftData
import Combine
import os

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
import WidgetKit
#endif

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "DataManager")

// Custom run type for user-defined distances
struct CustomRunType: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var distance: Int

    init(name: String, distance: Int) {
        self.id = UUID()
        self.name = name
        self.distance = distance
    }
}

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

    let defaults: UserDefaults
    private let appGroupID = "group.com.JasonMark.SprintTimer"
    private var isInitializing = true

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
    private let customRunTypesKey = "settings.customRunTypes"
    private let hasSeenTutorialKey = "settings.hasSeenTutorial"
    private let openWeatherAPIKeyKey = "settings.openWeatherAPIKey"
    private let betaModeKey = "settings.betaMode"

    @Published var betaMode: Bool = false {
        didSet {
            defaults.set(betaMode, forKey: betaModeKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var hasSeenTutorial: Bool = false {
        didSet {
            defaults.set(hasSeenTutorial, forKey: hasSeenTutorialKey)
        }
    }

    // Custom run types
    @Published var customRunTypes: [CustomRunType] = [] {
        didSet {
            guard !isInitializing else { return }
            saveCustomRunTypes()
            if !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    // All available distances (built-in + custom)
    var allDistances: [(label: String, distance: Int)] {
        var result: [(label: String, distance: Int)] = [
            ("100m", 100),
            ("200m", 200),
            ("400m", 400)
        ]
        for custom in customRunTypes {
            result.append((custom.name, custom.distance))
        }
        return result
    }

    // Settings Properties
    @Published var startMode: StartMode = .tap {
        didSet {
            guard oldValue != startMode else { return }
            defaults.set(startMode.rawValue, forKey: startModeKey)
            if !isInitializing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var countdownTime: Int = 5 {
        didSet {
            defaults.set(countdownTime, forKey: countdownTimeKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var useGPS: Bool = true {
        didSet {
            defaults.set(useGPS, forKey: useGPSKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var useHealthKit: Bool = true {
        didSet {
            defaults.set(useHealthKit, forKey: useHealthKitKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var trackWeather: Bool = false {
        didSet {
            defaults.set(trackWeather, forKey: trackWeatherKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var trackAltitude: Bool = true {
        didSet {
            defaults.set(trackAltitude, forKey: trackAltitudeKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var saveTapTime: Bool = true {
        didSet {
            defaults.set(saveTapTime, forKey: saveTapTimeKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
        }
    }

    @Published var saveGPSTime: Bool = false {
        didSet {
            defaults.set(saveGPSTime, forKey: saveGPSTimeKey)
            if !isInitializing && !SyncManager.shared.isUpdatingFromSync {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SyncManager.shared.syncSettings()
                }
            }
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
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            logger.info("SwiftData initialized at \(databaseURL.path)")
        } catch {
            logger.error("Failed to create ModelContainer: \(error). Attempting database reset...")

            // Try to delete the existing database
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("sqlite-shm"))
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("sqlite-wal"))

            // Try again
            do {
                self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                logger.info("SwiftData initialized after database reset")
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }

        // Initialize settings with defaults
        initializeDefaults()

        // Load current values
        loadSettings()

        // Mark initialization as complete
        isInitializing = false
    }

    private func initializeDefaults() {
        // Set defaults if never saved
        if defaults.object(forKey: useGPSKey) == nil {
            defaults.set(true, forKey: useGPSKey)
        }
        if defaults.object(forKey: useHealthKitKey) == nil {
            defaults.set(true, forKey: useHealthKitKey)
        }
        if defaults.object(forKey: trackWeatherKey) == nil {
            defaults.set(false, forKey: trackWeatherKey)
        }
        if defaults.object(forKey: trackAltitudeKey) == nil {
            defaults.set(true, forKey: trackAltitudeKey)
        }
        if defaults.object(forKey: saveTapTimeKey) == nil {
            defaults.set(true, forKey: saveTapTimeKey)
        }
        if defaults.object(forKey: saveGPSTimeKey) == nil {
            defaults.set(false, forKey: saveGPSTimeKey)
        }
        if defaults.object(forKey: startModeKey) == nil {
            defaults.set(StartMode.tap.rawValue, forKey: startModeKey)
        }
        if defaults.object(forKey: countdownTimeKey) == nil {
            defaults.set(5, forKey: countdownTimeKey)
        }
    }

    private func loadSettings() {
        let savedMode = defaults.string(forKey: startModeKey) ?? StartMode.tap.rawValue
        startMode = StartMode(rawValue: savedMode) ?? .tap
        countdownTime = defaults.integer(forKey: countdownTimeKey) > 0 ? defaults.integer(forKey: countdownTimeKey) : 5
        useGPS = defaults.bool(forKey: useGPSKey)
        useHealthKit = defaults.bool(forKey: useHealthKitKey)
        trackWeather = defaults.bool(forKey: trackWeatherKey)
        trackAltitude = defaults.bool(forKey: trackAltitudeKey)
        saveTapTime = defaults.bool(forKey: saveTapTimeKey)
        saveGPSTime = defaults.bool(forKey: saveGPSTimeKey)
        hasSeenTutorial = defaults.bool(forKey: hasSeenTutorialKey)
        betaMode = defaults.bool(forKey: betaModeKey)
        loadCustomRunTypes()
    }

    private func saveCustomRunTypes() {
        if let data = try? JSONEncoder().encode(customRunTypes) {
            defaults.set(data, forKey: customRunTypesKey)
        }
    }

    private func loadCustomRunTypes() {
        if let data = defaults.data(forKey: customRunTypesKey),
           let types = try? JSONDecoder().decode([CustomRunType].self, from: data) {
            customRunTypes = types
        }
    }

    func refresh() {
        loadSettings()
    }

    // MARK: - Debug Info

    @MainActor
    func getDebugInfo() async -> String {
        var info = "=== DEBUG INFO ===\n"
        info += "App Group: \(appGroupID)\n"
        #if os(iOS)
        info += "Platform: iOS\n"
        #else
        info += "Platform: watchOS\n"
        #endif
        info += "Time: \(Date().formatted())\n\n"

        info += "--- SETTINGS ---\n"
        info += "Start Mode: \(startMode.rawValue)\n"
        info += "Countdown: \(countdownTime)s\n"
        info += "GPS: \(useGPS)\n"
        info += "HealthKit: \(useHealthKit)\n"
        info += "Weather: \(trackWeather)\n"
        info += "Altitude: \(trackAltitude)\n"
        info += "Save Tap Time: \(saveTapTime)\n"
        info += "Save GPS Time: \(saveGPSTime)\n\n"

        info += "--- DATA ---\n"
        let runCount = await getRunCount()
        info += "Total Runs: \(runCount)\n"
        info += "Daily Notes: \(DailyNotesManager.shared.dailyNotes.count)\n\n"

        info += "--- SYNC STATUS ---\n"
        if WCSession.isSupported() {
            let session = WCSession.default
            info += "WCSession Active: \(session.activationState == .activated)\n"
            #if os(iOS)
            info += "Paired: \(session.isPaired)\n"
            info += "Watch Installed: \(session.isWatchAppInstalled)\n"
            #endif
            info += "Reachable: \(session.isReachable)\n"
        } else {
            info += "WCSession: Not supported\n"
        }

        info += "\n--- RECENT RUNS ---\n"
        if let recentRuns = await getRecentRuns(limit: 3) {
            for (index, run) in recentRuns.enumerated() {
                info += "\(index + 1). \(run.distance)m in \(run.formattedTime)\n"
                info += "   \(run.formattedDate)\n"
            }
        }

        return info
    }

    @MainActor
    func getRunCount() async -> Int {
        do {
            let descriptor = FetchDescriptor<Run>()
            let runs = try modelContainer.mainContext.fetch(descriptor)
            return runs.count
        } catch {
            logger.error("Error fetching runs: \(error)")
            return -1
        }
    }

    @MainActor
    func getRecentRuns(limit: Int) async -> [Run]? {
        do {
            let descriptor = FetchDescriptor<Run>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let runs = try modelContainer.mainContext.fetch(descriptor)
            return Array(runs.prefix(limit))
        } catch {
            logger.error("Error fetching recent runs: \(error)")
            return nil
        }
    }

    // MARK: - History Management

    @MainActor
    func saveRun(_ run: Run) {
        modelContainer.mainContext.insert(run)
        do {
            try modelContainer.mainContext.save()

            // Sync to other device
            let runData = SyncManager.shared.runToSyncData(run)
            SyncManager.shared.syncNewRun(runData)

            // Update complication data
            updateComplicationData(lastRun: run)

            // Schedule cloud backup (iPhone only)
            #if os(iOS)
            BackupManager.shared.scheduleBackup()
            #endif

        } catch {
            logger.error("Failed to save run: \(error)")
        }
    }

    @MainActor
    func updateComplicationData(lastRun: Run) {
        defaults.set(lastRun.formattedTime, forKey: "complication.lastRunTime")
        defaults.set(lastRun.distance, forKey: "complication.lastRunDistance")

        // Count today's runs
        let startOfDay = Calendar.current.startOfDay(for: Date())
        do {
            let descriptor = FetchDescriptor<Run>()
            let allRuns = try modelContainer.mainContext.fetch(descriptor)
            let todayCount = allRuns.filter { $0.date >= startOfDay }.count
            defaults.set(todayCount, forKey: "complication.todayRunCount")
        } catch {
            logger.error("Error counting today's runs: \(error)")
        }

        // Reload complications
        #if os(watchOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    @MainActor
    func deleteRun(_ run: Run) {
        let runId = run.id
        modelContainer.mainContext.delete(run)
        do {
            try modelContainer.mainContext.save()

            // Sync deletion to other device
            SyncManager.shared.syncRunDeletion(runId)

        } catch {
            logger.error("Failed to delete run: \(error)")
        }
    }
}

// MARK: - WatchConnectivity Import
import WatchConnectivity
