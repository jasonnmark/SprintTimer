import SwiftUI
import SwiftData

struct PostRunNotesView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Add Notes?")
                .font(.system(size: 16, weight: .bold))

            Text(run.formattedTime)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

#if os(watchOS)
            TextField("Tap to dictate...", text: $noteText, axis: .vertical)
                .font(.system(size: 12))
                .focused($isTextFieldFocused)
                .focusable()
                .padding(.horizontal, 8)
#else
            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 80)
                .padding(.horizontal, 8)
#endif

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

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .onAppear {
            noteText = run.notes
            #if os(watchOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
            #endif
        }
    }
}
