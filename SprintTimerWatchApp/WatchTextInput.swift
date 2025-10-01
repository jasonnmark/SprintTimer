// WatchTextInput.swift
#if os(watchOS)
import WatchKit

enum WatchTextInput {
    static func present(initialText: String?, completion: @escaping (String?) -> Void) {
        guard let host = WKExtension.shared().visibleInterfaceController else {
            completion(nil)
            return
        }

        // QuickBoard can’t truly “prefill” text, but we can provide an initial suggestion.
        let suggestions: [String]? = {
            guard let t = initialText, !t.isEmpty else { return nil }
            return [t]
        }()

        host.presentTextInputController(
            withSuggestions: suggestions,
            allowedInputMode: .plain
        ) { result in
            // Result is [Any]? (Strings). We only care about the first string.
            let text = (result as? [String])?.first
            completion(text)
        }
    }
}
#endif
