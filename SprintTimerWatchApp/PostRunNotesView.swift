import SwiftUI
import SwiftData

struct PostRunNotesView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    var body: some View {
        VStack(spacing: 6) {
#if os(watchOS)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button("Skip") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                        .font(.body)

                    Button("Save") {
                        if !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            run.notes = noteText
                            try? DataManager.shared.modelContainer.mainContext.save()
                        }
                        dismiss()
                    }
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
            Text("Add Notes?")
                .font(.system(size: 16, weight: .bold))

            Text(run.formattedTime)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 80)
                .padding(.horizontal, 8)

            HStack(spacing: 12) {
                Button("Skip") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    if !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        run.notes = noteText
                        try? DataManager.shared.modelContainer.mainContext.save()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
#endif

            Spacer(minLength: 0)
        }
        .onAppear {
            noteText = run.notes
        }
    }
}
