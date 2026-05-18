import SwiftUI

struct SegmentedTimeEditor: View {
    @Binding var elapsed: TimeInterval
    @Binding var isValid: Bool

    @State private var minutesText: String = ""
    @State private var secondsText: String = ""
    @State private var msText: String = ""
    @State private var hasSeeded = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case minutes, seconds, milliseconds
    }

    private var secondsValue: Int? { Int(secondsText) }
    private var msValue: Int? { Int(msText) }

    private var secondsOutOfRange: Bool {
        if let s = secondsValue { return s > 59 }
        return false
    }

    private var msOutOfRange: Bool {
        if let m = msValue { return m > 999 }
        return false
    }

    private var errorMessage: String? {
        if secondsOutOfRange { return "Seconds must be 0–59" }
        if msOutOfRange { return "Milliseconds must be 0–999" }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                segment($minutesText, placeholder: "0", label: "min", field: .minutes, width: 64)
                separator(":")
                segment($secondsText, placeholder: "00", label: "sec", field: .seconds, width: 64)
                separator(".")
                segment($msText, placeholder: "000", label: "ms", field: .milliseconds, width: 88)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .onAppear {
            if !hasSeeded {
                seedFromElapsed()
                hasSeeded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = .seconds
            }
        }
        .onChange(of: minutesText) { _, newValue in
            limit(&minutesText, to: 3, from: newValue)
            recompute()
        }
        .onChange(of: secondsText) { _, newValue in
            limit(&secondsText, to: 2, from: newValue)
            recompute()
        }
        .onChange(of: msText) { _, newValue in
            limit(&msText, to: 3, from: newValue)
            recompute()
        }
    }

    @ViewBuilder
    private func segment(_ text: Binding<String>, placeholder: String, label: String, field: Field, width: CGFloat) -> some View {
        VStack(spacing: 4) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 40, weight: .medium, design: .rounded).monospacedDigit())
                .frame(width: width)
                .focused($focusedField, equals: field)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func separator(_ char: String) -> some View {
        Text(char)
            .font(.system(size: 36, weight: .light))
            .foregroundColor(.secondary)
            .padding(.top, 2)
    }

    private func limit(_ text: inout String, to maxDigits: Int, from newValue: String) {
        let digitsOnly = newValue.filter { $0.isNumber }
        if digitsOnly.count > maxDigits {
            text = String(digitsOnly.prefix(maxDigits))
        } else if digitsOnly != newValue {
            text = digitsOnly
        }
    }

    private func seedFromElapsed() {
        let total = max(elapsed, 0)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let ms = Int((total.truncatingRemainder(dividingBy: 1)) * 1000)
        minutesText = String(minutes)
        secondsText = String(seconds)
        msText = String(format: "%d", ms)
    }

    private func recompute() {
        let m = Int(minutesText) ?? 0
        let s = secondsValue ?? 0
        let ms = msValue ?? 0
        let valid = !secondsOutOfRange && !msOutOfRange && m >= 0
        isValid = valid
        if valid {
            elapsed = TimeInterval(m * 60) + TimeInterval(s) + TimeInterval(ms) / 1000.0
        }
    }
}
