import SwiftUI
import SwiftData
import WatchKit

enum TimerViewMode {
    case start
    case running
    case waitingForMotion
    case countdown
    case actionMenu
}

struct TimerView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Binding var isPresented: Bool
    @State private var showingOutlierAlert = false
    @State private var outlierReason = ""
    @State private var tapHandled = false
    @State private var isInLongPressMode = false
    @State private var timerStartedButHidden = false
    @State private var menuWorkItem: DispatchWorkItem?
    @State private var pendingStopWasOutlier = false
    @State private var viewMode: TimerViewMode = .start
    @State private var savedElapsedTime: TimeInterval = 0
    @Environment(\.modelContext) private var modelContext
    
    var currentMode: TimerViewMode {
        if viewMode == .actionMenu {
            return .actionMenu
        } else if viewModel.isWaitingForMotion {
            return .waitingForMotion
        } else if viewModel.isInCountdown {
            return .countdown
        } else if viewModel.isRunning && !timerStartedButHidden {
            return .running
        } else {
            return .start
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            backgroundColor()
                .ignoresSafeArea()
            
            // Content based on mode
            switch viewMode {
            case .actionMenu:
                // Action menu as part of the view hierarchy, not a presentation
                actionMenuContent()
            default:
                // Normal timer content
                timerContent()
            }
        }
        .contentShape(Rectangle())
        .gesture(viewMode == .actionMenu ? nil : combinedGesture())
        .onDisappear {
            menuWorkItem?.cancel()
            menuWorkItem = nil
        }
        .alert("Unusual Run Time", isPresented: $showingOutlierAlert) {
            Button("Save Anyway") {
                // Save the run despite being an outlier
                viewModel.saveRunData(modelContext: modelContext)
                viewModel.resetTimer()
                viewMode = .start
                savedElapsedTime = 0
                isInLongPressMode = false
                tapHandled = false
            }
            Button("Delete Run", role: .destructive) {
                // Delete the run and reset
                viewModel.resetTimer()
                viewMode = .start
                savedElapsedTime = 0
                isInLongPressMode = false
                tapHandled = false
            }
        } message: {
            Text(outlierReason)
        }
    }
    
    @ViewBuilder
    private func timerContent() -> some View {
        VStack {
            Spacer()
            
            if currentMode == .start || timerStartedButHidden {
                // Start Button
                Text("START")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
            } else if currentMode == .waitingForMotion {
                // Waiting for Motion
                VStack(spacing: 8) {
                    Text("GET READY")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    Text("Move to start")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if currentMode == .countdown {
                // Countdown
                VStack(spacing: 8) {
                    Text("\(viewModel.countdownValue)")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                    Text("Get Ready")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            } else if currentMode == .running {
                // Timer Running
                VStack(spacing: 4) {
                    let parts = splitFormattedTime(viewModel.formattedTime)
                    
                    Text(parts.seconds)
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    
                    Text(parts.fraction)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            // Long press instruction at bottom (only on start screen)
            if currentMode == .start || timerStartedButHidden {
                Text("long press for menu")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 16)
            }
        }
    }
    
    @ViewBuilder
    private func actionMenuContent() -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 48)

            // Save Run button
            Button(action: {
                saveRun()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21))
                        .padding(.leading, 8)
                    Text("Save Run")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .background(Color.green.opacity(0.75))
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 8)

            // Save with Run Notes button
            Button(action: {
                print("DEBUG: Save with Notes button tapped")
                saveWithNotes()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 21))
                        .padding(.leading, 8)
                    Text("Save w/Notes")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .background(Color.blue.opacity(0.75))
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 8)

            // Delete Run button
            Button(action: {
                deleteRun()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 21))
                        .padding(.leading, 8)
                    Text("Delete")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .background(Color.red.opacity(0.75))
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 8)

            Spacer()
        }
    }
    
    private func saveRun() {
        viewModel.saveCurrentRun(modelContext: modelContext)
        viewModel.resetTimer()
        viewMode = .start
        savedElapsedTime = 0
        // Reset gesture state
        isInLongPressMode = false
        tapHandled = false
    }
    
    private func deleteRun() {
        viewModel.resetTimer()
        viewMode = .start
        savedElapsedTime = 0
        // Reset gesture state
        isInLongPressMode = false
        tapHandled = false
    }
    
    // CHANGED: no QuickBoard here; we ask RunnerView to open the Notes sheet
    private func saveWithNotes() {
        print("DEBUG: saveWithNotes called")
        
        // 1) Hide the in-view action menu immediately
        viewMode = .start
        isInLongPressMode = false
        tapHandled = false
        
        // 2) Do NOT reset elapsed time here; we save after notes entry
        // 3) Ask RunnerView to present the Notes sheet (which opens the watch keyboard)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowRunNotes"), object: nil)
        }
    }
    
    private func combinedGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !tapHandled {
                    tapHandled = true
                    isInLongPressMode = true
                    
                    if currentMode == .start {
                        // Start the timer
                        if viewModel.isRunning {
                            viewModel.resetTimer()
                        }
                        viewModel.resetTimer()
                        viewModel.startRun()
                        timerStartedButHidden = true
                        
                        menuWorkItem?.cancel()
                        let work = DispatchWorkItem {
                            if self.tapHandled && self.isInLongPressMode {
                                // Go directly to home instead of showing pause menu
                                viewModel.resetTimer()
                                NotificationCenter.default.post(name: Notification.Name("DismissRunnerView"), object: nil)
                                self.tapHandled = false
                                self.isInLongPressMode = false
                                self.timerStartedButHidden = false
                                self.menuWorkItem = nil
                            }
                        }
                        menuWorkItem = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
                    } else if currentMode == .running {
                        // Stop and check for outlier
                        let result = viewModel.stopRun(modelContext: modelContext)
                        pendingStopWasOutlier = result.isOutlier
                        savedElapsedTime = viewModel.elapsedTime
                        
                        if result.isOutlier {
                            // Show outlier alert instead of action menu
                            outlierReason = result.reason
                            showingOutlierAlert = true
                        } else {
                            // Normal flow - show action menu
                            viewMode = .actionMenu
                        }
                        
                        // Reset press state
                        isInLongPressMode = false
                        tapHandled = false
                    }
                }
            }
            .onEnded { _ in
                menuWorkItem?.cancel()
                menuWorkItem = nil
                isInLongPressMode = false
                tapHandled = false
                
                if timerStartedButHidden {
                    timerStartedButHidden = false
                }
            }
    }
    
    private func backgroundColor() -> Color {
        switch viewMode {
        case .actionMenu:
            return Color.black.opacity(0.9)
        default:
            if currentMode == .start || timerStartedButHidden {
                return isInLongPressMode ? Color.green.opacity(0.5) : Color.green
            } else if currentMode == .waitingForMotion || currentMode == .countdown {
                return Color.orange
            } else if currentMode == .running {
                return isInLongPressMode ? Color.blue.opacity(0.5) : Color.blue
            }
            return Color.black
        }
    }
    
    private func splitFormattedTime(_ time: String) -> (seconds: String, fraction: String) {
        if let dotIndex = time.firstIndex(of: ".") {
            let secondsPart = String(time[..<dotIndex])
            let fractionPart = String(time[dotIndex...])
            return (secondsPart, fractionPart)
        } else {
            return (time, "")
        }
    }
}
