import SwiftUI
import SwiftData

struct NotesView: View {
    @ObservedObject var viewModel: SprintTimerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var noteText = ""

    var body: some View {
        VStack(spacing: 6) {
#if os(watchOS)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button("Cancel") { handleFinish(saveNotes: false) }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .font(.body)

                    Button("Done") { handleFinish(saveNotes: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .font(.body)
                        .disabled(noteText.isEmpty)
                }
                .padding(.horizontal)

                ScrollView {
                    Text(noteText.isEmpty ? "Tap mic to dictate" : noteText)
                        .font(.system(size: 32, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .foregroundColor(noteText.isEmpty ? .gray : .primary)
                }

                TextFieldLink(prompt: Text("Speak your note...")) {
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
            Text("Run Notes")
                .font(.system(size: 14, weight: .bold))

            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(.horizontal, 8)

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
#endif

            Spacer(minLength: 0)
        }
        .navigationBarHidden(true)
        .onAppear {
            noteText = viewModel.currentRunNotes
        }
    }

    private func handleFinish(saveNotes: Bool) {
        if saveNotes {
            if let editingRun = viewModel.currentEditingRun {
                editingRun.notes = noteText
                try? modelContext.save()
                viewModel.currentEditingRun = nil
            } else {
                viewModel.currentRunNotes = noteText
                viewModel.saveCurrentRun(modelContext: modelContext)
                viewModel.resetTimer()
            }
        } else {
            if viewModel.currentEditingRun != nil {
                viewModel.currentEditingRun = nil
            }
        }
        dismiss()
    }
}
