import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var viewModel = SprintTimerViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDistance = 100
    @State private var showingSettings = false
    @State private var showingRunner = false
    @State private var showingHistory = false
    
    let distances = [100, 200, 400]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                // Distance Selector
                Picker("Distance", selection: $selectedDistance) {
                    ForEach(distances, id: \.self) { distance in
                        Text("\(distance)m").tag(distance)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 45)
                
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
                
                // Bottom Buttons
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
                .padding(.top, 8)
            }
            .padding()
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
                .environment(\.modelContext, modelContext)
        }
        .fullScreenCover(isPresented: $showingRunner) {
            RunnerView(viewModel: viewModel, isPresented: $showingRunner)
        }
    }
}
