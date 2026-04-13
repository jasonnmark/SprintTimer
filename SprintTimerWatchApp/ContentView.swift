import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var viewModel = SprintTimerViewModel()
    @StateObject private var dataManager = DataManager.shared
    @State private var selectedDistanceIndex = 0
    @State private var showingSettings = false
    @State private var showingRunner = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Distance Selector - supports built-in + custom types
                Picker("", selection: $selectedDistanceIndex) {
                    ForEach(Array(dataManager.allDistances.enumerated()), id: \.offset) { index, item in
                        Text(item.label)
                            .tag(index)
                            .font(.system(size: 28, weight: .semibold))
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 65)
                .labelsHidden()
                .padding(.top, 20)
                
                // Start Run Button
                Button(action: {
                    let distances = dataManager.allDistances
                    let safeIndex = min(selectedDistanceIndex, distances.count - 1)
                    viewModel.selectedDistance = distances[max(0, safeIndex)].distance
                    showingRunner = true
                }) {
                    Text("START")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .background(Color.green)
                .cornerRadius(15)
                
                // Bottom Buttons - Fixed with icon on top
                HStack(spacing: 30) {
                    Button(action: {
                        showingHistory = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 22))
                            Text("History")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showingSettings = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "gear")
                                .font(.system(size: 22))
                            Text("Settings")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 4)  // Reduced from 8 to balance spacing
            }
            .padding()
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingHistory) {
            HistoryView()
        }
        .fullScreenCover(isPresented: $showingRunner) {
            RunnerView(viewModel: viewModel, isPresented: $showingRunner)
        }
    }
}

