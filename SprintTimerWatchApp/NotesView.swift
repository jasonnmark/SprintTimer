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
            ScrollView {
                VStack(spacing: 12) {
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

                    // Always show the current note (incl. GPS-time prefill) above
                    // the Dictate button. Dictation appends, so the prefill survives
                    // unless the user explicitly clears it.
                    if !noteText.isEmpty {
                        Text(noteText)
                            .font(.system(size: 20, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        Button(role: .destructive) {
                            noteText = ""
                        } label: {
                            Label("Clear", systemImage: "xmark.circle.fill")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                    }

                    TextFieldLink(prompt: Text("Speak your note...")) {
                        Label(noteText.isEmpty ? "Dictate" : "Add more", systemImage: "mic.fill")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    } onSubmit: { result in
                        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        noteText = noteText.isEmpty ? trimmed : "\(noteText) \(trimmed)"
                    }
                }
                .padding(.horizontal)
            }
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
                // Propagate the edit to the iPhone so a subsequent full-sync
                // doesn't overwrite the Watch's note with the iPhone's stale copy.
                let syncData = SyncManager.shared.runToSyncData(editingRun)
                SyncManager.shared.syncNewRun(syncData)
                viewModel.currentEditingRun = nil
                dismiss()
            } else {
                viewModel.currentRunNotes = noteText
                viewModel.saveCurrentRun(modelContext: modelContext)
                viewModel.resetTimer()
                // Reset the underlying TimerView from the action menu back to the
                // start screen, then dismiss this sheet. The runner stays open so
                // the user lands on the full-screen Start button.
                NotificationCenter.default.post(name: Notification.Name("ResetTimerViewToStart"), object: nil)
                dismiss()
            }
        } else {
            // Cancel: leave the run unsaved so the underlying action menu reappears
            // with Save/Delete/Notes intact. Don't touch viewModel state.
            if viewModel.currentEditingRun != nil {
                viewModel.currentEditingRun = nil
            }
            dismiss()
        }
    }
}
