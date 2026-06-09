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

// A run type (built-in or user-defined). Joined to each Run by `id` so
// that renaming a custom type propagates retroactively to history.
struct RunType: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var distance: Int
    /// Archived types stay in storage so historical runs keep their label
    /// via UUID lookup, but they're hidden from pickers and filters.
    var isArchived: Bool

    init(id: UUID = UUID(), name: String, distance: Int, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.distance = distance
        self.isArchived = isArchived
    }

    // Tolerant decoding so older stored blobs (before `isArchived`) read cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.distance = try c.decode(Int.self, forKey: .distance)
        self.isArchived = (try? c.decode(Bool.self, forKey: .isArchived)) ?? false
    }
}

extension RunType {
    static let oneHundred = RunType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
        name: "100m", distance: 100
    )
    static let twoHundred = RunType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000200")!,
        name: "200m", distance: 200
    )
    static let fourHundred = RunType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000400")!,
        name: "400m", distance: 400
    )
    static let builtIns: [RunType] = [.oneHundred, .twoHundred, .fourHundred]
    var isBuiltIn: Bool { Self.builtIns.contains { $0.id == id } }

    /// Union-merge two custom-type lists by UUID. Incoming wins on shared IDs
    /// (so renames/archives still propagate across devices), but local-only
    /// entries are KEPT — never silently deleted by a peer whose snapshot is
    /// merely stale. Built-in IDs are filtered out defensively; they belong to
    /// `RunType.builtIns`, not the custom store.
    static func merge(local: [RunType], incoming: [RunType]) -> [RunType] {
        let builtInIds = Set(builtIns.map(\.id))
        let incomingById = Dictionary(
            uniqueKeysWithValues: incoming
                .filter { !builtInIds.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let localIds = Set(local.map(\.id))

        var merged: [RunType] = local.map { localType in
            incomingById[localType.id] ?? localType
        }
        for incomingType in incoming where !localIds.contains(incomingType.id) && !builtInIds.contains(incomingType.id) {
            merged.append(incomingType)
        }
        return merged
    }
}

// Back-compat alias so any external references compile while we transition.
typealias CustomRunType = RunType

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
    private let trackWeatherKey = "settings.trackWeather"
    private let trackAltitudeKey = "settings.trackAltitude"
    private let saveTapTimeKey = "settings.saveTapTime"
    private let saveGPSTimeKey = "settings.saveGPSTime"
    private let customRunTypesKey = "settings.customRunTypes"
    private let hasSeenTutorialKey = "settings.hasSeenTutorial"
    private let openWeatherAPIKeyKey = "settings.openWeatherAPIKey"
    private let debugModeKey = "settings.betaMode"
    private let pinchOffsetSecondsKey = "settings.pinchOffsetSeconds"

    @Published var debugMode: Bool = false {
        didSet {
            defaults.set(debugMode, forKey: debugModeKey)
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

    // Custom run types (active + archived). Archived rows stay in this list
    // so historical Run records keep resolving their name via UUID lookup.
    @Published var customRunTypes: [RunType] = [] {
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

    /// Types eligible to assign to a *new* run: built-ins + non-archived customs.
    /// Used by every picker/filter UI.
    var selectableRunTypes: [RunType] {
        (RunType.builtIns + customRunTypes.filter { !$0.isArchived })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every known type including archived customs. Used for UUID → name lookups
    /// when displaying history, exports, etc.
    var allRunTypesIncludingArchived: [RunType] {
        RunType.builtIns + customRunTypes
    }

    /// Resolve a `RunType` from any UUID, including archived ones.
    func runType(for id: UUID) -> RunType? {
        allRunTypesIncludingArchived.first { $0.id == id }
    }

    // MARK: - Custom Run Type CRUD

    /// Append a new custom type. Returns the created record.
    @discardableResult
    func addCustomType(name: String, distance: Int) -> RunType {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = RunType(name: trimmed, distance: max(1, distance))
        customRunTypes.append(type)
        return type
    }

    /// Rename a custom type (built-ins are immutable). Retroactive across history
    /// because Run records reference by UUID — display joins on lookup.
    func renameCustomType(id: UUID, to newName: String) {
        guard let idx = customRunTypes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customRunTypes[idx].name = trimmed
    }

    /// Flip the archived flag. Archive hides the type from pickers/filters but
    /// preserves it for lookup. Built-ins cannot be archived.
    func archiveCustomType(id: UUID) {
        guard let idx = customRunTypes.firstIndex(where: { $0.id == id }) else { return }
        customRunTypes[idx].isArchived = true
    }

    func unarchiveCustomType(id: UUID) {
        guard let idx = customRunTypes.firstIndex(where: { $0.id == id }) else { return }
        customRunTypes[idx].isArchived = false
    }

    /// How many runs reference a given type. Used for the archive-warning UX.
    @MainActor
    func runsReferencing(typeId: UUID) -> Int {
        let descriptor = FetchDescriptor<Run>()
        guard let runs = try? modelContainer.mainContext.fetch(descriptor) else { return 0 }
        return runs.filter { $0.runTypeId == typeId }.count
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

    /// Seconds added to `elapsedTime` for runs stopped via the watchOS Double
    /// Tap / pinch gesture, to compensate for the pinch's reaction-time bias.
    /// `originalElapsedTime` keeps the raw, unmodified value. Default 0.0;
    /// can be negative.
    @Published var pinchOffsetSeconds: Double = 0.0 {
        didSet {
            defaults.set(pinchOffsetSeconds, forKey: pinchOffsetSecondsKey)
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
            logger.debug("SwiftData initialized at \(databaseURL.path)")
        } catch {
            logger.error("Failed to create ModelContainer: \(error). Attempting database reset...")

            // Try to delete the existing database
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("sqlite-shm"))
            try? FileManager.default.removeItem(at: databaseURL.appendingPathExtension("sqlite-wal"))

            // Try again
            do {
                self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                logger.debug("SwiftData initialized after database reset")
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

        // One-shot cleanup of duplicates produced by the pre-fix sync receiver.
        // iPhone-only because the Watch will converge via the deletion broadcasts.
        #if os(iOS)
        Task { @MainActor in
            self.performRunDedupMigrationIfNeeded()
        }
        #endif
    }

    private func initializeDefaults() {
        // Set defaults if never saved
        if defaults.object(forKey: useGPSKey) == nil {
            defaults.set(true, forKey: useGPSKey)
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
        if defaults.object(forKey: pinchOffsetSecondsKey) == nil {
            defaults.set(0.0, forKey: pinchOffsetSecondsKey)
        }
    }

    private func loadSettings() {
        let savedMode = defaults.string(forKey: startModeKey) ?? StartMode.tap.rawValue
        startMode = StartMode(rawValue: savedMode) ?? .tap
        countdownTime = defaults.integer(forKey: countdownTimeKey) > 0 ? defaults.integer(forKey: countdownTimeKey) : 5
        useGPS = defaults.bool(forKey: useGPSKey)
        trackWeather = defaults.bool(forKey: trackWeatherKey)
        trackAltitude = defaults.bool(forKey: trackAltitudeKey)
        saveTapTime = defaults.bool(forKey: saveTapTimeKey)
        saveGPSTime = defaults.bool(forKey: saveGPSTimeKey)
        pinchOffsetSeconds = defaults.double(forKey: pinchOffsetSecondsKey)
        hasSeenTutorial = defaults.bool(forKey: hasSeenTutorialKey)
        debugMode = defaults.bool(forKey: debugModeKey)
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        info += "Version: \(version) (\(build))\n"
        info += "Time: \(Date().formatted())\n\n"

        info += "--- SETTINGS ---\n"
        info += "Start Mode: \(startMode.rawValue)\n"
        info += "Countdown: \(countdownTime)s\n"
        info += "GPS: \(useGPS)\n"
        info += "Weather: \(trackWeather)\n"
        info += "Altitude: \(trackAltitude)\n"
        info += "Save Tap Time: \(saveTapTime)\n"
        info += "Save GPS Time: \(saveGPSTime)\n"
        info += "Pinch Offset (s): \(pinchOffsetSeconds)\n\n"

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
            let pending = SyncManager.shared.outstandingTransferCount
            info += "Queued userInfo: \(pending.userInfo)\n"
            info += "Queued files: \(pending.files)\n"
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

// MARK: - Run dedup migration (one-shot)
//
// Pre-fix the WatchConnectivity receiver matched incoming runs by fuzzy
// (date±1s, distance, elapsedTime±0.001s). Editing distance or elapsedTime on
// one device pushed the value past the 0.001s window on the other, so the
// receiver took the INSERT branch and created a fresh row with a new UUID.
// The orphans share the same immutable originalDistance + originalElapsedTime
// and a date within a couple of seconds, so we cluster on those, keep the
// oldest, merge non-nil fields, delete siblings, and broadcast the deletions.
#if os(iOS)
extension DataManager {
    private static let dedupMigrationKey = "didRunDedupMigrationV1"

    @MainActor
    func performRunDedupMigrationIfNeeded() {
        guard !defaults.bool(forKey: Self.dedupMigrationKey) else { return }

        let context = modelContainer.mainContext
        let allRuns: [Run]
        do {
            allRuns = try context.fetch(FetchDescriptor<Run>())
        } catch {
            logger.error("dedupMigrationV1: fetch failed: \(error)")
            return
        }

        // Defensive: regenerate any zero UUIDs. Run.init always assigns a
        // fresh UUID so this branch should never fire in practice.
        let zeroUUID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        var regeneratedIds = 0
        for run in allRuns where run.id == zeroUUID {
            run.id = UUID()
            regeneratedIds += 1
        }

        // Flat O(n²) cluster scan — n is small and this runs once.
        var processed = Set<UUID>()
        var deletedIds: [UUID] = []
        var mergedClusters = 0

        for anchor in allRuns {
            if processed.contains(anchor.id) { continue }

            let anchorOrigDistance = anchor.originalDistance ?? anchor.distance
            let anchorOrigTime = anchor.originalElapsedTime ?? anchor.elapsedTime

            let cluster = allRuns.filter { other in
                if processed.contains(other.id) { return false }
                let otherOrigDistance = other.originalDistance ?? other.distance
                let otherOrigTime = other.originalElapsedTime ?? other.elapsedTime
                return otherOrigDistance == anchorOrigDistance &&
                    abs(otherOrigTime - anchorOrigTime) < 0.001 &&
                    abs(other.date.timeIntervalSince(anchor.date)) < 2.0
            }

            for run in cluster { processed.insert(run.id) }

            guard cluster.count > 1 else { continue }

            // Canonical: oldest date wins; tiebreak by richer optional payload.
            let canonical = cluster.min { a, b in
                if a.date != b.date { return a.date < b.date }
                return Self.optionalFieldRichness(a) > Self.optionalFieldRichness(b)
            }!

            let siblings = cluster.filter { $0.id != canonical.id }
            Self.mergeSiblings(siblings, into: canonical)

            for sibling in siblings {
                deletedIds.append(sibling.id)
                context.delete(sibling)
            }
            mergedClusters += 1
        }

        if !deletedIds.isEmpty || regeneratedIds > 0 {
            do {
                try context.save()
                logger.info("dedupMigrationV1: \(mergedClusters) clusters merged, \(deletedIds.count) runs deleted, \(regeneratedIds) UUIDs regenerated")
            } catch {
                logger.error("dedupMigrationV1: save failed: \(error)")
                return
            }
            for id in deletedIds {
                SyncManager.shared.syncRunDeletion(id)
            }
        } else {
            logger.info("dedupMigrationV1: no duplicates found")
        }

        defaults.set(true, forKey: Self.dedupMigrationKey)
    }

    private static func optionalFieldRichness(_ run: Run) -> Int {
        var count = 0
        if run.latitude != nil { count += 1 }
        if run.longitude != nil { count += 1 }
        if run.altitude != nil { count += 1 }
        if run.locationName?.isEmpty == false { count += 1 }
        if run.actualDistance != nil { count += 1 }
        if run.averageSpeed != nil { count += 1 }
        if run.altitudeGain != nil { count += 1 }
        if run.startHeartRate != nil { count += 1 }
        if run.endHeartRate != nil { count += 1 }
        if run.averageHeartRate != nil { count += 1 }
        if run.maxHeartRate != nil { count += 1 }
        if run.steps != nil { count += 1 }
        if run.strideLength != nil { count += 1 }
        if run.temperature != nil { count += 1 }
        if run.feelsLike != nil { count += 1 }
        if run.humidity != nil { count += 1 }
        if run.pressure != nil { count += 1 }
        if run.windSpeed != nil { count += 1 }
        if run.windDirection != nil { count += 1 }
        if run.visibility != nil { count += 1 }
        if run.uvIndex != nil { count += 1 }
        if run.dewPoint != nil { count += 1 }
        if run.aqi != nil { count += 1 }
        if run.weatherCondition?.isEmpty == false { count += 1 }
        if !run.notes.isEmpty { count += 1 }
        if run.runTypeId != nil { count += 1 }
        return count
    }

    private static func mergeSiblings(_ siblings: [Run], into canonical: Run) {
        // Edited mutable values: if canonical still matches its original but a
        // sibling shows an edit, adopt the sibling's edit. Otherwise canonical
        // wins (it's the oldest record's current state).
        let canonicalOrigTime = canonical.originalElapsedTime ?? canonical.elapsedTime
        if abs(canonical.elapsedTime - canonicalOrigTime) <= 0.0001,
           let editedSibling = siblings.first(where: { s in
               let o = s.originalElapsedTime ?? s.elapsedTime
               return abs(s.elapsedTime - o) > 0.0001
           }) {
            canonical.elapsedTime = editedSibling.elapsedTime
        }

        let canonicalOrigDistance = canonical.originalDistance ?? canonical.distance
        if canonical.distance == canonicalOrigDistance,
           let editedSibling = siblings.first(where: { s in
               let o = s.originalDistance ?? s.distance
               return s.distance != o
           }) {
            canonical.distance = editedSibling.distance
        }

        // Backfill any nil optional fields from siblings (first non-nil wins).
        for sibling in siblings {
            if canonical.latitude == nil { canonical.latitude = sibling.latitude }
            if canonical.longitude == nil { canonical.longitude = sibling.longitude }
            if canonical.altitude == nil { canonical.altitude = sibling.altitude }
            if canonical.locationName?.isEmpty != false,
               let v = sibling.locationName, !v.isEmpty {
                canonical.locationName = v
            }
            if canonical.actualDistance == nil { canonical.actualDistance = sibling.actualDistance }
            if canonical.averageSpeed == nil { canonical.averageSpeed = sibling.averageSpeed }
            if canonical.altitudeGain == nil { canonical.altitudeGain = sibling.altitudeGain }
            if canonical.startHeartRate == nil { canonical.startHeartRate = sibling.startHeartRate }
            if canonical.endHeartRate == nil { canonical.endHeartRate = sibling.endHeartRate }
            if canonical.averageHeartRate == nil { canonical.averageHeartRate = sibling.averageHeartRate }
            if canonical.maxHeartRate == nil { canonical.maxHeartRate = sibling.maxHeartRate }
            if canonical.steps == nil { canonical.steps = sibling.steps }
            if canonical.strideLength == nil { canonical.strideLength = sibling.strideLength }
            if canonical.temperature == nil { canonical.temperature = sibling.temperature }
            if canonical.feelsLike == nil { canonical.feelsLike = sibling.feelsLike }
            if canonical.humidity == nil { canonical.humidity = sibling.humidity }
            if canonical.pressure == nil { canonical.pressure = sibling.pressure }
            if canonical.windSpeed == nil { canonical.windSpeed = sibling.windSpeed }
            if canonical.windDirection == nil { canonical.windDirection = sibling.windDirection }
            if canonical.visibility == nil { canonical.visibility = sibling.visibility }
            if canonical.uvIndex == nil { canonical.uvIndex = sibling.uvIndex }
            if canonical.dewPoint == nil { canonical.dewPoint = sibling.dewPoint }
            if canonical.aqi == nil { canonical.aqi = sibling.aqi }
            if canonical.weatherCondition?.isEmpty != false,
               let v = sibling.weatherCondition, !v.isEmpty {
                canonical.weatherCondition = v
            }
            if canonical.runTypeId == nil { canonical.runTypeId = sibling.runTypeId }
            if canonical.stopMethod == nil { canonical.stopMethod = sibling.stopMethod }
        }

        // Notes: keep the longest non-empty across canonical + siblings.
        let allNotes = ([canonical] + siblings).map { $0.notes }.filter { !$0.isEmpty }
        if let longest = allNotes.max(by: { $0.count < $1.count }),
           longest.count > canonical.notes.count {
            canonical.notes = longest
        }
    }
}
#endif
