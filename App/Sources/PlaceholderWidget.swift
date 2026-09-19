import SwiftUI
import Observation
import NotchWidgetAPI

/// Stand-ins for the three mini apps until their milestones land (Shelf M2, Notes M3,
/// Reminders M4). Each exercises one piece of notch plumbing: the shelf takes file drops, and every
/// placeholder has a text field that engages the editing lock.
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
            PlaceholderWidget(id: .shelf, title: "Shelf", systemImage: "tray", milestone: "M2", acceptsFileDrops: true),
            PlaceholderWidget(id: .notes, title: "Notes", systemImage: "note.text", milestone: "M3"),
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
