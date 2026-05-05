import SwiftUI
import HealthKit

struct AppleHealthSettingsView: View {
    @State private var isAuthorized = false
    private let healthStore = HKHealthStore()

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image("AppleHealthIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        Text("Apple Health")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Text("SprintTimer saves your completed sprint sessions to the Apple Health app as workouts, so you can see them alongside your other activity. You can manage what SprintTimer reads and writes at any time in Settings \u{2192} Privacy & Security \u{2192} Health \u{2192} SprintTimer.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section {
                if isAuthorized {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected to Apple Health")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button(action: requestHealthAuthorization) {
                        Text("Connect Apple Health")
                    }
                }

                Link(destination: URL(string: "x-apple-health://")!) {
                    Text("Open Health App")
                }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkAuthorizationStatus()
        }
    }

    private func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        isAuthorized = status == .sharingAuthorized
    }

    private func requestHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { _, _ in
            DispatchQueue.main.async {
                checkAuthorizationStatus()
            }
        }
    }
}
