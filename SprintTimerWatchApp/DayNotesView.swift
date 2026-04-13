import SwiftUI

struct DayNotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var noteText = ""
    @State private var editingDate = Date() // Date being edited

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
#if os(watchOS)
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button(action: { dismiss() }) {
                            Text("Cancel")
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { saveDayNotes() }) {
                            Text("Save")
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)

                    ScrollView {
                        Text(noteText.isEmpty ? "Tap mic to dictate" : noteText)
                            .font(.system(size: 32, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .foregroundColor(noteText.isEmpty ? .gray : .primary)
                    }

                    TextFieldLink(prompt: Text("Speak your day notes...")) {
                        Label("Dictate", systemImage: "mic.fill")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    } onSubmit: { result in
                        noteText = result
                    }
                    .padding(.horizontal)
                }
                .ignoresSafeArea(edges: .bottom)
#else
                Text("Day Notes")
                    .font(.system(size: 14, weight: .bold))

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $noteText)
                        .font(.system(size: 12))
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
#endif
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
        }
    }
    
    private func saveDayNotes() {
        dailyNotesManager.setNote(noteText, for: editingDate)
        
        // Clear the editing date reference when done
        viewModel.currentEditingDate = nil
        
        dismiss()
    }
}
