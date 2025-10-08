import Foundation
import WatchConnectivity
import SwiftData

class SyncManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = SyncManager()
    
    private var session: WCSession?
    @Published var isUpdatingFromSync = false
    
    // Sync message types
    private enum SyncMessageType: String {
        case settingsChanged = "settingsChanged"
        case runAdded = "runAdded"
        case runDeleted = "runDeleted"
        case requestFullSync = "requestFullSync"
        case fullSyncData = "fullSyncData"
    }
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // MARK: - Public Methods
    
    func syncSettings() {
        // Don't sync if we're currently updating from a sync
        guard !isUpdatingFromSync else { return }
        
        guard let session = session, session.isReachable else {
            print("⚠️ SyncManager: Device not reachable for settings sync")
            return
        }
        
        let dataManager = DataManager.shared
        let settings: [String: Any] = [
            "startMode": dataManager.startMode.rawValue,
            "countdownTime": dataManager.countdownTime,
            "useGPS": dataManager.useGPS,
            "useHealthKit": dataManager.useHealthKit,
            "trackWeather": dataManager.trackWeather,
            "trackAltitude": dataManager.trackAltitude,
            "saveTapTime": dataManager.saveTapTime,
            "saveGPSTime": dataManager.saveGPSTime
        ]
        
        let message: [String: Any] = [
            "type": SyncMessageType.settingsChanged.rawValue,
            "settings": settings
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("❌ SyncManager: Failed to send settings: \(error)")
        }
        
        print("✅ SyncManager: Settings sync sent")
    }
    
    func syncNewRun(_ runData: [String: Any]) {
        guard let session = session else { return }
        
        let message: [String: Any] = [
            "type": SyncMessageType.runAdded.rawValue,
            "runData": runData
        ]
        
        // Try immediate send if reachable
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("❌ SyncManager: Failed to send run: \(error)")
                // Fall back to transferUserInfo
                session.transferUserInfo(message)
            }
        } else {
            // Queue for later delivery
            session.transferUserInfo(message)
            print("📤 SyncManager: Run queued for sync")
        }
    }
    
    func requestFullSync() {
        guard let session = session else { return }
        
        let message = ["type": SyncMessageType.requestFullSync.rawValue]
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] response in
                self?.handleFullSyncResponse(response)
            }) { error in
                print("❌ SyncManager: Failed to request full sync: \(error)")
            }
        } else {
            print("⚠️ SyncManager: Device not reachable for full sync")
        }
    }
    
    private func handleFullSyncResponse(_ response: [String: Any]) {
        guard let typeString = response["type"] as? String,
              typeString == SyncMessageType.fullSyncData.rawValue,
              let data = response["data"] as? [String: Any] else {
            print("❌ SyncManager: Invalid full sync response")
            return
        }
        
        Task { @MainActor in
            await handleFullSyncData(data)
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("❌ SyncManager: Activation failed: \(error)")
        } else {
            print("✅ SyncManager: WCSession activated with state: \(activationState.rawValue)")
            
            // Request full sync on activation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.requestFullSync()
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleReceivedMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        handleReceivedMessage(message, replyHandler: replyHandler)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleReceivedMessage(userInfo)
    }
    
    // MARK: - Message Handling
    
    private func handleReceivedMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard let typeString = message["type"] as? String,
              let type = SyncMessageType(rawValue: typeString) else {
            print("❌ SyncManager: Unknown message type")
            return
        }
        
        Task { @MainActor in
            switch type {
            case .settingsChanged:
                if let settings = message["settings"] as? [String: Any] {
                    handleSettingsUpdate(settings)
                }
                
            case .runAdded:
                if let runData = message["runData"] as? [String: Any] {
                    await handleRunAdded(runData)
                }
                
            case .runDeleted:
                if let runId = message["runId"] as? String {
                    await handleRunDeleted(runId)
                }
                
            case .requestFullSync:
                let syncData = await gatherFullSyncData()
                replyHandler?(["type": SyncMessageType.fullSyncData.rawValue, "data": syncData])
                
            case .fullSyncData:
                if let data = message["data"] as? [String: Any] {
                    await handleFullSyncData(data)
                }
            }
        }
    }
    
    private func handleSettingsUpdate(_ settings: [String: Any]) {
        print("📥 SyncManager: Received settings update")
        
        // Set flag to prevent sync loops
        isUpdatingFromSync = true
        defer { isUpdatingFromSync = false }
        
        let dataManager = DataManager.shared
        var hasChanges = false
        
        // Only update settings that have actually changed
        if let startModeRaw = settings["startMode"] as? String,
           let startMode = StartMode(rawValue: startModeRaw),
           dataManager.startMode != startMode {
            dataManager.startMode = startMode
            hasChanges = true
        }
        
        if let countdownTime = settings["countdownTime"] as? Int,
           dataManager.countdownTime != countdownTime {
            dataManager.countdownTime = countdownTime
            hasChanges = true
        }
        
        if let useGPS = settings["useGPS"] as? Bool,
           dataManager.useGPS != useGPS {
            dataManager.useGPS = useGPS
            hasChanges = true
        }
        
        if let useHealthKit = settings["useHealthKit"] as? Bool,
           dataManager.useHealthKit != useHealthKit {
            dataManager.useHealthKit = useHealthKit
            hasChanges = true
        }
        
        if let trackWeather = settings["trackWeather"] as? Bool,
           dataManager.trackWeather != trackWeather {
            dataManager.trackWeather = trackWeather
            hasChanges = true
        }
        
        if let trackAltitude = settings["trackAltitude"] as? Bool,
           dataManager.trackAltitude != trackAltitude {
            dataManager.trackAltitude = trackAltitude
            hasChanges = true
        }
        
        if let saveTapTime = settings["saveTapTime"] as? Bool,
           dataManager.saveTapTime != saveTapTime {
            dataManager.saveTapTime = saveTapTime
            hasChanges = true
        }
        
        if let saveGPSTime = settings["saveGPSTime"] as? Bool,
           dataManager.saveGPSTime != saveGPSTime {
            dataManager.saveGPSTime = saveGPSTime
            hasChanges = true
        }
        
        // Only force UI update if we actually changed something
        if hasChanges {
            print("✅ SyncManager: Settings updated with changes")
        } else {
            print("ℹ️ SyncManager: No settings changes needed")
        }
    }
    
    @MainActor
    private func handleRunAdded(_ runData: [String: Any]) async {
        print("📥 SyncManager: Received new run")
        
        guard let distance = runData["distance"] as? Int,
              let elapsedTime = runData["elapsedTime"] as? Double,
              let dateTimestamp = runData["date"] as? Double else {
            print("❌ SyncManager: Invalid run data")
            return
        }
        
        let date = Date(timeIntervalSince1970: dateTimestamp)
        let notes = runData["notes"] as? String ?? ""
        
        // Check if run already exists
        let dataManager = DataManager.shared
        let context = dataManager.modelContainer.mainContext
        let descriptor = FetchDescriptor<Run>()
        
        do {
            let existingRuns = try context.fetch(descriptor)
            let runExists = existingRuns.contains { run in
                abs(run.date.timeIntervalSince(date)) < 1.0 &&
                run.distance == distance &&
                abs(run.elapsedTime - elapsedTime) < 0.001
            }
            
            if !runExists {
                let run = Run(distance: distance, elapsedTime: elapsedTime, notes: notes)
                run.date = date
                
                // Add optional data
                if let latitude = runData["latitude"] as? Double {
                    run.latitude = latitude
                }
                if let longitude = runData["longitude"] as? Double {
                    run.longitude = longitude
                }
                if let altitude = runData["altitude"] as? Double {
                    run.altitude = altitude
                }
                if let startHeartRate = runData["startHeartRate"] as? Double {
                    run.startHeartRate = startHeartRate
                }
                if let endHeartRate = runData["endHeartRate"] as? Double {
                    run.endHeartRate = endHeartRate
                }
                if let steps = runData["steps"] as? Int {
                    run.steps = steps
                }
                if let strideLength = runData["strideLength"] as? Double {
                    run.strideLength = strideLength
                }
                if let temperature = runData["temperature"] as? Double {
                    run.temperature = temperature
                }
                if let humidity = runData["humidity"] as? Double {
                    run.humidity = humidity
                }
                
                // Save without triggering another sync
                context.insert(run)
                try context.save()
                print("✅ SyncManager: Run added to database")
            } else {
                print("⚠️ SyncManager: Run already exists, skipping")
            }
        } catch {
            print("❌ SyncManager: Failed to check/add run: \(error)")
        }
    }
    
    @MainActor
    private func handleRunDeleted(_ runId: String) async {
        print("📥 SyncManager: Received run deletion for ID: \(runId)")
        
        guard let uuid = UUID(uuidString: runId) else {
            print("❌ SyncManager: Invalid UUID")
            return
        }
        
        let dataManager = DataManager.shared
        let context = dataManager.modelContainer.mainContext
        let descriptor = FetchDescriptor<Run>()
        
        do {
            let runs = try context.fetch(descriptor)
            if let runToDelete = runs.first(where: { $0.id == uuid }) {
                context.delete(runToDelete)
                try context.save()
                print("✅ SyncManager: Run deleted")
            }
        } catch {
            print("❌ SyncManager: Failed to delete run: \(error)")
        }
    }
    
    @MainActor
    private func gatherFullSyncData() async -> [String: Any] {
        print("📤 SyncManager: Gathering full sync data")
        
        var syncData: [String: Any] = [:]
        let dataManager = DataManager.shared
        
        // Add settings
        syncData["settings"] = [
            "startMode": dataManager.startMode.rawValue,
            "countdownTime": dataManager.countdownTime,
            "useGPS": dataManager.useGPS,
            "useHealthKit": dataManager.useHealthKit,
            "trackWeather": dataManager.trackWeather,
            "trackAltitude": dataManager.trackAltitude,
            "saveTapTime": dataManager.saveTapTime,
            "saveGPSTime": dataManager.saveGPSTime
        ]
        
        // Add runs
        let context = dataManager.modelContainer.mainContext
        let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        
        do {
            let runs = try context.fetch(descriptor)
            let runDataArray = runs.map { run in
                var data: [String: Any] = [
                    "id": run.id.uuidString,
                    "date": run.date.timeIntervalSince1970,
                    "distance": run.distance,
                    "elapsedTime": run.elapsedTime,
                    "notes": run.notes
                ]
                
                // Add optional fields
                if let latitude = run.latitude { data["latitude"] = latitude }
                if let longitude = run.longitude { data["longitude"] = longitude }
                if let altitude = run.altitude { data["altitude"] = altitude }
                if let startHeartRate = run.startHeartRate { data["startHeartRate"] = startHeartRate }
                if let endHeartRate = run.endHeartRate { data["endHeartRate"] = endHeartRate }
                if let steps = run.steps { data["steps"] = steps }
                if let strideLength = run.strideLength { data["strideLength"] = strideLength }
                if let temperature = run.temperature { data["temperature"] = temperature }
                if let humidity = run.humidity { data["humidity"] = humidity }
                
                return data
            }
            syncData["runs"] = runDataArray
            
            print("✅ SyncManager: Gathered \(runs.count) runs for sync")
        } catch {
            print("❌ SyncManager: Failed to gather runs: \(error)")
            syncData["runs"] = []
        }
        
        // Add daily notes
        syncData["dailyNotes"] = DailyNotesManager.shared.dailyNotes
        
        return syncData
    }
    
    @MainActor
    private func handleFullSyncData(_ data: [String: Any]) async {
        print("📥 SyncManager: Processing full sync data")
        
        // Update settings
        if let settings = data["settings"] as? [String: Any] {
            handleSettingsUpdate(settings)
        }
        
        // Update runs
        if let runsData = data["runs"] as? [[String: Any]] {
            for runData in runsData {
                await handleRunAdded(runData)
            }
        }
        
        // Update daily notes
        if let dailyNotes = data["dailyNotes"] as? [String: String] {
            DailyNotesManager.shared.dailyNotes = dailyNotes
            DailyNotesManager.shared.objectWillChange.send()
        }
        
        print("✅ SyncManager: Full sync complete")
    }
    
    // MARK: - iOS Only
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("📱 SyncManager: Session became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("📱 SyncManager: Session deactivated")
        session.activate()
    }
    #endif
}

// MARK: - Helper Extensions

extension SyncManager {
    func syncRunDeletion(_ runId: UUID) {
        guard let session = session else { return }
        
        let message: [String: Any] = [
            "type": SyncMessageType.runDeleted.rawValue,
            "runId": runId.uuidString
        ]
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("❌ SyncManager: Failed to send deletion: \(error)")
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }
    
    @MainActor
    func runToSyncData(_ run: Run) -> [String: Any] {
        var data: [String: Any] = [
            "id": run.id.uuidString,
            "date": run.date.timeIntervalSince1970,
            "distance": run.distance,
            "elapsedTime": run.elapsedTime,
            "notes": run.notes
        ]
        
        // Add optional fields
        if let latitude = run.latitude { data["latitude"] = latitude }
        if let longitude = run.longitude { data["longitude"] = longitude }
        if let altitude = run.altitude { data["altitude"] = altitude }
        if let startHeartRate = run.startHeartRate { data["startHeartRate"] = startHeartRate }
        if let endHeartRate = run.endHeartRate { data["endHeartRate"] = endHeartRate }
        if let steps = run.steps { data["steps"] = steps }
        if let strideLength = run.strideLength { data["strideLength"] = strideLength }
        if let temperature = run.temperature { data["temperature"] = temperature }
        if let humidity = run.humidity { data["humidity"] = humidity }
        
        return data
    }
}
