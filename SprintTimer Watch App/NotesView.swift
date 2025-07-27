import SwiftUI

struct NotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @State private var noteText = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Run Notes")
                .font(.headline)
            
            Text("Add notes for this run")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            
            // Text input
            TextField("Tap to add notes", text: $noteText)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            
            Spacer()
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Save") {
                    viewModel.currentRunNotes = noteText
                    dismiss()
                }
            }
        }
        .padding()
        .onAppear {
            noteText = viewModel.currentRunNotes
        }
    }
}
