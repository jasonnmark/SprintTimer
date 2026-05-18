import Foundation
import WatchConnectivity
import SwiftData
import CoreLocation
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
            "originalElapsedTime": run.originalRecordedTime,
            "originalDistance": run.originalRecordedDistance,
            "notes": run.notes
        ]
        if let typeId = run.runTypeId {
            data["runTypeId"] = typeId.uuidString
        }

        // Read optional properties explicitly (Mirror doesn't work reliably with SwiftData @Model)
        if let v = run.latitude { data["latitude"] = v }
        if let v = run.longitude { data["longitude"] = v }
        if let v = run.altitude { data["altitude"] = v }
        if let v = run.startHeartRate { data["startHeartRate"] = v }
        if let v = run.endHeartRate { data["endHeartRate"] = v }
        if let v = run.averageHeartRate { data["averageHeartRate"] = v }
        if let v = run.maxHeartRate { data["maxHeartRate"] = v }
        if let v = run.strideLength { data["strideLength"] = v }
        if let v = run.actualDistance { data["actualDistance"] = v }
        if let v = run.averageSpeed { data["averageSpeed"] = v }
        if let v = run.altitudeGain { data["altitudeGain"] = v }
        if let v = run.temperature { data["temperature"] = v }
        if let v = run.feelsLike { data["feelsLike"] = v }
        if let v = run.humidity { data["humidity"] = v }
        if let v = run.pressure { data["pressure"] = v }
        if let v = run.windSpeed { data["windSpeed"] = v }
        if let v = run.windDirection { data["windDirection"] = v }
        if let v = run.visibility { data["visibility"] = v }
        if let v = run.dewPoint { data["dewPoint"] = v }
        if let v = run.steps { data["steps"] = v }
        if let v = run.uvIndex { data["uvIndex"] = v }
        if let v = run.aqi { data["aqi"] = v }
        if let v = run.locationName { data["locationName"] = v }
        if let v = run.weatherCondition { data["weatherCondition"] = v }

        logger.info("Sync data for run \(run.id): \(data.keys.sorted().joined(separator: ", "))")

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
            "trackWeather": dataManager.trackWeather,
            "trackAltitude": dataManager.trackAltitude,
            "saveTapTime": dataManager.saveTapTime,
            "saveGPSTime": dataManager.saveGPSTime,
            "betaMode": dataManager.debugMode
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
        guard let session = session else {
            logger.error("syncNewRun: WCSession is nil")
            return
        }

        let message: [String: Any] = [
            "type": SyncMessageType.runAdded.rawValue,
            "runData": runData
        ]

        if session.isReachable {
            logger.info("syncNewRun: sending via sendMessage (reachable)")
            session.sendMessage(message, replyHandler: nil) { error in
                logger.error("Failed to send run via message: \(error), falling back to transferUserInfo")
                session.transferUserInfo(message)
            }
        } else {
            logger.info("syncNewRun: sending via transferUserInfo (not reachable)")
            session.transferUserInfo(message)
        }
    }

    func requestFullSync() {
        guard let session = session else {
            logger.error("requestFullSync: WCSession is nil")
            return
        }

        let message = ["type": SyncMessageType.requestFullSync.rawValue]

        if session.isReachable {
            logger.info("requestFullSync: requesting (reachable)")
            session.sendMessage(message, replyHandler: { [weak self] response in
                logger.info("requestFullSync: received response")
                self?.handleFullSyncResponse(response)
            }) { error in
                logger.error("Failed to request full sync: \(error)")
            }
        } else {
            logger.info("requestFullSync: skipped (not reachable)")
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
            // Skip applicationContext init when there's no counterpart to talk to — otherwise
            // WCSession logs the WCErrorCodeWatchAppNotInstalled error chain on every launch
            // for iOS-only or watchOS-only installs. The payload must be non-empty or the
            // framework logs "Application context data is nil" on the receive side; the
            // timestamp is unused, real sync flows through sendMessage / transferUserInfo.
            if shouldUpdateApplicationContext(session: session) {
                try? session.updateApplicationContext([
                    "activatedAt": Date().timeIntervalSince1970
                ])
            }

            // Request full sync on activation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.requestFullSync()
            }
        }
    }

    private func shouldUpdateApplicationContext(session: WCSession) -> Bool {
        #if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
        #else
        // watchOS doesn't expose isPaired/isCompanionAppInstalled at this level; assume the
        // counterpart is reachable via the rest of the WCSession state machine.
        return true
        #endif
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
            logger.error("handleReceivedMessage: unknown type or missing type field")
            return
        }
        logger.info("Received sync message: \(typeString)")

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
           dataManager.debugMode != betaMode {
            dataManager.debugMode = betaMode
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
            logger.error("handleRunAdded: missing required fields")
            return
        }

        let date = Date(timeIntervalSince1970: dateTimestamp)
        let notes = runData["notes"] as? String ?? ""
        let syncKeys = runData.keys.sorted().joined(separator: ", ")
        logger.info("handleRunAdded: \(distance)m, keys: \(syncKeys)")

        let dataManager = DataManager.shared
        let context = dataManager.modelContainer.mainContext
        let descriptor = FetchDescriptor<Run>()

        do {
            let existingRuns = try context.fetch(descriptor)
            let existingRun = existingRuns.first { run in
                abs(run.date.timeIntervalSince(date)) < 1.0 &&
                run.distance == distance &&
                abs(run.elapsedTime - elapsedTime) < 0.001
            }

            let runToEnrich: Run
            if let existingRun {
                // Update existing run with any new enriched fields (location, HR, weather).
                // Original recorded values are immutable — never overwrite them on update.
                logger.info("handleRunAdded: updating existing run with enriched data")
                applyOptionalFields(from: runData, to: existingRun)
                if !notes.isEmpty && existingRun.notes.isEmpty {
                    existingRun.notes = notes
                }
                try context.save()
                logger.info("handleRunAdded: existing run updated successfully")
                runToEnrich = existingRun
            } else {
                let run = Run(distance: distance, elapsedTime: elapsedTime, notes: notes)
                run.date = date
                // Honor explicit originals from the sender (preserves the true recorded values
                // when the run has already been edited on the other device). If absent, the
                // init already captured the passed values, which is a reasonable fallback.
                if let originalTime = runData["originalElapsedTime"] as? Double {
                    run.originalElapsedTime = originalTime
                }
                if let originalDist = runData["originalDistance"] as? Int {
                    run.originalDistance = originalDist
                }
                if let typeIdString = runData["runTypeId"] as? String,
                   let typeId = UUID(uuidString: typeIdString) {
                    run.runTypeId = typeId
                }
                applyOptionalFields(from: runData, to: run)

                context.insert(run)
                try context.save()
                runToEnrich = run
            }

            // iPhone: fetch weather once per location, not per run
            // Check if any same-day run at this location already has weather
            #if os(iOS)
            if runToEnrich.weatherCondition == nil,
               let lat = runToEnrich.latitude, let lon = runToEnrich.longitude,
               WeatherService.shared.hasAPIKey {
                let runDate = Calendar.current.startOfDay(for: runToEnrich.date)
                let sameDayWithWeather = existingRuns.first { run in
                    Calendar.current.startOfDay(for: run.date) == runDate &&
                    run.weatherCondition != nil &&
                    run.latitude != nil &&
                    abs(run.latitude! - lat) < 0.01 && abs(run.longitude! - lon) < 0.01
                }

                if let donor = sameDayWithWeather {
                    // Copy weather from a nearby run that already has it
                    logger.info("handleRunAdded: copying weather from nearby run")
                    runToEnrich.temperature = donor.temperature
                    runToEnrich.feelsLike = donor.feelsLike
                    runToEnrich.humidity = donor.humidity
                    runToEnrich.pressure = donor.pressure
                    runToEnrich.windSpeed = donor.windSpeed
                    runToEnrich.windDirection = donor.windDirection
                    runToEnrich.visibility = donor.visibility
                    runToEnrich.uvIndex = donor.uvIndex
                    runToEnrich.dewPoint = donor.dewPoint
                    runToEnrich.weatherCondition = donor.weatherCondition
                    runToEnrich.aqi = donor.aqi
                    try? context.save()
                } else {
                    // Fetch weather from API (first run at this location today)
                    Task {
                        let location = CLLocation(latitude: lat, longitude: lon)
                        if let weather = await WeatherService.shared.fetchWeather(for: location) {
                            await MainActor.run {
                                // Apply weather to THIS run and all same-day runs at this location
                                let allRuns = (try? context.fetch(FetchDescriptor<Run>())) ?? []
                                let sameLocationRuns = allRuns.filter { run in
                                    Calendar.current.startOfDay(for: run.date) == runDate &&
                                    run.weatherCondition == nil &&
                                    run.latitude != nil &&
                                    abs(run.latitude! - lat) < 0.01 && abs(run.longitude! - lon) < 0.01
                                }
                                for run in sameLocationRuns {
                                    run.temperature = weather.temperature
                                    run.feelsLike = weather.feelsLike
                                    run.humidity = weather.humidity
                                    run.pressure = weather.pressure
                                    run.windSpeed = weather.windSpeed
                                    run.windDirection = weather.windDirection
                                    run.visibility = weather.visibility
                                    run.uvIndex = weather.uvIndex
                                    run.dewPoint = weather.dewPoint
                                    run.weatherCondition = weather.weatherCondition
                                }
                                try? context.save()
                                logger.info("handleRunAdded: weather saved for \(sameLocationRuns.count) runs")
                            }
                        }
                        if let aqi = await WeatherService.shared.fetchAQI(for: location) {
                            await MainActor.run {
                                let allRuns = (try? context.fetch(FetchDescriptor<Run>())) ?? []
                                let sameLocationRuns = allRuns.filter { run in
                                    Calendar.current.startOfDay(for: run.date) == runDate &&
                                    run.aqi == nil &&
                                    run.latitude != nil &&
                                    abs(run.latitude! - lat) < 0.01 && abs(run.longitude! - lon) < 0.01
                                }
                                for run in sameLocationRuns {
                                    run.aqi = aqi.aqi
                                }
                                try? context.save()
                                logger.info("handleRunAdded: AQI saved for \(sameLocationRuns.count) runs")
                            }
                        }
                    }
                }
            }
            #endif
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
