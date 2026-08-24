import SwiftUI

/// Left-edge 4pt stripe. Rank 1 → cyan; rank 2/3 → violet; rank 4+ → cyan-dim.
struct RankStripe: View {
    let rank: Int

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 4)
    }

    private var color: Color {
        switch rank {
        case 1: return PixelDesign.Palette.cyan
        case 2, 3: return PixelDesign.Palette.violet
        default: return PixelDesign.Palette.cyanDim
        }
    }
}
