#if os(iOS)
import Foundation
import SwiftUI
import CoreLocation
import os

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "DailyLocation")

/// One captured location for a calendar day. `name` may be nil if reverse
/// geocoding failed — coordinates are still useful as a fallback signal.
struct DayLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var name: String?
    var capturedAt: Date
}

/// Persistent store for per-day captured locations on the iPhone. Mirrors
/// `DailyNotesManager`'s shape and shares the same app-group UserDefaults so
/// notes and locations sit next to each other on disk.
@MainActor
final class DailyLocationManager: ObservableObject {
    static let shared = DailyLocationManager()

    private let defaults: UserDefaults
    private let appGroupID = "group.com.JasonMark.SprintTimer"
    private let storageKey = "dailyLocations"

    @Published private(set) var locations: [String: DayLocation] = [:]

    private init() {
        guard let groupDefaults = UserDefaults(suiteName: appGroupID) else {
            fatalError("Failed to create UserDefaults for app group: \(appGroupID)")
        }
        self.defaults = groupDefaults
        loadLocations()
    }

    private func loadLocations() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            locations = try JSONDecoder().decode([String: DayLocation].self, from: data)
        } catch {
            logger.error("Failed to decode dailyLocations: \(error)")
        }
    }

    private func saveLocations() {
        do {
            let data = try JSONEncoder().encode(locations)
            defaults.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to encode dailyLocations: \(error)")
        }
    }

    func getLocation(for date: Date) -> DayLocation? {
        locations[dateKey(for: date)]
    }

    func setLocation(_ location: DayLocation, for date: Date) {
        locations[dateKey(for: date)] = location
        saveLocations()
        objectWillChange.send()
    }

    func clearLocation(for date: Date) {
        locations.removeValue(forKey: dateKey(for: date))
        saveLocations()
        objectWillChange.send()
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }
}

/// One-shot location request for the iPhone day-note flow. Requests
/// when-in-use permission if needed, returns the first reasonably accurate
/// fix or nil on timeout / denial.
@MainActor
final class OneShotLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation(timeout: TimeInterval = 15) async -> CLLocation? {
        // If a request is already in flight, fail fast — callers can retry.
        if continuation != nil { return nil }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait briefly for the permission decision before issuing the
            // request — the delegate callback handles the in-flight case.
        } else if status == .denied || status == .restricted {
            return nil
        }

        return await withCheckedContinuation { [weak self] cont in
            guard let self else {
                cont.resume(returning: nil)
                return
            }
            self.continuation = cont
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resolve(with: nil)
            }
            self.manager.requestLocation()
        }
    }

    private func resolve(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last
        Task { @MainActor in
            self.resolve(with: fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            logger.error("OneShotLocationFetcher failed: \(error)")
            self.resolve(with: nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // If the user just granted access and a request is pending, fire it.
            if (status == .authorizedWhenInUse || status == .authorizedAlways),
               self.continuation != nil {
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.resolve(with: nil)
            }
        }
    }
}
#endif
