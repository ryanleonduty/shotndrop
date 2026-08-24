import SwiftUI

struct ShelfTrayFooterView: View {
    var body: some View {
        HStack {
            Text("DRAG OUT → CONSUMES")
                .font(PixelDesign.Font.face(.caption, size: 9))
                .foregroundColor(PixelDesign.Palette.whiteDim)
            Spacer()
            HStack(spacing: 4) {
                Text("ESC")
                    .font(PixelDesign.Font.face(.captionBold, size: 9))
                    .foregroundColor(PixelDesign.Palette.cyan)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        Rectangle()
                            .strokeBorder(PixelDesign.Palette.cyan, lineWidth: 1)
                    )
                Text("COLLAPSE")
                    .font(PixelDesign.Font.face(.caption, size: 9))
                    .foregroundColor(PixelDesign.Palette.whiteDim)
            }
        }
        .frame(height: PixelDesign.Geometry.trayFooterHeight)
        .padding(.horizontal, 10)
        .background(PixelDesign.Palette.midnight)
        .overlay(alignment: .top) {
            Rectangle().fill(PixelDesign.Palette.cyanDim).frame(height: 1)
        }
    }
}
