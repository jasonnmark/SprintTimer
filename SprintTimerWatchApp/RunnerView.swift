import SwiftUI
#if os(watchOS)
import WatchKit
#endif
import SwiftData

struct RunnerView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Binding var isPresented: Bool

    // NEW: Sheet states for notes screens
    @State private var showingRunNotesSheet = false
    @State private var showingDayNotesSheet = false

    var body: some View {
        TimerView(viewModel: viewModel, isPresented: $isPresented)
            .ignoresSafeArea()
            .navigationBarHidden(true)

            // NEW: Run notes sheet (invoked from Save w/Notes and from Pause menu)
            .sheet(isPresented: $showingRunNotesSheet) {
                NotesView(viewModel: viewModel)
            }

            // (Optional) Day notes sheet — you already fire ShowDayNotes from the pause sheet
            .sheet(isPresented: $showingDayNotesSheet) {
                DayNotesView(viewModel: viewModel)
            }

            // Keep your existing dismiss hook
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DismissRunnerView"))) { _ in
                isPresented = false
            }

            // CHANGED: Instead of invoking QuickBoard, we now open the sheet
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowRunNotes"))) { notification in
                // If we have a run object passed from history, load its notes
                if let run = notification.object as? Run {
                    viewModel.currentRunNotes = run.notes
                    viewModel.currentEditingRun = run  // Store reference for saving back
                }
                
                // Give any menu/animation a tick to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingRunNotesSheet = true
                }
            }

            // Keep day-notes path working from your pause menu
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowDayNotes"))) { notification in
                // If we have a date object passed from history, load it for editing
                if let date = notification.object as? Date {
                    viewModel.currentEditingDate = date
                }
                
                DispatchQueue.main.async {
                    showingDayNotesSheet = true
                }
            }
    }
}
