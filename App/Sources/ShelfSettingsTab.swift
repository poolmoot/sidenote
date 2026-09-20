import SwiftUI
import ShelfFeature

/// Settings › Shelf: item count and *Clear shelf* (spec §3.6). Lives in the app target, not
/// `SettingsFeature`, because it needs `ShelfStore` directly and features never import each other.
struct ShelfSettingsTab: View {
    let store: ShelfStore

    var body: some View {
        Form {
            Section("Shelf") {
                LabeledContent("Items", value: "\(store.items.count)")
                Button("Clear Shelf", role: .destructive) {
                    store.clear()
                }
                .disabled(store.items.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}
