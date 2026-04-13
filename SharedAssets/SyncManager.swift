import Foundation
import WatchConnectivity
import SwiftData
import os

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "SyncManager")

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

    // Keys for optional run fields in sync dictionaries
    private static let optionalDoubleKeys = [
        "latitude", "longitude", "altitude",
        "startHeartRate", "endHeartRate", "averageHeartRate", "maxHeartRate",
        "strideLength", "actualDistance", "averageSpeed", "altitudeGain",
        "temperature", "feelsLike", "humidity", "pressure",
        "windSpeed", "windDirection", "visibility", "dewPoint"
    ]
    private static let optionalIntKeys = ["steps", "uvIndex", "aqi"]
    private static let optionalStringKeys = ["locationName", "weatherCondition"]

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Run Serialization Helpers

    @MainActor
    func runToSyncData(_ run: Run) -> [String: Any] {
        var data: [String: Any] = [
            "id": run.id.uuidString,
            "date": run.date.timeIntervalSince1970,
            "distance": run.distance,
            "elapsedTime": run.elapsedTime,
            "notes": run.notes
        ]

        // Use Mirror to read optional properties by key path
        let mirror = Mirror(reflecting: run)
        for child in mirror.children {
            guard let label = child.label else { continue }
            if Self.optionalDoubleKeys.contains(label), let value = child.value as? Double? {
                if let v = value { data[label] = v }
            } else if Self.optionalIntKeys.contains(label), let value = child.value as? Int? {
                if let v = value { data[label] = v }
            } else if Self.optionalStringKeys.contains(label), let value = child.value as? String? {
                if let v = value { data[label] = v }
            }
        }

        return data
    }

    private func applyOptionalFields(from runData: [String: Any], to run: Run) {
        // Doubles
        if let v = runData["latitude"] as? Double { run.latitude = v }
        if let v = runData["longitude"] as? Double { run.longitude = v }
        if let v = runData["altitude"] as? Double { run.altitude = v }
        if let v = runData["startHeartRate"] as? Double { run.startHeartRate = v }
        if let v = runData["endHeartRate"] as? Double { run.endHeartRate = v }
        if let v = runData["averageHeartRate"] as? Double { run.averageHeartRate = v }
        if let v = runData["maxHeartRate"] as? Double { run.maxHeartRate = v }
        if let v = runData["strideLength"] as? Double { run.strideLength = v }
        if let v = runData["actualDistance"] as? Double { run.actualDistance = v }
        if let v = runData["averageSpeed"] as? Double { run.averageSpeed = v }
        if let v = runData["altitudeGain"] as? Double { run.altitudeGain = v }
        if let v = runData["temperature"] as? Double { run.temperature = v }
        if let v = runData["feelsLike"] as? Double { run.feelsLike = v }
        if let v = runData["humidity"] as? Double { run.humidity = v }
        if let v = runData["pressure"] as? Double { run.pressure = v }
        if let v = runData["windSpeed"] as? Double { run.windSpeed = v }
        if let v = runData["windDirection"] as? Double { run.windDirection = v }
        if let v = runData["visibility"] as? Double { run.visibility = v }
        if let v = runData["dewPoint"] as? Double { run.dewPoint = v }
        // Ints
        if let v = runData["steps"] as? Int { run.steps = v }
        if let v = runData["uvIndex"] as? Int { run.uvIndex = v }
        if let v = runData["aqi"] as? Int { run.aqi = v }
        // Strings
        if let v = runData["locationName"] as? String { run.locationName = v }
        if let v = runData["weatherCondition"] as? String { run.weatherCondition = v }
    }

    // MARK: - Settings Dictionary Helper

    private func buildSettingsDict() -> [String: Any] {
        let dataManager = DataManager.shared
        var settings: [String: Any] = [
            "startMode": dataManager.startMode.rawValue,
            "countdownTime": dataManager.countdownTime,
            "useGPS": dataManager.useGPS,
            "useHealthKit": dataManager.useHealthKit,
            "trackWeather": dataManager.trackWeather,
            "trackAltitude": dataManager.trackAltitude,
            "saveTapTime": dataManager.saveTapTime,
            "saveGPSTime": dataManager.saveGPSTime,
            "betaMode": dataManager.betaMode
        ]
        if let customData = try? JSONEncoder().encode(dataManager.customRunTypes) {
            settings["customRunTypes"] = customData
        }
        return settings
    }

    // MARK: - Public Methods

    func syncSettings() {
        guard !isUpdatingFromSync else { return }

        guard let session = session, session.isReachable else {
            return
        }

        let message: [String: Any] = [
            "type": SyncMessageType.settingsChanged.rawValue,
            "settings": buildSettingsDict()
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            logger.error("Failed to send settings: \(error)")
        }
    }

    func syncNewRun(_ runData: [String: Any]) {
        guard let session = session else { return }

        let message: [String: Any] = [
            "type": SyncMessageType.runAdded.rawValue,
            "runData": runData
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                logger.error("Failed to send run: \(error)")
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    func requestFullSync() {
        guard let session = session else { return }

        let message = ["type": SyncMessageType.requestFullSync.rawValue]

        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] response in
                self?.handleFullSyncResponse(response)
            }) { error in
                logger.error("Failed to request full sync: \(error)")
            }
        }
    }

    private func handleFullSyncResponse(_ response: [String: Any]) {
        guard let typeString = response["type"] as? String,
              typeString == SyncMessageType.fullSyncData.rawValue,
              let data = response["data"] as? [String: Any] else {
            return
        }

        Task { @MainActor in
            await handleFullSyncData(data)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("Activation failed: \(error)")
        } else {
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
        // Set flag to prevent sync loops
        isUpdatingFromSync = true
        defer { isUpdatingFromSync = false }

        let dataManager = DataManager.shared

        if let startModeRaw = settings["startMode"] as? String,
           let startMode = StartMode(rawValue: startModeRaw),
           dataManager.startMode != startMode {
            dataManager.startMode = startMode
        }

        if let countdownTime = settings["countdownTime"] as? Int,
           dataManager.countdownTime != countdownTime {
            dataManager.countdownTime = countdownTime
        }

        if let useGPS = settings["useGPS"] as? Bool,
           dataManager.useGPS != useGPS {
            dataManager.useGPS = useGPS
        }

        if let useHealthKit = settings["useHealthKit"] as? Bool,
           dataManager.useHealthKit != useHealthKit {
            dataManager.useHealthKit = useHealthKit
        }

        if let trackWeather = settings["trackWeather"] as? Bool,
           dataManager.trackWeather != trackWeather {
            dataManager.trackWeather = trackWeather
        }

        if let trackAltitude = settings["trackAltitude"] as? Bool,
           dataManager.trackAltitude != trackAltitude {
            dataManager.trackAltitude = trackAltitude
        }

        if let saveTapTime = settings["saveTapTime"] as? Bool,
           dataManager.saveTapTime != saveTapTime {
            dataManager.saveTapTime = saveTapTime
        }

        if let saveGPSTime = settings["saveGPSTime"] as? Bool,
           dataManager.saveGPSTime != saveGPSTime {
            dataManager.saveGPSTime = saveGPSTime
        }

        if let betaMode = settings["betaMode"] as? Bool,
           dataManager.betaMode != betaMode {
            dataManager.betaMode = betaMode
        }

        if let customData = settings["customRunTypes"] as? Data,
           let customTypes = try? JSONDecoder().decode([CustomRunType].self, from: customData),
           dataManager.customRunTypes != customTypes {
            dataManager.customRunTypes = customTypes
        }
    }

    @MainActor
    private func handleRunAdded(_ runData: [String: Any]) async {
        guard let distance = runData["distance"] as? Int,
              let elapsedTime = runData["elapsedTime"] as? Double,
              let dateTimestamp = runData["date"] as? Double else {
            return
        }

        let date = Date(timeIntervalSince1970: dateTimestamp)
        let notes = runData["notes"] as? String ?? ""

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
                applyOptionalFields(from: runData, to: run)

                context.insert(run)
                try context.save()
            }
        } catch {
            logger.error("Failed to check/add run: \(error)")
        }
    }

    @MainActor
    private func handleRunDeleted(_ runId: String) async {
        guard let uuid = UUID(uuidString: runId) else {
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
            }
        } catch {
            logger.error("Failed to delete run: \(error)")
        }
    }

    @MainActor
    private func gatherFullSyncData() async -> [String: Any] {
        var syncData: [String: Any] = [:]

        syncData["settings"] = buildSettingsDict()

        // Add runs
        let context = DataManager.shared.modelContainer.mainContext
        let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.date, order: .reverse)])

        do {
            let runs = try context.fetch(descriptor)
            syncData["runs"] = runs.map { runToSyncData($0) }
        } catch {
            logger.error("Failed to gather runs: \(error)")
            syncData["runs"] = []
        }

        // Add daily notes
        syncData["dailyNotes"] = DailyNotesManager.shared.dailyNotes

        return syncData
    }

    @MainActor
    private func handleFullSyncData(_ data: [String: Any]) async {
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
    }

    // MARK: - iOS Only
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
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
                logger.error("Failed to send deletion: \(error)")
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }
}
