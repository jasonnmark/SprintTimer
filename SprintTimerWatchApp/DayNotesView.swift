import SwiftUI

struct DayNotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                Text("Day Notes")
                    .font(.system(size: 14, weight: .bold))
                
                ScrollView {
                    TextField("Add day notes...", text: $noteText)
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
                        saveDayNotes()
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
            // Load existing day notes
            noteText = dailyNotesManager.getNote(for: Date())
            
            // Focus the text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func saveDayNotes() {
        dailyNotesManager.setNote(noteText, for: Date())
        dismiss()
    }
}
