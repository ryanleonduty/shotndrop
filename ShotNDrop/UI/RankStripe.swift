import SwiftUI

/// Pixel rank badge. Rank 1 → cyan; rank 2/3 → violet; rank 4+ → cyan-dim.
struct RankStripe: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(PixelDesign.Font.face(.captionBold, size: 9))
            .foregroundColor(color)
            .frame(width: 20, height: 20)
            .background(PixelDesign.Palette.rune)
            .overlay {
                RankBadgeBorder()
                    .stroke(color, lineWidth: 2)
            }
            .shadow(color: PixelDesign.Palette.void, radius: 0, x: 2, y: 2)
    }

    private var color: Color {
        switch rank {
        case 1: return PixelDesign.Palette.cyan
        case 2, 3: return PixelDesign.Palette.cyanSoft
        default: return PixelDesign.Palette.cyanDim
        }
    }
}

private struct RankBadgeBorder: Shape {
    private let step: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let left = rect.minX
        let top = rect.minY
        let right = rect.maxX
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: left + step, y: top))
        path.addLine(to: CGPoint(x: right - step, y: top))
        path.addLine(to: CGPoint(x: right - step, y: top + step))
        path.addLine(to: CGPoint(x: right, y: top + step))
        path.addLine(to: CGPoint(x: right, y: bottom - step))
        path.addLine(to: CGPoint(x: right - step, y: bottom - step))
        path.addLine(to: CGPoint(x: right - step, y: bottom))
        path.addLine(to: CGPoint(x: left + step, y: bottom))
        path.addLine(to: CGPoint(x: left + step, y: bottom - step))
        path.addLine(to: CGPoint(x: left, y: bottom - step))
        path.addLine(to: CGPoint(x: left, y: top + step))
        path.addLine(to: CGPoint(x: left + step, y: top + step))
        path.closeSubpath()
        return path
    }
}
