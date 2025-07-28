import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var viewModel = SprintTimerViewModel()
    @State private var selectedDistance = 100
    @State private var showingSettings = false
    @State private var showingRunner = false
    @State private var showingHistory = false
    
    let distances = [100, 200, 400]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // Distance Selector - Made 10% shorter with no label
                Picker("", selection: $selectedDistance) {
                    ForEach(distances, id: \.self) { distance in
                        Text("\(distance)m")
                            .tag(distance)
                            .font(.system(size: 28, weight: .semibold))
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 65)
                .labelsHidden()
                .padding(.top, 20)  // Increased from 8 to move down from clock
                
                // Start Run Button
                Button(action: {
                    viewModel.selectedDistance = selectedDistance
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
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .fullScreenCover(isPresented: $showingRunner) {
            RunnerView(viewModel: viewModel, isPresented: $showingRunner)
        }
    }
}
