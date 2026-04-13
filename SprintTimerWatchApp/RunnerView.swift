import SwiftUI
#if os(watchOS)
import WatchKit
#endif
import SwiftData

struct RunnerView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Binding var isPresented: Bool

    // Sheet states for notes screens
    @State private var showingRunNotesSheet = false
    @State private var showingDayNotesSheet = false
    @State private var showingPostRunNotesSheet = false
    @State private var lastSavedRun: Run?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TimerView(viewModel: viewModel, isPresented: $isPresented)
            .ignoresSafeArea()
            .navigationBarHidden(true)

            // Run notes sheet (invoked from Save w/Notes)
            .sheet(isPresented: $showingRunNotesSheet) {
                NotesView(viewModel: viewModel)
            }

            // Day notes sheet
            .sheet(isPresented: $showingDayNotesSheet) {
                DayNotesView(viewModel: viewModel)
            }

            // Post-run notes prompt (shown after every save)
            .sheet(isPresented: $showingPostRunNotesSheet, onDismiss: {
                viewModel.resetTimer()
                isPresented = false
            }) {
                if let run = lastSavedRun {
                    PostRunNotesView(run: run)
                }
            }

            // Reset timer whenever RunnerView disappears (navigating back to home)
            .onDisappear {
                if viewModel.isRunning || viewModel.isInCountdown || viewModel.isWaitingForMotion || viewModel.elapsedTime > 0 {
                    viewModel.resetTimer()
                }
            }

            // Dismiss hook
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DismissRunnerView"))) { _ in
                isPresented = false
            }

            // Open notes sheet
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowRunNotes"))) { notification in
                if let run = notification.object as? Run {
                    viewModel.currentRunNotes = run.notes
                    viewModel.currentEditingRun = run
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingRunNotesSheet = true
                }
            }

            // Post-run notes prompt after saving
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowPostRunNotes"))) { _ in
                let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.date, order: .reverse)])
                if let runs = try? modelContext.fetch(descriptor), let latest = runs.first {
                    lastSavedRun = latest
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingPostRunNotesSheet = true
                }
            }

            // Day notes
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowDayNotes"))) { notification in
                if let date = notification.object as? Date {
                    viewModel.currentEditingDate = date
                }
                DispatchQueue.main.async {
                    showingDayNotesSheet = true
                }
            }
    }
}
