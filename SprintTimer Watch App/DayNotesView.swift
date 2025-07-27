import SwiftUI

struct DayNotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @State private var noteText = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Daily Notes")
                .font(.headline)
            
            Text("These notes will be added to all runs today")
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            // Display current notes
            if !viewModel.dailyNotes.isEmpty {
                Text("Current: \(viewModel.dailyNotes)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            
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
                    if !noteText.isEmpty {
                        viewModel.dailyNotes = noteText
                    }
                    dismiss()
                }
                .disabled(noteText.isEmpty)
            }
        }
        .padding()
        .onAppear {
            noteText = viewModel.dailyNotes
        }
    }
}
