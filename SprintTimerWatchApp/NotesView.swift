import SwiftUI
import SwiftData

struct NotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("Run Notes")
                    .font(.system(size: 14, weight: .bold))
                
#if os(watchOS)
                TextField("Add run notes...", text: $noteText, axis: .vertical)
                    .font(.system(size: 16))
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
#else
                TextEditor(text: $noteText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 8)
#endif

                HStack(spacing: 12) {
                    Button("Cancel") {
                        handleFinish(saveNotes: false)
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        handleFinish(saveNotes: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
                
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .navigationBarHidden(true)
        }
        .onAppear {
            // Start with whatever notes were previously stored (if any)
            noteText = viewModel.currentRunNotes

            // Focus the text field on watch to bring up keyboard/dictation automatically
            #if os(watchOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
            #endif
        }
    }
    
    private func handleFinish(saveNotes: Bool) {
        if saveNotes {
            if let editingRun = viewModel.currentEditingRun {
                // We're editing an existing run from history
                editingRun.notes = noteText
                // The run is already in the model context, just save it
                try? modelContext.save()
                // Clear the editing reference
                viewModel.currentEditingRun = nil
            } else {
                // We're creating a new run (original behavior)
                viewModel.currentRunNotes = noteText
                viewModel.saveCurrentRun(modelContext: modelContext)
                viewModel.resetTimer()
                // Dismiss RunnerView to return to home
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: Notification.Name("DismissRunnerView"), object: nil)
                }
            }
        } else {
            // Cancel: clear editing reference if we were editing
            if viewModel.currentEditingRun != nil {
                viewModel.currentEditingRun = nil
            }
        }
        // Dismiss ONLY the notes sheet
        dismiss()
    }
}
