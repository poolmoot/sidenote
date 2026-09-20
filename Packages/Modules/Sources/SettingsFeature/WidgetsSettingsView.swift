import SwiftUI
import NotchWidgetAPI

/// Settings › Widgets: a checkbox and drag-to-reorder per widget (spec §3.6). Enabled widgets are
/// listed first, in the order `enabledWidgetIDs` already carries; any disabled widget follows, so
/// unchecking one doesn't remove it from view — it can still be reordered and re-checked later.
struct WidgetsSettingsView: View {
    let preferences: Preferences
    let widgets: [any NotchWidget]

    @State private var rows: [WidgetRow] = []

    var body: some View {
        List {
            reorderableRows
        }
        .onAppear {
            guard rows.isEmpty else { return }
            rows = Self.makeRows(widgets: widgets, enabledWidgetIDs: preferences.enabledWidgetIDs)
        }
        .onChange(of: rows) { _, _ in persist() }
    }

    @ViewBuilder
    private var reorderableRows: some View {
        if #available(macOS 27, *) {
            ForEach($rows) { $row in
                WidgetRowView(row: $row)
            }
            .reorderable()
        } else {
            ForEach($rows) { $row in
                WidgetRowView(row: $row)
            }
            .onMove { indices, newOffset in
                rows.move(fromOffsets: indices, toOffset: newOffset)
            }
        }
    }

    private func persist() {
        let enabled = rows.filter(\.isEnabled).map(\.id)
        guard enabled != preferences.enabledWidgetIDs else { return }
        preferences.enabledWidgetIDs = enabled
    }

    /// Enabled widgets first (in `enabledWidgetIDs` order), then any remaining registered widget —
    /// disabled, but still shown so it can be re-enabled and placed.
    private static func makeRows(widgets: [any NotchWidget], enabledWidgetIDs: [WidgetID]) -> [WidgetRow] {
        let registry = Dictionary(widgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let enabledSet = Set(enabledWidgetIDs)
        var order: [WidgetID] = []
        var seen = Set<WidgetID>()
        for id in enabledWidgetIDs where registry[id] != nil && seen.insert(id).inserted {
            order.append(id)
        }
        for widget in widgets where seen.insert(widget.id).inserted {
            order.append(widget.id)
        }
        return order.compactMap { id in
            guard let widget = registry[id] else { return nil }
            return WidgetRow(id: id, title: widget.title, systemImage: widget.systemImage, isEnabled: enabledSet.contains(id))
        }
    }
}

struct WidgetRow: Identifiable, Equatable {
    let id: WidgetID
    let title: String
    let systemImage: String
    var isEnabled: Bool
}

private struct WidgetRowView: View {
    @Binding var row: WidgetRow

    var body: some View {
        Toggle(isOn: $row.isEnabled) {
            Label(row.title, systemImage: row.systemImage)
        }
    }
}
