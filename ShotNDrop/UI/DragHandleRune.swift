import SwiftUI

/// Compact pixel grab affordance rendered at the right of each tray row. Not
/// interactive on its own — the whole row is the drag source.
struct DragHandleRune: View {
    var body: some View {
        Canvas { context, size in
            let pixel: CGFloat = 3
            let gap: CGFloat = 3
            let color = PixelDesign.Palette.cyanDim
            let columns: [CGFloat] = [size.width * 0.35, size.width * 0.65]
            let startY = (size.height - (pixel * 3 + gap * 2)) / 2

            for row in 0..<3 {
                let y = startY + CGFloat(row) * (pixel + gap)
                for x in columns {
                    let rect = CGRect(x: x - pixel / 2, y: y, width: pixel, height: pixel)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: 20, height: 20)
    }
}
