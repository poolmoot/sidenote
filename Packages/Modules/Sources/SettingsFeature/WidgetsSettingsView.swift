import SwiftUI
import NotchWidgetAPI

/// Settings › Widgets: a checkbox and drag-to-reorder per widget (spec §3.6). Enabled widgets are
/// listed first, in the order `enabledWidgetIDs` already carries; any disabled widget follows, so
/// unchecking one doesn't remove it from view — it can still be reordered and re-checked later.
///
/// `rows` is derived fresh from `preferences.enabledWidgetIDs` on every `body` evaluation
/// (AGENTS rule 5: no `@State` copy of store/Preferences data, fixed post-review — this used to
/// seed a `@State [WidgetRow]` once from `Preferences` and only ever write back *from* it) — a
/// reorder or toggle computes the new order/membership and writes straight back to
/// `preferences.enabledWidgetIDs`.
struct WidgetsSettingsView: View {
    let preferences: Preferences
    let widgets: [any NotchWidget]

    private var rows: [WidgetRow] {
        Self.makeRows(widgets: widgets, enabledWidgetIDs: preferences.enabledWidgetIDs)
    }

    var body: some View {
        if #available(macOS 27, *) {
            List {
                ForEach(rows) { row in
                    WidgetRowView(row: row, onToggle: { setEnabled($0, for: row.id) })
                }
                .reorderable()
            }
            .reorderContainer(for: WidgetRow.self) { difference in
                persist(Self.applying(difference, to: rows))
            }
        } else {
            List {
                ForEach(rows) { row in
                    WidgetRowView(row: row, onToggle: { setEnabled($0, for: row.id) })
                }
                .onMove { indices, newOffset in
                    var reordered = rows
                    reordered.move(fromOffsets: indices, toOffset: newOffset)
                    persist(reordered)
                }
            }
        }
    }

    private func setEnabled(_ isEnabled: Bool, for id: WidgetID) {
        var updated = rows
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isEnabled = isEnabled
        persist(updated)
    }

    /// Applies a macOS 27 `reorderContainer` difference to `current`'s order. `sources` is every
    /// id being moved (a multi-selection drag can move more than one); it's removed from its old
    /// position(s) and reinserted as a block just before `destination`'s anchor id, or at the end.
    @available(macOS 27, *)
    private static func applying(
        _ difference: ReorderDifference<WidgetID, ReorderableSingleCollectionIdentifier>,
        to current: [WidgetRow]
    ) -> [WidgetRow] {
        var order = current.map(\.id)
        let moving = Set(difference.sources)
        order.removeAll { moving.contains($0) }

        let insertionIndex: Int
        switch difference.destination.position {
        case .before(let anchorID):
            insertionIndex = order.firstIndex(of: anchorID) ?? order.count
        case .end:
            insertionIndex = order.count
        @unknown default:
            insertionIndex = order.count
        }
        order.insert(contentsOf: difference.sources, at: min(insertionIndex, order.count))

        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        return order.compactMap { byID[$0] }
    }

    private func persist(_ rows: [WidgetRow]) {
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
    let row: WidgetRow
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { row.isEnabled }, set: { onToggle($0) })) {
            Label(row.title, systemImage: row.systemImage)
        }
    }
}
