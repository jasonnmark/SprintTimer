import SwiftUI
import WatchKit

struct TimerView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @State private var showingOutlierAlert = false
    @State private var outlierReason = ""
    @State private var showingPauseMenu = false
    @State private var pauseButtonTimer: Timer?
    @State private var isPauseButtonPressed = false
    @State private var pauseHoldProgress: CGFloat = 0
    @State private var holdStartTime: Date?
    @State private var isTrackingPauseGesture = false
    
    var body: some View {
        ZStack {
            // Main timer content
            if !viewModel.isRunning && !viewModel.isWaitingForMotion && !viewModel.isInCountdown {
                // Start Button - Full Screen
                ZStack {
                    Color.green
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Text("START")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                }
                .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                    if pressing {
                        viewModel.startRun()
                    }
                }, perform: {})
            } else if viewModel.isWaitingForMotion {
                // Waiting for Motion - Full Screen
                VStack {
                    Text("GET READY")
                        .font(.system(size: 30, weight: .bold))
                    Text("Move to start")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.orange)
            } else if viewModel.isInCountdown {
                // Countdown - Full Screen
                VStack {
                    Text("\(viewModel.countdownValue)")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                    Text("Get Ready")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.orange)
            } else if viewModel.isRunning {
                // Timer Running - Full Screen
                Button(action: {
                    // Quick tap on timer - stop and check for outlier
                    // Only allow tap if not tracking pause gesture
                    if !isTrackingPauseGesture {
                        let outlierCheck = viewModel.stopRun(modelContext: DataManager.shared.modelContainer.mainContext)
                        if outlierCheck.isOutlier {
                            outlierReason = outlierCheck.reason
                            showingOutlierAlert = true
                        }
                    }
                }) {
                    Text(viewModel.formattedTime)
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isTrackingPauseGesture)
            }
            
            // Full screen gesture overlay when tracking pause
            if isTrackingPauseGesture {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in
                                handlePausePress(false)
                            }
                    )
            }
        }
        .overlay(
            // Pause button overlay - only visible during run
            Group {
                if viewModel.isRunning || viewModel.isWaitingForMotion {
                    VStack {
                        HStack {
                            // Pause button with hold detection
                            ZStack {
                                // Background
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 50, height: 50)
                                
                                // Progress ring - only show when actively pressing
                                if isPauseButtonPressed {
                                    Circle()
                                        .trim(from: 0, to: pauseHoldProgress)
                                        .stroke(Color.white, lineWidth: 3)
                                        .frame(width: 46, height: 46)
                                        .rotationEffect(.degrees(-90))
                                }
                                
                                // Icon
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            .scaleEffect(isPauseButtonPressed ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.1), value: isPauseButtonPressed)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !isPauseButtonPressed && !isTrackingPauseGesture {
                                            isTrackingPauseGesture = true
                                            handlePausePress(true)
                                        }
                                    }
                            )
                            
                            Spacer()
                        }
                        .padding()
                        
                        Spacer()
                    }
                }
            }
        )
        .fullScreenCover(isPresented: $showingOutlierAlert) {
            OutlierAlertView(
                reason: outlierReason,
                onKeep: {
                    viewModel.saveCurrentRun(modelContext: DataManager.shared.modelContainer.mainContext)
                    viewModel.resetTimer()
                    showingOutlierAlert = false
                },
                onDelete: {
                    viewModel.resetTimer()
                    showingOutlierAlert = false
                }
            )
            .interactiveDismissDisabled(true)
        }
        .fullScreenCover(isPresented: $showingPauseMenu, onDismiss: {
            // Timer was already reset when pause was held
        }) {
            PauseMenuView(
                onHome: {
                    showingPauseMenu = false
                    NotificationCenter.default.post(name: Notification.Name("DismissRunnerView"), object: nil)
                },
                onDayNotes: {
                    showingPauseMenu = false
                    NotificationCenter.default.post(name: Notification.Name("ShowDayNotes"), object: nil)
                },
                onRunNotes: {
                    showingPauseMenu = false
                    NotificationCenter.default.post(name: Notification.Name("ShowRunNotes"), object: nil)
                }
            )
        }
    }
    
    private func handlePausePress(_ pressing: Bool) {
        if pressing {
            // Start timer immediately on any press
            if !viewModel.isRunning && !viewModel.isWaitingForMotion && !viewModel.isInCountdown {
                viewModel.startRun()
            }
            
            // If timer is running (either just started or was already running), begin hold animation
            if viewModel.isRunning {
                startPauseHoldAnimation()
            }
        } else {
            // Released
            isTrackingPauseGesture = false
            if isPauseButtonPressed {
                cancelPauseHold()
            }
        }
    }
    
    private func startPauseHoldAnimation() {
        isPauseButtonPressed = true
        holdStartTime = Date()
        pauseHoldProgress = 0
        
        // Animate progress
        withAnimation(.linear(duration: 3.0)) {
            pauseHoldProgress = 1.0
        }
        
        // Start timer for feedback
        var count = 0
        pauseButtonTimer?.invalidate()
        pauseButtonTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            count += 1
            WKInterfaceDevice.current().play(.click)
            if count >= 3 {
                timer.invalidate()
                // Call completion on the 3rd tick
                DispatchQueue.main.async {
                    if self.isPauseButtonPressed {
                        self.handlePauseHoldComplete()
                    }
                }
            }
        }
    }
    
    private func cancelPauseHold() {
        isPauseButtonPressed = false
        pauseHoldProgress = 0
        pauseButtonTimer?.invalidate()
        isTrackingPauseGesture = false
    }
    
    private func handlePauseHoldComplete() {
        pauseButtonTimer?.invalidate()
        WKInterfaceDevice.current().play(.success)
        
        if viewModel.isRunning {
            // Reset timer without saving when pause is held
            viewModel.resetTimer()
        }
        
        isPauseButtonPressed = false
        pauseHoldProgress = 0
        isTrackingPauseGesture = false
        showingPauseMenu = true
    }
}

struct OutlierAlertView: View {
    let reason: String
    let onKeep: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundColor(.yellow)
                
                Text("Unusual Time")
                    .font(.system(size: 16, weight: .bold))
                
                Text(reason)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                VStack(spacing: 10) {
                    Button(action: onKeep) {
                        Text("Keep")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    
                    Button(action: onDelete) {
                        Text("Delete")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}

struct PauseMenuView: View {
    @Environment(\.dismiss) var dismiss
    let onHome: () -> Void
    let onDayNotes: () -> Void
    let onRunNotes: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Home button - centered
            Button(action: onHome) {
                VStack(spacing: 3) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 20))
                    Text("Home")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white)
                .frame(width: 120, height: 50)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Notes section
            VStack(spacing: 6) {
                Text("Notes")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    // Run Notes button
                    Button(action: onRunNotes) {
                        VStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.system(size: 20))
                            Text("Run")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(height: 50)
                    
                    // Day Notes button
                    Button(action: onDayNotes) {
                        VStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 20))
                            Text("Day")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(height: 50)
                }
            }
            .padding(.horizontal, 10)
            
            Spacer()
        }
    }
}
