import SwiftUI

/// SwiftUI helpers that build the three type roles the design artifact
/// prescribes. `display` (Press Start 2P) for `[ SYSTEM ]` labels,
/// `body` (VT323) for filenames/counts, `caption` (Silkscreen) for
/// micro captions and keycap labels. Fallbacks are handled inside
/// `PixelDesign.Font.face`.
enum RunicText {
    static func display(_ text: String, size: CGFloat = 10, color: Color = PixelDesign.Palette.white) -> some View {
        Text(text)
            .font(PixelDesign.Font.face(.display, size: size))
            .foregroundColor(color)
    }

    static func body(_ text: String, size: CGFloat = 16, color: Color = PixelDesign.Palette.white) -> some View {
        Text(text)
            .font(PixelDesign.Font.face(.body, size: size))
            .foregroundColor(color)
    }

    static func caption(_ text: String, size: CGFloat = 10, bold: Bool = false, color: Color = PixelDesign.Palette.whiteDim) -> some View {
        Text(text)
            .font(PixelDesign.Font.face(bold ? .captionBold : .caption, size: size))
            .foregroundColor(color)
            .textCase(.uppercase)
    }
}
