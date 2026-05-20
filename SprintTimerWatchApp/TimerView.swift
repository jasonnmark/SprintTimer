import SwiftUI
import SwiftData
import WatchKit

enum TimerViewMode {
    case start
    case running
    case waitingForMotion
    case countdown
    case actionMenu
    case outlierAlert
}

struct TimerView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Binding var isPresented: Bool
    @State private var outlierReason = ""
    @State private var tapHandled = false
    @State private var isInLongPressMode = false
    @State private var timerStartedButHidden = false
    @State private var menuWorkItem: DispatchWorkItem?
    @State private var pendingStopWasOutlier = false
    @State private var viewMode: TimerViewMode = .start
    @State private var savedElapsedTime: TimeInterval = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    
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
                actionMenuContent()
            case .outlierAlert:
                outlierAlertContent()
            default:
                timerContent()
            }
        }
        .contentShape(Rectangle())
        .gesture(combinedGesture())
        .onDisappear {
            menuWorkItem?.cancel()
            menuWorkItem = nil
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
                if isLuminanceReduced {
                    // Always On Display: simplified view, no milliseconds
                    VStack(spacing: 8) {
                        Text("RUNNING")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        let parts = splitFormattedTime(viewModel.formattedTime)
                        Text(parts.seconds)
                            .font(.system(size: 60, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                        Button {
                            handleStopRunGesture(method: .pinch)
                        } label: {
                            Text("Tap or pinch to stop")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .handGestureShortcut(.primaryAction)
                    }
                } else {
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

                        // Double Tap hook: hands-free stop for the finish line.
                        // Screen tap continues to work on every watch — this is purely additive.
                        Button {
                            handleStopRunGesture(method: .pinch)
                        } label: {
                            Text("Tap or pinch to stop")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .handGestureShortcut(.primaryAction)
                    }
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
        VStack(spacing: 12) {
            Button(action: { saveRun() }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                    Text(viewModel.formattedTime)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.75))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .handGestureShortcut(.primaryAction)
            .padding(.horizontal, 0)

            Button(action: { saveWithNotes() }) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 32))
                    Text("Notes")
                        .font(.system(size: 22, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.75))
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)

            Button(action: { deleteRun() }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 32))
                    Text("Delete")
                        .font(.system(size: 22, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.75))
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(.top, 32)
    }
    
    @ViewBuilder
    private func outlierAlertContent() -> some View {
        VStack(spacing: 16) {
            Text("Keep?")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Button(action: {
                viewModel.saveRunData(modelContext: modelContext)
                viewModel.resetTimer()
                viewMode = .start
                savedElapsedTime = 0
                isInLongPressMode = false
                tapHandled = false
            }) {
                Text("Save")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.75))
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)

            Button(action: {
                viewModel.resetTimer()
                viewMode = .start
                savedElapsedTime = 0
                isInLongPressMode = false
                tapHandled = false
            }) {
                Text("Delete")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.35))
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(.top, 16)
    }

    private func saveRun() {
        viewModel.saveCurrentRun(modelContext: modelContext)
        viewModel.resetTimer()
        viewMode = .start
        savedElapsedTime = 0
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

    /// Shared stop-the-run flow, callable from either the screen tap gesture or
    /// the Double Tap primary-action Button. The `method` argument records which
    /// input triggered the stop so save-time can apply per-method offsets.
    private func handleStopRunGesture(method: StopMethod = .tap) {
        guard currentMode == .running else { return }

        let result = viewModel.stopRun(modelContext: modelContext, stopMethod: method)
        pendingStopWasOutlier = result.isOutlier
        savedElapsedTime = viewModel.elapsedTime

        if result.isOutlier {
            outlierReason = result.reason
            viewMode = .outlierAlert
        } else {
            viewMode = .actionMenu
        }

        isInLongPressMode = false
        tapHandled = false
    }
    
    // CHANGED: no QuickBoard here; we ask RunnerView to open the Notes sheet
    private func saveWithNotes() {
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
                guard viewMode != .actionMenu && viewMode != .outlierAlert else { return }
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
                        handleStopRunGesture()
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
        case .actionMenu, .outlierAlert:
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
