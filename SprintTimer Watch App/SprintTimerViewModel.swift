import SwiftUI
import CoreMotion
import CoreLocation
import HealthKit
import SwiftData

class SprintTimerViewModel: NSObject, ObservableObject {
    // Timer Properties
    @Published var elapsedTime: TimeInterval = 0
    @Published var isRunning = false
    @Published var isWaitingForMotion = false
    @Published var isPaused = false
    
    private var pausedTime: TimeInterval = 0
    
    // Settings
    @Published var useGPS = true
    @Published var useHealthKit = true
    @Published var trackWeather = true
    @Published var trackAltitude = true
    @Published var useMotionStart = false
    @Published var saveTapTime = true
    @Published var saveGPSTime = false
    
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
        if useMotionStart {
            isWaitingForMotion = true
            startMotionDetection()
        } else {
            beginTiming()
        }
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
        isPaused = false
        pausedTime = 0
        timer?.invalidate()
        timer = nil
        currentRunNotes = "" // Clear run-specific notes
        if useGPS {
            locationManager.stopUpdatingLocation()
        }
    }
    
    private func beginTiming() {
        startTime = Date()
        isRunning = true
        isWaitingForMotion = false
        isPaused = false
        pausedTime = 0
        
        // Start location tracking if enabled
        if useGPS {
            locationManager.startUpdatingLocation()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            self.elapsedTime = Date().timeIntervalSince(startTime)
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
            guard let self = self, let data = data else { return }
            
            let acceleration = sqrt(pow(data.acceleration.x, 2) +
                                  pow(data.acceleration.y, 2) +
                                  pow(data.acceleration.z, 2))
            
            if acceleration > 2.5 && self.isWaitingForMotion {
                self.motionManager.stopAccelerometerUpdates()
                self.beginTiming()
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
                guard let self = self, let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
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
        
        // Save to SwiftData
        modelContext.insert(run)
        print("DEBUG: Inserted run with ID: \(run.id)")
        
        do {
            try modelContext.save()
            print("✅ Run saved successfully: \(selectedDistance)m in \(formattedTime)")
            
            // Verify save
            let descriptor = FetchDescriptor<Run>()
            let allRuns = try modelContext.fetch(descriptor)
            print("DEBUG: Total runs in database after save: \(allRuns.count)")
        } catch {
            print("❌ Failed to save run: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
        
        // Stop location updates
        if useGPS {
            locationManager.stopUpdatingLocation()
        }
    }
    
    // Outlier detection - NO PREDICATE MACRO
    func isRunOutlier(modelContext: ModelContext) -> (isOutlier: Bool, reason: String) {
        // Get all runs and filter manually
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        
        do {
            // Fetch ALL runs, no predicate
            let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.elapsedTime)])
            let allRuns = try modelContext.fetch(descriptor)
            
            // Filter manually in Swift
            let recentRuns = allRuns.filter { run in
                run.distance == self.selectedDistance && run.date > oneMonthAgo
            }
            
            // Need at least one previous run to compare
            guard !recentRuns.isEmpty else {
                return (false, "")
            }
            
            // Get the personal best (fastest time)
            let personalBest = recentRuns.first!.elapsedTime
            
            // Check if current run is too slow or too fast
            if elapsedTime > personalBest * 2.0 {
                return (true, "Over 2x slower than recent best")
            } else if elapsedTime < personalBest * 0.7 {
                return (true, "Under 70% of recent best time")
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
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
