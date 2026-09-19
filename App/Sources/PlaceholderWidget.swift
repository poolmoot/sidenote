import SwiftUI
import Observation
import NotchWidgetAPI

/// Stand-ins for the mini apps that haven't landed yet (Reminders M4). The Shelf and Notes
/// placeholders are gone now that `ShelfWidget` (M2) and `NotesWidget` (M3) are real. Each
/// placeholder has a text field that engages the editing lock, so that plumbing keeps getting
/// exercised.
@MainActor
@Observable
final class PlaceholderWidget: NotchWidget {
    let id: WidgetID
    let title: String
    let systemImage: String
    let acceptsFileDrops: Bool
    let milestone: String
    let expandedSize = CGSize(width: 320, height: 420)
    private(set) var droppedNames: [String] = []

    init(id: WidgetID, title: String, systemImage: String, milestone: String, acceptsFileDrops: Bool = false) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.milestone = milestone
        self.acceptsFileDrops = acceptsFileDrops
    }

    static func all() -> [PlaceholderWidget] {
        [
            PlaceholderWidget(id: .reminders, title: "Reminders", systemImage: "bell", milestone: "M4"),
        ]
    }

    func makeExpandedView(context: WidgetContext) -> AnyView {
        AnyView(PlaceholderView(widget: self, context: context))
    }

    func handleFileDrop(_ urls: [URL]) -> Bool {
        droppedNames = urls.map(\.lastPathComponent)
        return true
    }
}

private struct PlaceholderView: View {
    let widget: PlaceholderWidget
    let context: WidgetContext
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(widget.title) arrives in \(widget.milestone).")
                .foregroundStyle(.secondary)
            if !widget.droppedNames.isEmpty {
                Text("Dropped:").font(.subheadline.bold())
                ForEach(widget.droppedNames, id: \.self) { name in
                    Text(name).lineLimit(1).truncationMode(.middle)
                }
            }
            TextField("Type here to test the editing lock", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
            Spacer()
        }
        .onChange(of: isFocused) { _, focused in context.setEditing(focused) }
    }
}
