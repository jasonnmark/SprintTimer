import SwiftUI

struct NotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                Text("Run Notes")
                    .font(.system(size: 14, weight: .bold))
                
                ScrollView {
                    TextField("Add run notes...", text: $noteText)
                        .font(.system(size: 12))
                        .focused($isTextFieldFocused)
                        .padding(.horizontal)
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
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
        viewModel.currentRunNotes = noteText
        dismiss()
    }
}
