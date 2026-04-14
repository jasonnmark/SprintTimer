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
        let backups = await fetchBackupList()
        if let latest = backups.first {
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

    func fetchBackupList() async -> [BackupInfo] {
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "backupDate", ascending: false)]

        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 20)
            return results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return BackupInfo(
                    id: record.recordID,
                    date: record["backupDate"] as? Date ?? record.creationDate ?? Date(),
                    deviceName: record["deviceName"] as? String ?? "Unknown",
                    runCount: record["runCount"] as? Int ?? 0
                )
            }
        } catch {
            logger.error("Failed to fetch backup list: \(error)")
            return []
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

        return data
    }

    private func runToDict(_ run: Run) -> [String: Any] {
        var d: [String: Any] = [
            "id": run.id.uuidString,
            "date": ISO8601DateFormatter().string(from: run.date),
            "distance": run.distance,
            "elapsedTime": run.elapsedTime,
            "notes": run.notes
        ]

        if let v = run.actualDistance { d["actualDistance"] = v }
        if let v = run.averageSpeed { d["averageSpeed"] = v }
        if let v = run.latitude { d["latitude"] = v }
        if let v = run.longitude { d["longitude"] = v }
        if let v = run.altitude { d["altitude"] = v }
        if let v = run.altitudeGain { d["altitudeGain"] = v }
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

        return d
    }

    // MARK: - Restore Application

    private func applyBackupData(_ data: [String: Any]) async throws {
        let context = DataManager.shared.modelContainer.mainContext

        // Restore runs
        if let runsArray = data["runs"] as? [[String: Any]] {
            let formatter = ISO8601DateFormatter()
            let existing = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            let existingDates = Set(existing.map { $0.date.timeIntervalSince1970 })

            var restored = 0
            for runDict in runsArray {
                guard let distance = runDict["distance"] as? Int,
                      let elapsedTime = runDict["elapsedTime"] as? Double,
                      let dateString = runDict["date"] as? String,
                      let date = formatter.date(from: dateString) else { continue }

                // Skip if run already exists (within 1 second)
                let ts = date.timeIntervalSince1970
                if existingDates.contains(where: { abs($0 - ts) < 1.0 }) { continue }

                let notes = runDict["notes"] as? String ?? ""
                let run = Run(distance: distance, elapsedTime: elapsedTime, notes: notes)
                run.date = date

                // Apply all optional fields
                if let v = runDict["actualDistance"] as? Double { run.actualDistance = v }
                if let v = runDict["averageSpeed"] as? Double { run.averageSpeed = v }
                if let v = runDict["latitude"] as? Double { run.latitude = v }
                if let v = runDict["longitude"] as? Double { run.longitude = v }
                if let v = runDict["altitude"] as? Double { run.altitude = v }
                if let v = runDict["altitudeGain"] as? Double { run.altitudeGain = v }
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
    }

    // MARK: - Retention

    private func pruneOldBackups() async {
        let backups = await fetchBackupList()
        guard backups.count > 1 else { return }

        let now = Date()
        let calendar = Calendar.current
        var toKeep = Set<CKRecord.ID>()

        // Always keep the most recent
        if let first = backups.first { toKeep.insert(first.id) }

        // Daily: keep all within 7 days
        for backup in backups {
            if now.timeIntervalSince(backup.date) <= 7 * 86400 {
                toKeep.insert(backup.id)
            }
        }

        // Weekly: keep newest per week within 3 months
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        var seenWeeks = Set<String>()
        for backup in backups {
            guard backup.date >= threeMonthsAgo else { continue }
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: backup.date)
            let weekKey = "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
            if !seenWeeks.contains(weekKey) {
                seenWeeks.insert(weekKey)
                toKeep.insert(backup.id)
            }
        }

        // Monthly: keep newest per month (forever)
        var seenMonths = Set<String>()
        for backup in backups {
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
