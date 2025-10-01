import SwiftUI
import CoreMotion
import CoreLocation
import HealthKit
import SwiftData
import Combine
#if os(watchOS)
import WatchKit
#endif

@MainActor
class SprintTimerViewModel: NSObject, ObservableObject {
    // Timer Properties
    @Published var elapsedTime: TimeInterval = 0
    @Published var isRunning = false
    @Published var isWaitingForMotion = false
    @Published var isInCountdown = false
    @Published var countdownValue = 0
    @Published var isPaused = false
    
    private var pausedTime: TimeInterval = 0
    private var countdownTimer: Timer?
    
    // Data Manager
    private let dataManager = DataManager.shared
    
    // Run Data
    @Published var selectedDistance = 100
    @Published var dailyNotes = ""
    @Published var currentRunNotes = ""
    
    // Current Run Data
    @Published var currentLocation: CLLocation?
    @Published var startHeartRate: Double?
    @Published var endHeartRate: Double?
    
    private var timer: Timer?
    private var startTime: Date?
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    
    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let milliseconds = Int((elapsedTime.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
        } else {
            return String(format: "%d.%03d", seconds, milliseconds)
        }
    }
    
    override init() {
        super.init()
        setupMotionDetection()
        requestPermissions()
        setupLocationManager()
    }
    
    func startRun() {
        // Debug logging
        print("=== Starting Run ===")
        print("Start Mode: \(dataManager.startMode.rawValue)")
        print("==================")
        
        switch dataManager.startMode {
        case .countdown:
            startCountdown()
        case .motion:
            isWaitingForMotion = true
            startMotionDetection()
        case .tap:
            beginTiming()
        }
    }
    
    private func startCountdown() {
        isInCountdown = true
        countdownValue = dataManager.countdownTime
        
        // Play initial beep
        playCountdownSound(isGo: false)
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.countdownValue -= 1
                
                if self.countdownValue == 3 {
                    // "On your mark" beep
                    self.playCountdownSound(isGo: false)
                } else if self.countdownValue == 2 {
                    // "Get set" beep
                    self.playCountdownSound(isGo: false)
                } else if self.countdownValue == 0 {
                    // "Go" beep with vibration
                    self.playCountdownSound(isGo: true)
                    self.countdownTimer?.invalidate()
                    self.isInCountdown = false
                    self.beginTiming()
                }
            }
        }
    }
    
    private func playCountdownSound(isGo: Bool) {
        #if os(watchOS)
        if isGo {
            WKInterfaceDevice.current().play(.start)
        } else {
            WKInterfaceDevice.current().play(.click)
        }
        #else
        // iOS haptic feedback
        if isGo {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        } else {
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
        #endif
    }
    
    func stopRun(modelContext: ModelContext) -> (isOutlier: Bool, reason: String) {
        print("DEBUG: Stopping run - elapsed time: \(elapsedTime)")
        guard elapsedTime > 0 else {
            print("❌ No elapsed time recorded, not saving")
            return (false, "")
        }
        
        isRunning = false
        timer?.invalidate()
        timer = nil
        
        // Check if it's an outlier before saving
        let outlierCheck = isRunOutlier(modelContext: modelContext)
        
        if !outlierCheck.isOutlier {
            // Not an outlier, save immediately
            saveRunData(modelContext: modelContext)
        }
        
        return outlierCheck
    }
    
    func saveCurrentRun(modelContext: ModelContext) {
        saveRunData(modelContext: modelContext)
    }
    
    func endRun(modelContext: ModelContext) {
        _ = stopRun(modelContext: modelContext)
        resetTimer()
    }
    
    func resetTimer() {
        elapsedTime = 0
        isRunning = false
        isWaitingForMotion = false
        isInCountdown = false
        isPaused = false
        pausedTime = 0
        countdownValue = 0
        timer?.invalidate()
        countdownTimer?.invalidate()
        timer = nil
        countdownTimer = nil
        currentRunNotes = "" // Clear run-specific notes
        if dataManager.useGPS {
            locationManager.stopUpdatingLocation()
        }
    }
    
    private func beginTiming() {
        startTime = Date()
        isRunning = true
        isWaitingForMotion = false
        isInCountdown = false
        isPaused = false
        pausedTime = 0
        
        // Start location tracking if enabled
        if dataManager.useGPS {
            locationManager.startUpdatingLocation()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func setupMotionDetection() {
        motionManager.accelerometerUpdateInterval = 0.01
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0
    }
    
    private func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let data = data else { return }
            
            Task { @MainActor in
                guard let self = self else { return }
                
                let acceleration = sqrt(pow(data.acceleration.x, 2) +
                                      pow(data.acceleration.y, 2) +
                                      pow(data.acceleration.z, 2))
                
                if acceleration > 2.5 && self.isWaitingForMotion {
                    self.motionManager.stopAccelerometerUpdates()
                    self.beginTiming()
                }
            }
        }
    }
    
    private func requestPermissions() {
        // Location permissions
        locationManager.requestWhenInUseAuthorization()
        
        // HealthKit permissions
        if HKHealthStore.isHealthDataAvailable() {
            let typesToRead: Set<HKObjectType> = [
                HKObjectType.quantityType(forIdentifier: .heartRate)!,
                HKObjectType.quantityType(forIdentifier: .stepCount)!
            ]
            
            let typesToWrite: Set<HKSampleType> = [
                HKObjectType.workoutType()
            ]
            
            healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { _, _ in
                // Authorization complete
            }
        }
    }
    
    func pauseTimer() {
        if isRunning {
            isPaused = true
            isRunning = false
            pausedTime = elapsedTime
            timer?.invalidate()
            timer = nil
        }
    }
    
    func resumeTimer() {
        if isPaused {
            isPaused = false
            isRunning = true
            startTime = Date().addingTimeInterval(-pausedTime)
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    guard let startTime = self.startTime else { return }
                    self.elapsedTime = Date().timeIntervalSince(startTime)
                }
            }
        }
    }
    
    private func saveRunData(modelContext: ModelContext) {
        print("DEBUG: Starting save - Distance: \(selectedDistance), Time: \(elapsedTime)")
        
        // Combine daily notes and run notes
        var combinedNotes = ""
        if !dailyNotes.isEmpty && !currentRunNotes.isEmpty {
            combinedNotes = "\(dailyNotes) | \(currentRunNotes)"
        } else if !dailyNotes.isEmpty {
            combinedNotes = dailyNotes
        } else {
            combinedNotes = currentRunNotes
        }
        
        // Create new run
        let run = Run(distance: self.selectedDistance, elapsedTime: elapsedTime, notes: combinedNotes)
        
        // Add location data if available
        if let location = currentLocation {
            run.latitude = location.coordinate.latitude
            run.longitude = location.coordinate.longitude
            run.altitude = location.altitude
        }
        
        // Add health data if available
        run.startHeartRate = startHeartRate
        run.endHeartRate = endHeartRate
        
        // Use DataManager to save
        dataManager.saveRun(run)
        
        // Stop location updates
        if dataManager.useGPS {
            locationManager.stopUpdatingLocation()
        }
    }
    
    // Outlier detection
    func isRunOutlier(modelContext: ModelContext) -> (isOutlier: Bool, reason: String) {
        // Get all runs and filter manually
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        
        do {
            // Fetch ALL runs, no predicate
            let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let allRuns = try modelContext.fetch(descriptor)
            
            // Filter manually in Swift
            let recentRuns = allRuns.filter { run in
                run.distance == self.selectedDistance && run.date > oneMonthAgo
            }
            
            // Need at least 3 previous runs to compare
            guard recentRuns.count >= 3 else {
                return (false, "")
            }
            
            // Calculate the median time of recent runs (better than using just the fastest)
            let sortedTimes = recentRuns.map { $0.elapsedTime }.sorted()
            let medianTime = sortedTimes[sortedTimes.count / 2]
            
            // Check if current run is too slow or too fast compared to typical performance
            if elapsedTime > medianTime * 1.5 {
                return (true, "Over 50% slower than recent typical time")
            } else if elapsedTime < medianTime * 0.6 {
                return (true, "Under 60% of recent typical time")
            }
            
            return (false, "")
            
        } catch {
            print("Error checking for outlier: \(error)")
            return (false, "")
        }
    }
}

// Location Manager Delegate
extension SprintTimerViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }
}
