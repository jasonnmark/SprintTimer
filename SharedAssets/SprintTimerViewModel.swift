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
    @Published var currentEditingRun: Run? // For editing existing run notes from history
    @Published var currentEditingDate: Date? // For editing day notes for specific date from history
    
    // Current Run Data
    @Published var currentLocation: CLLocation?
    @Published var startHeartRate: Double?
    @Published var endHeartRate: Double?
    @Published var averageHeartRate: Double?
    @Published var maxHeartRate: Double?
    @Published var steps: Int?
    @Published var strideLength: Double?

    // GPS route tracking for distance/speed/altitude gain
    private var routeLocations: [CLLocation] = []
    
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
            // Not an outlier, but don't save yet - let the UI handle saving
            // This prevents double-saving
        }
        
        // Fetch HealthKit metrics at stop
        if dataManager.useHealthKit, let start = startTime {
            let end = Date()
            // Capture ending heart rate (latest sample)
            fetchLatestHeartRate { [weak self] hr in
                Task { @MainActor in
                    self?.endHeartRate = hr
                }
            }
            // Capture average and max heart rate during the run
            fetchHeartRateStats(from: start, to: end) { [weak self] avg, max in
                Task { @MainActor in
                    self?.averageHeartRate = avg
                    self?.maxHeartRate = max
                }
            }
            // Capture steps over the interval and compute stride length
            fetchSteps(from: start, to: end) { [weak self] count in
                Task { @MainActor in
                    self?.steps = count
                    if let steps = count, steps > 0 {
                        self?.strideLength = Double(self?.selectedDistance ?? 0) / Double(steps)
                    } else {
                        self?.strideLength = nil
                    }
                }
            }
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
    
    func saveWithNotes(modelContext: ModelContext, completion: @escaping () -> Void = {}) {
        #if os(watchOS)
        // IMPORTANT: Don’t present QuickBoard here (we may still be inside a confirmationDialog).
        // Ask RunnerView to present it after the dialog disappears.
        NotificationCenter.default.post(name: Notification.Name("ShowRunNotes"), object: nil)
        #else
        // iPhone flow (unchanged): use your existing route to show a notes UI.
        NotificationCenter.default.post(name: Notification.Name("ShowRunNotes"), object: nil)
        #endif
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
        startHeartRate = nil
        endHeartRate = nil
        averageHeartRate = nil
        maxHeartRate = nil
        steps = nil
        strideLength = nil
        routeLocations = []
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
        
        if dataManager.useHealthKit {
            fetchLatestHeartRate { [weak self] hr in
                Task { @MainActor in
                    self?.startHeartRate = hr
                }
            }
        }
        
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
        
        // HealthKit permissions - only if available and user has enabled it
        guard HKHealthStore.isHealthDataAvailable(), dataManager.useHealthKit else {
            print("HealthKit not available or not enabled in settings")
            return
        }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]
        
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]
        
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ HealthKit authorization error: \(error)")
                } else if success {
                    print("✅ HealthKit authorization granted")
                } else {
                    print("⚠️ HealthKit authorization denied")
                }
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
    
    func saveRunData(modelContext: ModelContext) {
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

        // Calculate GPS distance, speed, and altitude gain from route
        if routeLocations.count >= 2 {
            var totalDistance: CLLocationDistance = 0
            var minAltitude = routeLocations[0].altitude
            var maxAltitude = routeLocations[0].altitude
            var altitudeGain: Double = 0

            for i in 1..<routeLocations.count {
                totalDistance += routeLocations[i].distance(from: routeLocations[i - 1])
                let alt = routeLocations[i].altitude
                if alt > maxAltitude { maxAltitude = alt }
                if alt < minAltitude { minAltitude = alt }
                let altDiff = alt - routeLocations[i - 1].altitude
                if altDiff > 0 { altitudeGain += altDiff }
            }

            run.actualDistance = totalDistance
            if elapsedTime > 0 {
                run.averageSpeed = totalDistance / elapsedTime
            }
            run.altitudeGain = altitudeGain
        }
        
        // Add health data if available
        run.startHeartRate = startHeartRate
        run.endHeartRate = endHeartRate
        run.averageHeartRate = averageHeartRate
        run.maxHeartRate = maxHeartRate
        run.steps = steps
        run.strideLength = strideLength
        
        // Reverse geocode location name
        if let location = currentLocation {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    let parts = [placemark.locality, placemark.administrativeArea].compactMap { $0 }
                    let name = parts.joined(separator: ", ")
                    if !name.isEmpty {
                        Task { @MainActor in
                            run.locationName = name
                            try? DataManager.shared.modelContainer.mainContext.save()
                        }
                    }
                }
            }
        }

        // Use DataManager to save
        dataManager.saveRun(run)

        // Fetch weather data asynchronously if enabled and location available
        if dataManager.trackWeather, let location = currentLocation {
            Task {
                async let weatherResult = WeatherService.shared.fetchWeather(for: location)
                async let aqiResult = WeatherService.shared.fetchAQI(for: location)

                if let weather = await weatherResult {
                    await MainActor.run {
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
                        try? DataManager.shared.modelContainer.mainContext.save()
                    }
                }
                if let aqi = await aqiResult {
                    await MainActor.run {
                        run.aqi = aqi.aqi
                        try? DataManager.shared.modelContainer.mainContext.save()
                    }
                }
            }
        }

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
            // Collect route points while running for distance/speed/altitude calculations
            if isRunning {
                routeLocations.append(contentsOf: locations)
            }
        }
    }
}

// MARK: - HealthKit Queries
extension SprintTimerViewModel {
    private func fetchLatestHeartRate(completion: @escaping (Double?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(nil)
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            if let quantitySample = samples?.first as? HKQuantitySample {
                let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let bpm = quantitySample.quantity.doubleValue(for: unit)
                completion(bpm)
            } else {
                completion(nil)
            }
        }
        healthStore.execute(query)
    }

    private func fetchHeartRateStats(from start: Date, to end: Date, completion: @escaping (Double?, Double?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(nil, nil)
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            guard let hrSamples = samples as? [HKQuantitySample], !hrSamples.isEmpty else {
                completion(nil, nil)
                return
            }
            let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            let bpmValues = hrSamples.map { $0.quantity.doubleValue(for: unit) }
            let avg = bpmValues.reduce(0, +) / Double(bpmValues.count)
            let max = bpmValues.max()
            completion(avg, max)
        }
        healthStore.execute(query)
    }

    private func fetchSteps(from start: Date, to end: Date, completion: @escaping (Int?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            completion(nil)
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
            if let sum = statistics?.sumQuantity() {
                let steps = Int(sum.doubleValue(for: HKUnit.count()))
                completion(steps)
            } else {
                completion(nil)
            }
        }
        healthStore.execute(query)
    }
}
