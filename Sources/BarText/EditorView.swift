import SwiftUI

/// The contents of the "Edit text" window: a single text field plus Save.
/// Enter and the Save button both commit through `onSave`.
struct EditorView: View {
    @State private var text: String
    private let onSave: (String) -> Void

    init(text: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.onSave = onSave
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("Text", text: $text)
                .textFieldStyle(.roundedBorder)

            Button("Save") { onSave(text) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .frame(width: 380, height: 56)
    }
}
