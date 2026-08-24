import SwiftUI

/// Dotted-pattern rune glyph rendered at the right of each tray row. Not
/// interactive on its own — the whole row is the drag source.
struct DragHandleRune: View {
    var body: some View {
        Canvas { context, size in
            let dot: CGFloat = 2
            let gapY: CGFloat = 3
            let color = PixelDesign.Palette.cyan
            let cols: [CGFloat] = [size.width * 0.35, size.width * 0.65]
            var y: CGFloat = size.height * 0.20
            while y <= size.height * 0.80 {
                for x in cols {
                    let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    context.fill(Path(rect), with: .color(color))
                }
                y += gapY
            }
        }
        .frame(width: 20)
    }
}
