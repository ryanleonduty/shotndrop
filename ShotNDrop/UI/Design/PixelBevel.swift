import SwiftUI

/// Chunky pixel-language bevel used on the slot interior and, in Phase 3,
/// on tray rows. Two-tone hairline with palette-token colors — never a
/// smooth gradient.
struct PixelBevel: ViewModifier {
    enum Tone: Equatable {
        case idle
        case hover
        case success
        case danger
        case holding
    }

    let tone: Tone

    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .strokeBorder(borderColor, lineWidth: PixelDesign.Geometry.slotBorderWidth)
            )
    }

    private var borderColor: Color {
        switch tone {
        case .idle: return PixelDesign.Palette.cyanDim
        case .holding: return PixelDesign.Palette.cyan
        case .hover: return PixelDesign.Palette.cyan
        case .success: return PixelDesign.Palette.gold
        case .danger: return PixelDesign.Palette.danger
        }
    }
}

extension View {
    func pixelBevel(_ tone: PixelBevel.Tone) -> some View {
        modifier(PixelBevel(tone: tone))
    }
}
