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
        NavigationView {
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
        .fullScreenCover(isPresented: Binding(
            get: { !dataManager.hasSeenTutorial },
            set: { if !$0 { dataManager.hasSeenTutorial = true } }
        )) {
            TutorialView {
                dataManager.hasSeenTutorial = true
            }
        }
    }
}

struct TutorialView: View {
    let onDismiss: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, title: String, detail: String)] = [
        ("hand.tap.fill", "Tap to Start", "Tap the green START button to begin timing your sprint."),
        ("hand.tap.fill", "Tap to Stop", "Tap anywhere on the timer screen to stop. An action menu will appear."),
        ("square.and.pencil", "Save & Notes", "Choose Save, Save with Notes, or Delete from the menu after each run."),
        ("gearshape.fill", "Start Modes", "In Settings, choose Countdown, Motion Detection, or Tap to Start.")
    ]

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: pages[page].icon)
                .font(.system(size: 32))
                .foregroundColor(.green)

            Text(pages[page].title)
                .font(.system(size: 16, weight: .bold))
                .multilineTextAlignment(.center)

            Text(pages[page].detail)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer()

            if page < pages.count - 1 {
                Button("Next") {
                    withAnimation { page += 1 }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Button("Get Started") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            if page > 0 {
                Text("\(page + 1) of \(pages.count)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding()
    }
}

