import SwiftUI

struct RunnerView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Binding var isPresented: Bool
    @State private var showingNotes = false
    @State private var notesType: NotesType = .run
    @Environment(\.modelContext) private var modelContext
    
    enum NotesType {
        case day, run
    }
    
    var body: some View {
        TimerView(viewModel: viewModel)
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DismissRunnerView"))) { _ in
                isPresented = false
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowDayNotes"))) { _ in
                notesType = .day
                showingNotes = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowRunNotes"))) { _ in
                notesType = .run
                showingNotes = true
            }
            .sheet(isPresented: $showingNotes) {
                Group {
                    if notesType == .day {
                        DayNotesView(viewModel: viewModel)
                    } else {
                        NotesView(viewModel: viewModel)
                    }
                }
                .interactiveDismissDisabled(true)
            }
    }
}
