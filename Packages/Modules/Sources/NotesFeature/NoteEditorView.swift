import SwiftUI
import Foundation
import NotchWidgetAPI
import DesignSystem

/// A single note's editor: a raw `TextEditor` for typing, and a rendered preview below it where
/// checklist lines (`- [ ]` / `- [x]`) are tickable and URLs are clickable (spec §3.4).
///
/// Typing engages the widget's editing lock (`WidgetContext.setEditing`) so the notch doesn't fold
/// mid-keystroke when the app loses key status (see M1's review notes); leaving the editor — the
/// back chevron, or the notch folding — disengages it and flushes any pending write immediately.
struct NoteEditorView: View {
    let note: Note
    let store: NotesStore
    let context: WidgetContext
    let onBack: () -> Void

    @State private var text: String
    @FocusState private var isEditorFocused: Bool

    init(note: Note, store: NotesStore, context: WidgetContext, onBack: @escaping () -> Void) {
        self.note = note
        self.store = store
        self.context = context
        self.onBack = onBack
        _text = State(initialValue: note.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Palette.primaryText)
                .frame(minHeight: 90, maxHeight: 140)
                .focused($isEditorFocused)
            Divider()
            preview
        }
        .onAppear { isEditorFocused = true }
        // Autosave (spec §3.4): every change bumps `updatedAt` and hands the store the new text;
        // `JSONFileStore` itself debounces the actual disk write ~0.5s after the last keystroke.
        .onChange(of: text) { _, newValue in
            store.update(id: note.id, text: newValue)
        }
        .onChange(of: isEditorFocused) { _, focused in
            context.setEditing(focused)
        }
    }

    private var header: some View {
        HStack {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(Palette.primaryText)
            .accessibilityLabel("Back to notes")
            Spacer()
        }
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    lineView(for: line, at: index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    @ViewBuilder
    private func lineView(for line: Substring, at index: Int) -> some View {
        switch ChecklistLine.parse(line) {
        case .checkbox(_, let done, let checkboxText):
            HStack(alignment: .top, spacing: 6) {
                Button {
                    store.toggleCheckbox(id: note.id, lineIndex: index)
                } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(done ? Color.accentColor : Palette.secondaryText)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()

                linkText(checkboxText)
                    .strikethrough(done)
                    .foregroundStyle(done ? Palette.secondaryText : Palette.primaryText)
            }
        case .plain(let plainText):
            if !plainText.isEmpty {
                linkText(plainText)
                    .foregroundStyle(Palette.primaryText)
            }
        }
    }

    /// `string` rendered with any URLs autodetected and marked as `.link`, so `Text` makes them
    /// clickable (SwiftUI opens a `.link` attribute in the default browser on its own — spec §3.4).
    private func linkText(_ string: String) -> Text {
        Text(Self.attributedString(for: string))
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func attributedString(for string: String) -> AttributedString {
        var attributed = AttributedString(string)
        guard let detector = linkDetector else { return attributed }
        let fullRange = NSRange(string.startIndex..<string.endIndex, in: string)
        for match in detector.matches(in: string, range: fullRange) {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: string),
                  let attributedRange = Range(stringRange, in: attributed) else { continue }
            attributed[attributedRange].link = url
            attributed[attributedRange].underlineStyle = .single
        }
        return attributed
    }

    private func goBack() {
        context.setEditing(false)
        store.flush()
        onBack()
    }
}
