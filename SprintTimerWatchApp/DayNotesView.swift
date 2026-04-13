import SwiftUI

struct DayNotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var noteText = ""
    @State private var editingDate = Date() // Date being edited
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("Day Notes")
                    .font(.system(size: 14, weight: .bold))
                
#if os(watchOS)
                TextField("Add day notes...", text: $noteText, axis: .vertical)
                    .font(.system(size: 16))
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
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
                        Text("Add day notes...")
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
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 16))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        saveDayNotes()
                    }) {
                        Text("Save")
                            .font(.system(size: 16))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            // Use the date from viewModel if it exists (when editing from history), otherwise use today
            if let editDate = viewModel.currentEditingDate {
                editingDate = editDate
            } else {
                editingDate = Date()
            }
            
            // Load existing day notes for the specified date
            noteText = dailyNotesManager.getNote(for: editingDate)
            
            // Focus the text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func saveDayNotes() {
        dailyNotesManager.setNote(noteText, for: editingDate)
        
        // Clear the editing date reference when done
        viewModel.currentEditingDate = nil
        
        dismiss()
    }
}
