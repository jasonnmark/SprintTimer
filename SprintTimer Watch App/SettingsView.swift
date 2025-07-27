import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Toggle("Use GPS Verification", isOn: $viewModel.useGPS)
                Toggle("Connect to HealthKit", isOn: $viewModel.useHealthKit)
                Toggle("Track Weather Data", isOn: $viewModel.trackWeather)
                Toggle("Track Altitude", isOn: $viewModel.trackAltitude)
                
                Divider()
                
                Text("Start Mode")
                    .font(.headline)
                Toggle("Start with Motion", isOn: $viewModel.useMotionStart)
                    .padding(.bottom, 5)
                Text(viewModel.useMotionStart ? "Timer starts when motion detected" : "Tap button to start timer")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Divider()
                
                Text("Save Options")
                    .font(.headline)
                Toggle("Save Tap Time", isOn: $viewModel.saveTapTime)
                Toggle("Save GPS Time", isOn: $viewModel.saveGPSTime)
            }
            .padding()
        }
        .navigationTitle("Settings")
    }
}
