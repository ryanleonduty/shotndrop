import SwiftUI

struct ShelfTrayHeaderView: View {
    let count: Int

    var body: some View {
        HStack {
            Text("[ SHOTNDROP // INVENTORY ]")
                .font(PixelDesign.Font.face(.display, size: 10))
                .foregroundColor(PixelDesign.Palette.white)
            Spacer()
            Text("\(count) / \(ShelfInventory.capacity)")
                .font(PixelDesign.Font.face(.body, size: 16))
                .foregroundColor(PixelDesign.Palette.cyan)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(PixelDesign.Palette.rune)
        }
        .frame(height: PixelDesign.Geometry.trayHeaderHeight)
        .padding(.horizontal, 10)
        .background(PixelDesign.Palette.midnight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PixelDesign.Palette.cyanDim).frame(height: 1)
        }
    }
}
