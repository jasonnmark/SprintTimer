#if os(iOS)
import Foundation
import CloudKit
import SwiftData
import UIKit
import os

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "BackupManager")

@MainActor
class BackupManager: ObservableObject {
    static let shared = BackupManager()

    private let container = CKContainer(identifier: "iCloud.com.JasonMark.SprintTimer")
    private let recordType = "Backup"
    private let defaults = UserDefaults(suiteName: "group.com.JasonMark.SprintTimer")!

    private let lastBackupKey = "backup.lastBackupDate"
    private let userClearedDataKey = "backup.userClearedData"

    @Published var lastBackupDate: Date?
    @Published var isBackingUp = false
    @Published var isRestoring = false
    @Published var backupError: String?

    private var backupTimer: Timer?

    private init() {
        lastBackupDate = defaults.object(forKey: lastBackupKey) as? Date
    }

    // MARK: - Flags

    /// Set when user intentionally clears data — prevents auto-restore
    var userClearedData: Bool {
        get { defaults.bool(forKey: userClearedDataKey) }
        set { defaults.set(newValue, forKey: userClearedDataKey) }
    }

    // MARK: - Schedule

    /// Call after saving a run. Debounces to avoid backing up on every sync message.
    func scheduleBackup() {
        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performBackup()
            }
        }
    }

    /// Call on app launch. Backs up if last backup was >24 hours ago.
    func backupIfNeeded() {
        if let last = lastBackupDate, Date().timeIntervalSince(last) < 86400 {
            logger.info("Backup skipped: last backup was \(Date().timeIntervalSince(last) / 3600, privacy: .public) hours ago")
            return
        }
        Task {
            await performBackup()
        }
    }

    /// Call on app launch when database is empty. Checks for cloud backup to restore.
    func checkForAutoRestore() async -> Bool {
        if userClearedData {
            logger.info("Auto-restore skipped: user cleared data intentionally")
            return false
        }

        // Check if there are any local runs
        let context = DataManager.shared.modelContainer.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<Run>())) ?? 0
        if count > 0 {
            return false
        }

        // Check cloud for backups
        let result = await fetchBackupList()
        if let latest = result.backups.first {
            logger.info("Found cloud backup from \(latest.date) with \(latest.runCount) runs")
            return true
        }
        return false
    }

    // MARK: - Backup

    func performBackup() async {
        guard !isBackingUp else { return }
        isBackingUp = true
        backupError = nil

        logger.info("Starting cloud backup...")

        do {
            let data = gatherBackupData()
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])

            let record = CKRecord(recordType: recordType)
            record["backupDate"] = Date()
            record["deviceName"] = deviceName()
            let runCount = (data["runs"] as? [[String: Any]])?.count ?? 0
            record["runCount"] = runCount
            record["version"] = 1

            // Store JSON as asset (more efficient for large data)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("backup_\(UUID().uuidString).json")
            try jsonData.write(to: tempURL)
            record["data"] = CKAsset(fileURL: tempURL)

            let database = container.privateCloudDatabase
            try await database.save(record)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            let now = Date()
            lastBackupDate = now
            defaults.set(now, forKey: lastBackupKey)

            // Clear the userClearedData flag since we now have a backup with current state
            userClearedData = false

            logger.info("Cloud backup complete")

            // Prune old backups
            await pruneOldBackups()

        } catch {
            logger.error("Cloud backup failed: \(error)")
            backupError = error.localizedDescription
        }

        isBackingUp = false
    }

    // MARK: - Restore

    struct BackupInfo: Identifiable {
        let id: CKRecord.ID
        let date: Date
        let deviceName: String
        let runCount: Int
    }

    /// Result of a backup-list fetch. `errorMessage` is nil when the call succeeded
    /// (even if `backups` is empty — that's "no backups yet" vs. "couldn't check").
    struct BackupListResult {
        var backups: [BackupInfo]
        var errorMessage: String?
    }

    func fetchBackupList() async -> BackupListResult {
        // Account check first — most "no backups" reports trace back to the user
        // being signed out of iCloud or the container being unavailable, and the
        // CloudKit query error in that case isn't helpful on its own.
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                break
            case .noAccount:
                return BackupListResult(backups: [], errorMessage: "You're not signed in to iCloud. Sign in via Settings → [your name] → iCloud, then try again.")
            case .restricted:
                return BackupListResult(backups: [], errorMessage: "iCloud is restricted on this device (parental controls or an MDM profile). Backups can't be read until that's lifted.")
            case .couldNotDetermine:
                return BackupListResult(backups: [], errorMessage: "Couldn't determine iCloud status. Check your network connection and that you're signed in to iCloud.")
            case .temporarilyUnavailable:
                return BackupListResult(backups: [], errorMessage: "iCloud is temporarily unavailable. Try again in a few minutes.")
            @unknown default:
                return BackupListResult(backups: [], errorMessage: "iCloud is not available (status: \(status.rawValue)).")
            }
        } catch {
            return BackupListResult(backups: [], errorMessage: "Couldn't check iCloud status: \(error.localizedDescription)")
        }

        let database = container.privateCloudDatabase
        let predicate = NSPredicate(format: "backupDate > %@", Date.distantPast as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "backupDate", ascending: false)]

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 20)
            let backups: [BackupInfo] = results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return BackupInfo(
                    id: record.recordID,
                    date: record["backupDate"] as? Date ?? record.creationDate ?? Date(),
                    deviceName: record["deviceName"] as? String ?? "Unknown",
                    runCount: record["runCount"] as? Int ?? 0
                )
            }
            return BackupListResult(backups: backups, errorMessage: nil)
        } catch let error as CKError where error.code == .invalidArguments {
            // CloudKit needs an explicit queryable index on the record type before this query
            // can run. The fix is in CloudKit Dashboard, not in code.
            logger.notice("Backup list unavailable — CloudKit returned invalidArguments. Check that backupDate is Queryable + Sortable on the Backup record type in the active environment: \(error.localizedDescription)")
            return BackupListResult(backups: [], errorMessage: "Your backups exist in iCloud but can't be listed yet — the Backup record type's schema isn't fully deployed. This is a developer-side fix in CloudKit Dashboard.")
        } catch let error as CKError where error.code == .networkUnavailable || error.code == .networkFailure {
            return BackupListResult(backups: [], errorMessage: "No network connection. Connect to Wi-Fi or cellular data and try again.")
        } catch let error as CKError where error.code == .notAuthenticated {
            return BackupListResult(backups: [], errorMessage: "iCloud isn't authenticated. Open Settings → [your name] → iCloud and make sure you're signed in.")
        } catch let error as CKError where error.code == .quotaExceeded {
            return BackupListResult(backups: [], errorMessage: "Your iCloud storage is full. Free up space in Settings → [your name] → iCloud → Manage Storage.")
        } catch {
            logger.error("Failed to fetch backup list: \(error)")
            return BackupListResult(backups: [], errorMessage: "Couldn't read backups from iCloud: \(error.localizedDescription)")
        }
    }

    func restoreFromBackup(id: CKRecord.ID) async -> Bool {
        guard !isRestoring else { return false }
        isRestoring = true
        backupError = nil

        logger.info("Restoring from backup \(id)...")

        do {
            let database = container.privateCloudDatabase
            let record = try await database.record(for: id)

            guard let asset = record["data"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                logger.error("Backup record has no data asset")
                isRestoring = false
                return false
            }

            let jsonData = try Data(contentsOf: fileURL)
            guard let data = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                logger.error("Failed to parse backup JSON")
                isRestoring = false
                return false
            }

            try await applyBackupData(data)
            userClearedData = false
            logger.info("Restore complete")
            isRestoring = false
            return true

        } catch {
            logger.error("Restore failed: \(error)")
            backupError = error.localizedDescription
            isRestoring = false
            return false
        }
    }

    // MARK: - Data Gathering

    private func gatherBackupData() -> [String: Any] {
        let context = DataManager.shared.modelContainer.mainContext
        let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.date, order: .reverse)])

        var data: [String: Any] = [
            "version": 1,
            "backupDate": ISO8601DateFormatter().string(from: Date()),
            "deviceName": deviceName()
        ]

        // Runs
        if let runs = try? context.fetch(descriptor) {
            data["runs"] = runs.map { runToDict($0) }
        } else {
            data["runs"] = []
        }

        // Daily notes
        data["dailyNotes"] = DailyNotesManager.shared.dailyNotes

        // Settings that should ride along on the backup so a restore on a new
        // device recovers the user's calibration choices.
        data["settings"] = [
            "pinchOffsetSeconds": DataManager.shared.pinchOffsetSeconds
        ]

        return data
    }

    private func runToDict(_ run: Run) -> [String: Any] {
        var d: [String: Any] = [
            "id": run.id.uuidString,
            "date": ISO8601DateFormatter().string(from: run.date),
            "distance": run.distance,
            "elapsedTime": run.elapsedTime,
            "originalElapsedTime": run.originalRecordedTime,
            "originalDistance": run.originalRecordedDistance,
            "notes": run.notes
        ]
        if let typeId = run.runTypeId {
            d["runTypeId"] = typeId.uuidString
        }

        if let v = run.actualDistance { d["actualDistance"] = v }
        if let v = run.averageSpeed { d["averageSpeed"] = v }
        if let v = run.latitude { d["latitude"] = v }
        if let v = run.longitude { d["longitude"] = v }
        if let v = run.altitude { d["altitude"] = v }
        if let v = run.altitudeGain { d["altitudeGain"] = v }
        if let v = run.gpsTimeToTarget { d["gpsTimeToTarget"] = v }
        if let v = run.locationName { d["locationName"] = v }
        if let v = run.startHeartRate { d["startHeartRate"] = v }
        if let v = run.endHeartRate { d["endHeartRate"] = v }
        if let v = run.averageHeartRate { d["averageHeartRate"] = v }
        if let v = run.maxHeartRate { d["maxHeartRate"] = v }
        if let v = run.steps { d["steps"] = v }
        if let v = run.strideLength { d["strideLength"] = v }
        if let v = run.temperature { d["temperature"] = v }
        if let v = run.feelsLike { d["feelsLike"] = v }
        if let v = run.humidity { d["humidity"] = v }
        if let v = run.pressure { d["pressure"] = v }
        if let v = run.windSpeed { d["windSpeed"] = v }
        if let v = run.windDirection { d["windDirection"] = v }
        if let v = run.visibility { d["visibility"] = v }
        if let v = run.uvIndex { d["uvIndex"] = v }
        if let v = run.dewPoint { d["dewPoint"] = v }
        if let v = run.aqi { d["aqi"] = v }
        if let v = run.weatherCondition { d["weatherCondition"] = v }
        if let v = run.stopMethod { d["stopMethod"] = v }

        return d
    }

    // MARK: - Restore Application

    private func applyBackupData(_ data: [String: Any]) async throws {
        let context = DataManager.shared.modelContainer.mainContext

        // Restore runs
        if let runsArray = data["runs"] as? [[String: Any]] {
            let formatter = ISO8601DateFormatter()
            let existing = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            let existingIDs = Set(existing.map { $0.id })

            var restored = 0
            for runDict in runsArray {
                guard let distance = runDict["distance"] as? Int,
                      let elapsedTime = runDict["elapsedTime"] as? Double,
                      let dateString = runDict["date"] as? String,
                      let date = formatter.date(from: dateString) else { continue }

                // Skip if a run with this id is already in the store. Backups
                // round-trip the original UUID so the same run never gets
                // inserted twice across restore + sync.
                if let idString = runDict["id"] as? String,
                   let id = UUID(uuidString: idString),
                   existingIDs.contains(id) {
                    continue
                }

                let notes = runDict["notes"] as? String ?? ""
                let run = Run(distance: distance, elapsedTime: elapsedTime, notes: notes)
                run.date = date
                if let idString = runDict["id"] as? String, let id = UUID(uuidString: idString) {
                    run.id = id
                }

                // Restore originally recorded values from the backup if present.
                // The init already captured the passed values; override here when the
                // backup carries the true originals from a prior recording.
                if let v = runDict["originalElapsedTime"] as? Double { run.originalElapsedTime = v }
                if let v = runDict["originalDistance"] as? Int { run.originalDistance = v }
                if let s = runDict["runTypeId"] as? String, let id = UUID(uuidString: s) {
                    run.runTypeId = id
                }

                // Apply all optional fields
                if let v = runDict["actualDistance"] as? Double { run.actualDistance = v }
                if let v = runDict["averageSpeed"] as? Double { run.averageSpeed = v }
                if let v = runDict["latitude"] as? Double { run.latitude = v }
                if let v = runDict["longitude"] as? Double { run.longitude = v }
                if let v = runDict["altitude"] as? Double { run.altitude = v }
                if let v = runDict["altitudeGain"] as? Double { run.altitudeGain = v }
                if let v = runDict["gpsTimeToTarget"] as? Double { run.gpsTimeToTarget = v }
                if let v = runDict["locationName"] as? String { run.locationName = v }
                if let v = runDict["startHeartRate"] as? Double { run.startHeartRate = v }
                if let v = runDict["endHeartRate"] as? Double { run.endHeartRate = v }
                if let v = runDict["averageHeartRate"] as? Double { run.averageHeartRate = v }
                if let v = runDict["maxHeartRate"] as? Double { run.maxHeartRate = v }
                if let v = runDict["steps"] as? Int { run.steps = v }
                if let v = runDict["strideLength"] as? Double { run.strideLength = v }
                if let v = runDict["temperature"] as? Double { run.temperature = v }
                if let v = runDict["feelsLike"] as? Double { run.feelsLike = v }
                if let v = runDict["humidity"] as? Double { run.humidity = v }
                if let v = runDict["pressure"] as? Double { run.pressure = v }
                if let v = runDict["windSpeed"] as? Double { run.windSpeed = v }
                if let v = runDict["windDirection"] as? Double { run.windDirection = v }
                if let v = runDict["visibility"] as? Double { run.visibility = v }
                if let v = runDict["uvIndex"] as? Int { run.uvIndex = v }
                if let v = runDict["dewPoint"] as? Double { run.dewPoint = v }
                if let v = runDict["aqi"] as? Int { run.aqi = v }
                if let v = runDict["weatherCondition"] as? String { run.weatherCondition = v }
                if let v = runDict["stopMethod"] as? String { run.stopMethod = v }

                context.insert(run)
                restored += 1
            }

            try context.save()
            logger.info("Restored \(restored) runs from backup")
        }

        // Restore daily notes
        if let dailyNotes = data["dailyNotes"] as? [String: String] {
            for (dateKey, note) in dailyNotes {
                DailyNotesManager.shared.dailyNotes[dateKey] = note
            }
            DailyNotesManager.shared.objectWillChange.send()
            logger.info("Restored \(dailyNotes.count) daily notes from backup")
        }

        // Restore settings carried in the backup. Only known keys are
        // recognized; unknown keys are ignored so future versions stay
        // forward-compatible.
        if let settings = data["settings"] as? [String: Any] {
            if let v = settings["pinchOffsetSeconds"] as? Double {
                DataManager.shared.pinchOffsetSeconds = v
            }
        }
    }

    // MARK: - Retention

    private func pruneOldBackups() async {
        let backups = await fetchBackupList().backups
        guard backups.count > 1 else { return }

        let now = Date()
        let calendar = Calendar.current
        var toKeep = Set<CKRecord.ID>()

        // Always keep the most recent
        if let first = backups.first { toKeep.insert(first.id) }

        // Daily: one per day, kept for a week
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        var seenDays = Set<String>()
        for backup in backups {
            guard backup.date >= oneWeekAgo else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: backup.date)
            let dayKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
            if !seenDays.contains(dayKey) {
                seenDays.insert(dayKey)
                toKeep.insert(backup.id)
            }
        }

        // Weekly: one per week, kept for a month
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        var seenWeeks = Set<String>()
        for backup in backups {
            guard backup.date >= oneMonthAgo else { continue }
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: backup.date)
            let weekKey = "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
            if !seenWeeks.contains(weekKey) {
                seenWeeks.insert(weekKey)
                toKeep.insert(backup.id)
            }
        }

        // Monthly: one per month, kept for three months
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        var seenMonths = Set<String>()
        for backup in backups {
            guard backup.date >= threeMonthsAgo else { continue }
            let components = calendar.dateComponents([.year, .month], from: backup.date)
            let monthKey = "\(components.year ?? 0)-\(components.month ?? 0)"
            if !seenMonths.contains(monthKey) {
                seenMonths.insert(monthKey)
                toKeep.insert(backup.id)
            }
        }

        // Delete everything not in toKeep
        let toDelete = backups.filter { !toKeep.contains($0.id) }
        if toDelete.isEmpty { return }

        logger.info("Pruning \(toDelete.count) old backups (keeping \(toKeep.count))")

        let database = container.privateCloudDatabase
        for backup in toDelete {
            do {
                try await database.deleteRecord(withID: backup.id)
            } catch {
                logger.error("Failed to delete old backup: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func deviceName() -> String {
        return UIDevice.current.name
    }
}
#endif
