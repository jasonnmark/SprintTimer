#if os(iOS)
import Foundation
import SwiftData
import CoreLocation
import Network
import os

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "LocationBackfill")

/// One-shot cleanup pass that re-resolves `locationName` for runs that
/// were saved without one (typically Watch runs completed while offline).
/// Runs at iPhone app launch; throttled to at most once per 24h unless
/// `force: true` is passed.
@MainActor
final class LocationBackfillService {
    static let shared = LocationBackfillService()

    private static let lastRunKey = "locationBackfillLastRun"
    private static let throttleInterval: TimeInterval = 60 * 60 * 24 // 24h
    private static let perPassCap = 30
    private static let perRequestDelayNanos: UInt64 = 1_000_000_000 // 1s

    private var isRunning = false

    private init() {}

    func runIfNeeded(force: Bool = false) async {
        if isRunning {
            logger.info("Backfill already in progress, skipping")
            return
        }
        let defaults = UserDefaults(suiteName: "group.com.JasonMark.SprintTimer")
        if !force,
           let last = defaults?.object(forKey: Self.lastRunKey) as? Date,
           Date().timeIntervalSince(last) < Self.throttleInterval {
            logger.info("Backfill skipped (ran <24h ago)")
            return
        }

        isRunning = true
        defer { isRunning = false }

        guard await isNetworkReachable() else {
            logger.info("Backfill skipped: no network")
            return
        }

        let context = DataManager.shared.modelContainer.mainContext
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { run in
                run.locationName == nil && run.latitude != nil && run.longitude != nil
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let candidates: [Run]
        do {
            candidates = try context.fetch(descriptor)
        } catch {
            logger.error("Backfill fetch failed: \(error)")
            return
        }

        if candidates.isEmpty {
            logger.info("Backfill: no candidates")
            defaults?.set(Date(), forKey: Self.lastRunKey)
            return
        }

        let batch = candidates.prefix(Self.perPassCap)
        logger.info("Backfill: processing \(batch.count) of \(candidates.count) candidates")

        var resolvedCount = 0
        for (index, run) in batch.enumerated() {
            guard let lat = run.latitude, let lon = run.longitude else { continue }
            let location = CLLocation(latitude: lat, longitude: lon)

            if let name = await LocationResolver.reverseGeocode(location: location),
               !name.isEmpty {
                run.locationName = name
                resolvedCount += 1
                do {
                    try context.save()
                    let syncData = SyncManager.shared.runToSyncData(run)
                    SyncManager.shared.syncNewRun(syncData)
                } catch {
                    logger.error("Backfill save failed for run \(run.id): \(error)")
                }
            }

            // Stay well under MapKit's geocoder throttle.
            if index < batch.count - 1 {
                try? await Task.sleep(nanoseconds: Self.perRequestDelayNanos)
            }
        }

        logger.info("Backfill complete: resolved \(resolvedCount) of \(batch.count)")
        defaults?.set(Date(), forKey: Self.lastRunKey)
    }

    private func isNetworkReachable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "LocationBackfill.NWPathMonitor")
            let state = ReachabilityCallState(continuation: continuation, monitor: monitor)
            monitor.pathUpdateHandler = { path in
                state.resolve(reachable: path.status == .satisfied)
            }
            monitor.start(queue: queue)
            // Safety: resolve as unreachable after 2s in case no update arrives.
            queue.asyncAfter(deadline: .now() + 2.0) {
                state.resolve(reachable: false)
            }
        }
    }
}

/// Serializes the single-shot resolve of an NWPathMonitor continuation so the
/// path callback and the timeout closure can't both fire.
private final class ReachabilityCallState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<Bool, Never>
    private let monitor: NWPathMonitor

    init(continuation: CheckedContinuation<Bool, Never>, monitor: NWPathMonitor) {
        self.continuation = continuation
        self.monitor = monitor
    }

    func resolve(reachable: Bool) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        monitor.cancel()
        continuation.resume(returning: reachable)
    }
}
#endif
