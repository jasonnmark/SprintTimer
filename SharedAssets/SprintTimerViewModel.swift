import SwiftUI
import CoreMotion
import CoreLocation
import HealthKit
import SwiftData
import Combine
@preconcurrency import AVFoundation
import os
#if os(watchOS)
import WatchKit
#endif

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "ViewModel")

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
    private lazy var motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    #if os(watchOS)
    private var extendedSession: WKExtendedRuntimeSession?
    #endif

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
        setupAudioSession()
        requestPermissions()
        setupLocationManager()
    }

    func startRun() {
        // Start location tracking early so GPS has time to get a fix before the sprint ends
        if dataManager.useGPS {
            locationManager.startUpdatingLocation()
        }

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

        // Pre-warm the audio engine so the first tone doesn't block
        prepareToneEngine()

        // Use a Date-anchored countdown so audio latency can't drift the schedule
        let countdownStart = Date()
        let totalTicks = dataManager.countdownTime

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(countdownStart)
                let ticksElapsed = Int(elapsed)  // whole seconds elapsed
                let newValue = totalTicks - ticksElapsed

                guard newValue >= 0 else { return }
                guard newValue != self.countdownValue else { return }

                self.countdownValue = newValue

                if newValue >= 1 && newValue <= 3 {
                    self.playCountdownCue(isGo: false)
                } else if newValue == 0 {
                    self.playGoBurst()
                    timer.invalidate()
                    self.isInCountdown = false
                    self.beginTiming()
                }
            }
        }
    }

    // MARK: - Tone Generator (Pole Position–style race start)

    /// Holds a strong reference to the current AVAudioPlayer so ARC doesn't deallocate mid-playback.
    private var tonePlayer: AVAudioPlayer?

    /// Pre-generated WAV data for countdown tones, built once at countdown start.
    private var countdownToneData: Data?
    private var goToneData: Data?

    /// Pre-generate tone WAV data so playback is instant during the countdown.
    private func prepareToneEngine() {
        countdownToneData = generateWAVData(frequency: 880, duration: 0.2, volume: 0.7)
        goToneData = generateWAVData(frequency: 1760, duration: 0.5, volume: 1.0)

        // Prime AVAudioPlayer by playing a silent tone — warms up the audio session
        if let silenceData = generateWAVData(frequency: 0, duration: 0.01, volume: 0) {
            tonePlayer = try? AVAudioPlayer(data: silenceData)
            tonePlayer?.volume = 0
            tonePlayer?.play()
        }
    }

    private func tearDownToneEngine() {
        tonePlayer?.stop()
        tonePlayer = nil
        countdownToneData = nil
        goToneData = nil
    }

    /// Play a countdown tick: 880 Hz, 200ms
    private func playCountdownCue(isGo: Bool) {
        if let data = countdownToneData {
            playWAVData(data, volume: 0.7)
        }

        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #else
        let feedback = UISelectionFeedbackGenerator()
        feedback.selectionChanged()
        #endif
    }

    /// Play the GO signal: 1760 Hz (octave up), 500ms, full volume + haptic burst
    private func playGoBurst() {
        if let data = goToneData {
            playWAVData(data, volume: 1.0)
        }

        #if os(watchOS)
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                WKInterfaceDevice.current().play(.start)
            }
        }
        #else
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.impactOccurred()
            }
        }
        #endif
    }

    /// Play in-memory WAV data via AVAudioPlayer (works reliably on watchOS).
    private func playWAVData(_ data: Data, volume: Float) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = volume
            player.play()
            tonePlayer = player // keep strong reference
        } catch {
            logger.error("Failed to play tone: \(error)")
        }
    }

    /// Build a 16-bit mono WAV file in memory containing a sine wave.
    private func generateWAVData(frequency: Double, duration: Double, volume: Float) -> Data? {
        let sampleRate: Int = 44100
        let numSamples = Int(Double(sampleRate) * duration)
        let bitsPerSample: Int = 16
        let byteRate = sampleRate * (bitsPerSample / 8)
        let dataSize = numSamples * (bitsPerSample / 8)
        let fileSize = 36 + dataSize

        var data = Data()
        // RIFF header
        data.append(contentsOf: [UInt8]("RIFF".utf8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: [UInt8]("WAVE".utf8))
        // fmt chunk
        data.append(contentsOf: [UInt8]("fmt ".utf8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample / 8).littleEndian) { Array($0) }) // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        // data chunk
        data.append(contentsOf: [UInt8]("data".utf8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        let fadeFrames = min(Int(Double(sampleRate) * 0.02), numSamples)
        for i in 0..<numSamples {
            var sample = sin(2.0 * .pi * frequency * Double(i) / Double(sampleRate))
            let remaining = numSamples - i
            if remaining < fadeFrames {
                sample *= Double(remaining) / Double(fadeFrames)
            }
            let clamped = max(-1.0, min(1.0, sample * Double(volume)))
            let int16 = Int16(clamped * Double(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        return data
    }

    func stopRun(modelContext: ModelContext) -> (isOutlier: Bool, reason: String) {
        guard elapsedTime > 0 else {
            return (false, "")
        }

        isRunning = false
        timer?.invalidate()
        timer = nil

        // Check if it's an outlier before saving
        let outlierCheck = isRunOutlier(modelContext: modelContext)

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
        NotificationCenter.default.post(name: Notification.Name("ShowRunNotes"), object: nil)
        #else
        NotificationCenter.default.post(name: Notification.Name("ShowRunNotes"), object: nil)
        #endif
    }

    func resetTimer() {
        elapsedTime = 0
        hasSavedCurrentRun = false
        isRunning = false
        isWaitingForMotion = false
        isInCountdown = false
        isPaused = false
        pausedTime = 0
        countdownValue = 0
        timer?.invalidate()
        countdownTimer?.invalidate()
        tearDownToneEngine()
        timer = nil
        countdownTimer = nil
        currentRunNotes = ""
        startHeartRate = nil
        endHeartRate = nil
        averageHeartRate = nil
        maxHeartRate = nil
        steps = nil
        strideLength = nil
        routeLocations = []
        motionManager.stopAccelerometerUpdates()
        if dataManager.useGPS {
            locationManager.stopUpdatingLocation()
        }
        #if os(watchOS)
        stopExtendedSession()
        #endif
    }

    private func beginTiming() {
        #if os(watchOS)
        startExtendedSession()
        #endif
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

        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error)")
        }
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0
    }

    private func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.01

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
        locationManager.requestWhenInUseAuthorization()

        guard HKHealthStore.isHealthDataAvailable(), dataManager.useHealthKit else {
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
            if let error = error {
                logger.error("HealthKit authorization error: \(error)")
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

    private var hasSavedCurrentRun = false

    func saveRunData(modelContext: ModelContext) {
        guard elapsedTime > 0, !hasSavedCurrentRun else { return }
        hasSavedCurrentRun = true

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
            var altitudeGain: Double = 0

            for i in 1..<routeLocations.count {
                totalDistance += routeLocations[i].distance(from: routeLocations[i - 1])
                let altDiff = routeLocations[i].altitude - routeLocations[i - 1].altitude
                if altDiff > 0 { altitudeGain += altDiff }
            }

            run.actualDistance = totalDistance
            if elapsedTime > 0 {
                run.averageSpeed = totalDistance / elapsedTime
            }
            run.altitudeGain = altitudeGain
        }

        // startHeartRate is fetched early in beginTiming(), so it's usually ready
        run.startHeartRate = startHeartRate

        // Use DataManager to save (before async work so the run is persisted)
        dataManager.saveRun(run)

        // Capture run ID for async work (avoids capturing non-Sendable Run across isolation boundaries)
        let runId = run.id

        // Fetch HealthKit data asynchronously and write in one batch
        if dataManager.useHealthKit, let start = startTime {
            let end = Date()
            let distance = self.selectedDistance
            // Expand time window: HR sensor may report samples slightly after the sprint ends,
            // and for very short sprints we need a wider window to catch any samples
            let hrStart = start.addingTimeInterval(-30) // 30s before sprint
            let hrEnd = end.addingTimeInterval(30) // 30s after sprint
            Task { @MainActor in
                let hr: Double? = await withCheckedContinuation { cont in
                    self.fetchLatestHeartRate { cont.resume(returning: $0) }
                }
                let (avg, max): (Double?, Double?) = await withCheckedContinuation { cont in
                    self.fetchHeartRateStats(from: hrStart, to: hrEnd) { avg, max in
                        cont.resume(returning: (avg, max))
                    }
                }
                let stepCount: Int? = await withCheckedContinuation { cont in
                    self.fetchSteps(from: start, to: end) { cont.resume(returning: $0) }
                }

                logger.info("HealthKit backfill: endHR=\(hr?.description ?? "nil"), avgHR=\(avg?.description ?? "nil"), maxHR=\(max?.description ?? "nil"), steps=\(stepCount?.description ?? "nil")")

                // Single DB write with only non-nil values
                await self.updateRun(id: runId) { run in
                    if let hr { run.endHeartRate = hr }
                    if let avg { run.averageHeartRate = avg }
                    if let max { run.maxHeartRate = max }
                    if let stepCount {
                        run.steps = stepCount
                        if stepCount > 0 {
                            run.strideLength = Double(distance) / Double(stepCount)
                        }
                    }
                }
            }
        }

        // Reverse geocode location name asynchronously
        if let location = currentLocation {
            Task {
                let name = await reverseGeocode(location: location)
                if let name, !name.isEmpty {
                    await updateRun(id: runId) { $0.locationName = name }
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
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!

        do {
            let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let allRuns = try modelContext.fetch(descriptor)

            let recentRuns = allRuns.filter { run in
                run.distance == self.selectedDistance && run.date > oneMonthAgo
            }

            // Need at least 3 previous runs to compare
            guard recentRuns.count >= 3 else {
                return (false, "")
            }

            let sortedTimes = recentRuns.map { $0.elapsedTime }.sorted()
            let medianTime = sortedTimes[sortedTimes.count / 2]

            if elapsedTime > medianTime * 1.5 {
                return (true, "Over 50% slower than recent typical time")
            } else if elapsedTime < medianTime * 0.6 {
                return (true, "Under 60% of recent typical time")
            }

            return (false, "")

        } catch {
            logger.error("Error checking for outlier: \(error)")
            return (false, "")
        }
    }
}

// MARK: - Async Run Updates
extension SprintTimerViewModel {
    /// Re-fetches a run by ID on the main context and applies a mutation, then saves.
    @MainActor
    private func updateRun(id: UUID, apply: (Run) -> Void) async {
        let context = DataManager.shared.modelContainer.mainContext
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            let runs = try context.fetch(descriptor)
            if let run = runs.first {
                apply(run)
                try context.save()
                logger.info("Updated run \(id) successfully")

                // Re-sync enriched data to the other device
                let syncData = SyncManager.shared.runToSyncData(run)
                SyncManager.shared.syncNewRun(syncData)
            } else {
                logger.error("Run \(id) not found for update")
            }
        } catch {
            logger.error("Failed to update run \(id): \(error)")
        }
    }
}

// MARK: - Reverse Geocoding
import MapKit

extension SprintTimerViewModel {
    private func reverseGeocode(location: CLLocation) async -> String? {
        logger.info("Reverse geocoding for: \(location.coordinate.latitude), \(location.coordinate.longitude)")

        guard let request = MKReverseGeocodingRequest(location: location) else {
            logger.error("MKReverseGeocodingRequest init returned nil")
            return nil
        }
        do {
            let mapItems = try await request.mapItems
            logger.info("Geocoding returned \(mapItems.count) items")
            if let item = mapItems.first {
                // Try the structured address first
                if let address = item.address {
                    let name = address.shortAddress ?? address.fullAddress
                    logger.info("Address result: short=\(address.shortAddress ?? "nil"), full=\(address.fullAddress)")
                    if !name.isEmpty {
                        return name
                    }
                }
                // Fall back to addressRepresentations if address is nil
                if let reps = item.addressRepresentations {
                    if let cityCtx = reps.cityWithContext {
                        logger.info("AddressRepresentations fallback: \(cityCtx)")
                        return cityCtx
                    } else if let city = reps.cityName {
                        return city
                    }
                }
            }
        } catch {
            logger.error("Reverse geocoding failed: \(error)")
        }
        logger.error("Reverse geocoding returned no usable result")
        return nil
    }
}

// Location Manager Delegate
extension SprintTimerViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
            if isRunning {
                routeLocations.append(contentsOf: locations)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            logger.error("Location manager failed: \(error)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            logger.info("Location authorization changed: \(status.rawValue)")
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if dataManager.useGPS {
                    manager.startUpdatingLocation()
                }
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
        let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
            if let error {
                logger.error("HR stats query error: \(error)")
            }
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
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
            if let error {
                logger.error("Steps query error: \(error)")
            }
            if let sum = statistics?.sumQuantity() {
                let steps = Int(sum.doubleValue(for: HKUnit.count()))
                completion(steps)
            } else {
                completion(nil)
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Extended Runtime Session (watchOS)
    #if os(watchOS)
    private func startExtendedSession() {
        // Invalidate any existing session
        stopExtendedSession()
        let session = WKExtendedRuntimeSession()
        session.start()
        extendedSession = session
        logger.info("Extended runtime session started")
    }

    private func stopExtendedSession() {
        if let session = extendedSession, session.state == .running {
            session.invalidate()
            logger.info("Extended runtime session stopped")
        }
        extendedSession = nil
    }
    #endif
}
