import SwiftUI
import SwiftData
import HealthKit

struct PostRunNotesView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    private var savedToHealth: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = HKHealthStore().authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
    }
    var body: some View {
        VStack(spacing: 6) {
#if os(watchOS)
            ScrollView {
                VStack(spacing: 12) {
                    if savedToHealth {
                        HStack(spacing: 4) {
                            Image("AppleHealthIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                            Text("Saved to Apple Health")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

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

                    TextFieldLink(prompt: Text("Speak your note...")) {
                        Label("Dictate", systemImage: "mic.fill")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    } onSubmit: { result in
                        noteText = result
                    }

                    if !noteText.isEmpty {
                        Text(noteText)
                            .font(.system(size: 32, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
            }
#else
            Text("Add Notes?")
                .font(.system(size: 16, weight: .bold))

            Text(run.formattedTime)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            if savedToHealth {
                HStack(spacing: 4) {
                    Image("AppleHealthIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text("Saved to Apple Health")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }

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
