import SwiftUI

struct NumberSettingField: View {
    let title: String
    @Binding var value: Int
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(_ title: String, value: Binding<Int>) {
        self.title = title
        _value = value
        _draft = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        TextField(title, text: $draft)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .accessibilityLabel(title)
            .onSubmit { commit() }
        .onChange(of: isFocused) { if !isFocused { commit() } }
        .onChange(of: value) { if !isFocused { draft = String(value) } }
        .onDisappear { commit() }
    }

    private func commit() {
        // Commit after editing so an unfinished history count cannot discard entries.
        if let number = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) { value = number }
        draft = String(value)
    }
}
