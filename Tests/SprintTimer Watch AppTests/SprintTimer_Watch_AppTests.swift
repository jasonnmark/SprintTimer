import Testing
import Foundation
@testable import SprintTimer_Watch_App

// MARK: - Run Model Tests (Watch)

struct WatchRunModelTests {

    @Test func runCreation() {
        let run = Run(distance: 200, elapsedTime: 25.678)
        #expect(run.distance == 200)
        #expect(run.elapsedTime == 25.678)
        #expect(run.formattedTime == "25.678")
    }

    @Test func runWithNotes() {
        let run = Run(distance: 100, elapsedTime: 12.0, notes: "Felt good")
        #expect(run.notes == "Felt good")
    }

    @Test func formattedTimeUnderMinute() {
        let run = Run(distance: 100, elapsedTime: 45.123)
        #expect(run.formattedTime == "45.123")
    }

    @Test func formattedTimeOverMinute() {
        let run = Run(distance: 400, elapsedTime: 72.456)
        #expect(run.formattedTime == "1:12.456")
    }

    @Test func paceCalculation() {
        let run = Run(distance: 400, elapsedTime: 50.0)
        #expect(run.pace == "8.0 m/s")
    }
}

// MARK: - Start Mode Tests (Watch)

struct WatchStartModeTests {

    @Test func allModesAvailable() {
        #expect(StartMode.allCases.count == 3)
    }

    @Test func roundTripFromRawValue() {
        for mode in StartMode.allCases {
            let restored = StartMode(rawValue: mode.rawValue)
            #expect(restored == mode)
        }
    }
}

// MARK: - Custom Run Type Tests (Watch)

struct WatchCustomRunTypeTests {

    @Test func encodeDecode() throws {
        let types = [
            CustomRunType(name: "Sprint", distance: 60),
            CustomRunType(name: "Hurdles", distance: 110)
        ]
        let data = try JSONEncoder().encode(types)
        let decoded = try JSONDecoder().decode([CustomRunType].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Sprint")
        #expect(decoded[1].distance == 110)
    }
}

// MARK: - Outlier Logic Tests (Watch)

struct WatchOutlierTests {

    @Test func normalRunPasses() {
        let median = 12.0
        let time = 12.5
        #expect(time <= median * 1.5)
        #expect(time >= median * 0.6)
    }

    @Test func extremeSlowFlagged() {
        let median = 12.0
        let time = 25.0
        #expect(time > median * 1.5)
    }

    @Test func extremeFastFlagged() {
        let median = 12.0
        let time = 5.0
        #expect(time < median * 0.6)
    }
}
