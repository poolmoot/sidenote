import SwiftUI

public extension Shape {
    /// Fills this shape as the notch body (spec §5). Solid black always; Liquid Glass layers
    /// macOS 26's glass material on top, but only while unfolded — the folded pill stays plain
    /// black-edged so it still reads as a continuation of the bezel rather than a floating panel.
    @ViewBuilder
    func notchSurface(style: NotchStyle, isFolded: Bool) -> some View {
        if style == .liquidGlass, !isFolded {
            fill(Palette.notch)
                .glassEffect(.regular, in: self)
        } else {
            fill(Palette.notch)
        }
    }
}
