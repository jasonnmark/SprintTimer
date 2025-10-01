/// TimerView interaction goals:
/// 0) Downpress on start screen:
///    - Dark green start screen
///    - Timer starts instantly but is not displayed
/// 1) Release before 3 seconds on start screen:
///    - Go to timer screen showing however long has passed
/// 2) At 3 second mark (while still holding on start screen):
///    - Switch to home menu
///    - Timer reset

import SwiftUI
import SwiftData
import WatchKit

struct TimerView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @State private var showingOutlierAlert = false
    @State private var outlierReason = ""
    @State private var showingPauseMenu = false
    @State private var tapHandled = false
    @State private var isInLongPressMode = false
    @State private var timerStartedButHidden = false
    @State private var menuWorkItem: DispatchWorkItem?
    @State private var showingRunActionMenu = false
    @State private var pendingStopWasOutlier = false
    @State private var lockRunningAppearance = false
    
    var body: some View {
        ZStack {
            // Background
            backgroundColor()
                .ignoresSafeArea()
            
            // Main content - centered on screen
            VStack {
                Spacer()
                
                if ((!viewModel.isRunning && !viewModel.isWaitingForMotion && !viewModel.isInCountdown) || timerStartedButHidden) && !lockRunningAppearance {
                    // Start Button - Centered on screen (show even when timer started but hidden)
                    Text("START")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                } else if viewModel.isWaitingForMotion {
                    // Waiting for Motion - Centered on screen
                    VStack(spacing: 8) {
                        Text("GET READY")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text("Move to start")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else if viewModel.isInCountdown {
                    // Countdown - Centered on screen
                    VStack(spacing: 8) {
                        Text("\(viewModel.countdownValue)")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundColor(.white)
                        Text("Get Ready")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                } else if ((viewModel.isRunning && !timerStartedButHidden) || lockRunningAppearance) {
                    // Timer Running - Centered on screen (only show when not hidden)
                    VStack(spacing: 4) {
                        // Split formattedTime into integer and fractional parts
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
            }
            
            // "Long press for menu" text - Only show when not running
            if !viewModel.isRunning && !lockRunningAppearance {
                VStack {
                    Spacer()
                    Text("long press for menu")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 8)
                }
            }
        }
        .contentShape(Rectangle()) // Makes entire ZStack tappable for gestures
        .gesture(combinedGesture())
        .onDisappear { menuWorkItem?.cancel(); menuWorkItem = nil }
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
        .overlay(
            Group {
                if showingRunActionMenu {
                    RunningActionMenuView(
                        onSave: {
                            viewModel.saveCurrentRun(modelContext: DataManager.shared.modelContainer.mainContext)
                            viewModel.resetTimer()
                            // Clear local UI/gesture state
                            showingRunActionMenu = false
                            lockRunningAppearance = false
                            tapHandled = false
                            isInLongPressMode = false
                            timerStartedButHidden = false
                            menuWorkItem?.cancel(); menuWorkItem = nil
                        },
                        onDelete: {
                            viewModel.resetTimer()
                            showingRunActionMenu = false
                            lockRunningAppearance = false
                            tapHandled = false
                            isInLongPressMode = false
                            timerStartedButHidden = false
                            menuWorkItem?.cancel(); menuWorkItem = nil
                        },
                        onSaveWithNotes: {
                            // Do NOT save or reset yet — let the notes screen save the run once submitted
                            // Dismiss the action menu and clear any running UI lock/state
                            lockRunningAppearance = false
                            showingRunActionMenu = false
                            tapHandled = false
                            isInLongPressMode = false
                            timerStartedButHidden = false
                            menuWorkItem?.cancel(); menuWorkItem = nil
                            // Present the notes editor directly; it will save the run on submission
                            NotificationCenter.default.post(name: Notification.Name("ShowRunNotes"), object: nil)
                        }
                    )
                    .ignoresSafeArea()
                }
            }
        )
    }
    
    /// Combined drag gesture used to detect downpress and long-press.
    /// - On first finger down in START state (not running, not waiting, not countdown):
    ///   - Sets `isInLongPressMode = true` to tint background dark green (Goal 0)
    ///   - Calls `viewModel.startRun()` and sets `timerStartedButHidden = true` to start the timer without showing it (Goal 0)
    ///   - Schedules a 1.5s `DispatchWorkItem` to detect a sustained hold and present the menu, resetting the timer (Goal 2)
    /// - On finger up before 3s:
    ///   - Cancels the work item, exits long-press mode, and reveals the running timer (Goal 1)
    /// - If already running (timer visible), a downpress immediately stops the run and presents a Save/Delete/Save with Notes menu (no home menu, no delay)
    private func combinedGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                // Only handle the first change event (finger down)
                if !tapHandled {
                    tapHandled = true
                    isInLongPressMode = true // Enter long press mode on finger down
                    
                    // Handle both START and STOP on finger down
                    if !viewModel.isRunning && !viewModel.isWaitingForMotion && !viewModel.isInCountdown {
                        // Defensive: ensure no timer is running and elapsed is zero before starting
                        if viewModel.isRunning {
                            print("❌ TimerView: Attempted to start while already running. Forcing reset.")
                            viewModel.resetTimer()
                        }
                        assert(!viewModel.isRunning, "TimerView: startRun called while already running")
                        // Force a clean start from 0
                        viewModel.resetTimer()
                        
                        // Goal 0: Start immediately but keep the timer display hidden while finger is down
                        viewModel.startRun()
                        timerStartedButHidden = true
                        
                        // Only start long press timer for menu in START state
                        // Cancel any pending work item from a previous press
                        menuWorkItem?.cancel()
                        // Goal 2: If the downpress is held for 1.5 seconds, reset and show the home menu
                        let work = DispatchWorkItem {
                            // Check current flags at fire time to avoid stale triggers
                            if self.tapHandled && self.isInLongPressMode {
                                // Long press in START state: discard run and show menu
                                // IMPORTANT: DO NOT CHANGE - This properly resets the stopwatch
                                viewModel.resetTimer()
                                self.showingPauseMenu = true
                                // Exit long-press mode and clear temporary state
                                self.tapHandled = false
                                self.isInLongPressMode = false
                                self.timerStartedButHidden = false
                                // Clear reference to the completed work item
                                self.menuWorkItem = nil
                            }
                        }
                        menuWorkItem = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
                    } else if viewModel.isRunning && !timerStartedButHidden {
                        // RUNNING: On finger down, stop the run at this exact time (start of long-press)
                        // and present a custom action menu to Save or Delete. Do not show home menu here.
                        let result = viewModel.stopRun(modelContext: DataManager.shared.modelContainer.mainContext)
                        // Store whether this was considered an outlier; if so, we'll save explicitly on confirmation.
                        pendingStopWasOutlier = result.isOutlier
                        // Present the run action menu (three options: Save Run, Delete Run, Save with Notes)
                        showingRunActionMenu = true
                        lockRunningAppearance = true
                        // Do NOT show the outlier alert here and do NOT navigate to home menu.
                        // NO long press behavior in RUNNING state beyond presenting this menu
                    }
                }
            }
            .onEnded { _ in
                menuWorkItem?.cancel()
                menuWorkItem = nil
                
                // Exit long press mode and reveal timer when finger is lifted
                isInLongPressMode = false
                tapHandled = false
                
                // Goal 1: If the timer was started while hidden, reveal it (show elapsed time)
                if timerStartedButHidden {
                    timerStartedButHidden = false
                }
            }
    }
    
    /// Background color reflects state; in START long-press, dark green indicates finger down (Goal 0)
    private func backgroundColor() -> Color {
        if lockRunningAppearance { return isInLongPressMode ? Color.blue.opacity(0.5) : Color.blue }
        if (!viewModel.isRunning && !viewModel.isWaitingForMotion && !viewModel.isInCountdown) || timerStartedButHidden {
            // START state or timer started but hidden - show dark green when in long press mode
            return isInLongPressMode ? Color.green.opacity(0.5) : Color.green
        } else if viewModel.isWaitingForMotion || viewModel.isInCountdown {
            return Color.orange
        } else if viewModel.isRunning && !timerStartedButHidden {
            // Only show blue when timer is visible
            return isInLongPressMode ? Color.blue.opacity(0.5) : Color.blue
        }
        return Color.black
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

struct RunningActionMenuView: View {
    let onSave: () -> Void
    let onDelete: () -> Void
    let onSaveWithNotes: () -> Void
    @State private var pressStart: Date? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 10) {
                Spacer(minLength: 24)

                // Save Run button (first)
                Button(action: onSave) {
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

                // Save with Run Notes button (second)
                Button(action: onSaveWithNotes) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.and.list.clipboard")
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

                // Delete Run button (third)
                Button(action: onDelete) {
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
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if pressStart == nil { pressStart = Date() }
                }
                .onEnded { _ in
                    let start = pressStart ?? Date()
                    let duration = Date().timeIntervalSince(start)
                    pressStart = nil
                    if duration < 3.0 {
                        // Quick click: auto-save
                        onSave()
                    }
                    // If >= 3s, do nothing (buttons remain for explicit choice)
                }
        )
    }
}

