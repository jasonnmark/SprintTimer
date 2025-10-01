import SwiftUI

struct NotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
#if os(watchOS)
                TextField("Add run notes...", text: $noteText, axis: .vertical)
                    .font(.system(size: 12))
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.horizontal)
#else
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $noteText)
                        .font(.system(size: 12))
                        .focused($isTextFieldFocused)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    if noteText.isEmpty {
                        Text("Add run notes...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal)
#endif
                
                HStack(spacing: 12) {
                    Button(action: {
                        saveNotes()
                    }) {
                        Text("Save")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            // Load existing run notes
            noteText = viewModel.currentRunNotes
            
            // Focus the text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func saveNotes() {
        // Attach notes to the current (stopped) run and save it now
        viewModel.currentRunNotes = noteText
        viewModel.saveCurrentRun(modelContext: DataManager.shared.modelContainer.mainContext)
        viewModel.resetTimer()
        dismiss()
    }
}
