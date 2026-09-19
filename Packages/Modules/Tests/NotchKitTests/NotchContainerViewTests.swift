import AppKit
import Testing
@testable import NotchKit

@MainActor
struct NotchContainerViewTests {
    private func container() -> NotchContainerView {
        let view = NotchContainerView(frame: CGRect(x: 0, y: 0, width: 326, height: 982))
        view.setHotRect(CGRect(x: 256, y: 391, width: 70, height: 200))
        return view
    }

    @Test func clicksOutsideHotRectFallThrough() {
        #expect(container().hitTest(CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func clicksInsideHotRectAreTaken() {
        let view = container()
        #expect(view.hitTest(CGPoint(x: 300, y: 450)) === view)
    }

    @Test func isFlippedToMatchSwiftUI() {
        #expect(container().isFlipped)
    }

    @Test func readsOnlyFileURLsFromPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NotchContainerViewTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL, URL(string: "https://example.com")! as NSURL])
        #expect(NotchContainerView.fileURLs(pasteboard) == [URL(fileURLWithPath: "/tmp/a.txt")])
        pasteboard.releaseGlobally()
    }
}
