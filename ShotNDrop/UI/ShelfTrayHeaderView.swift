import SwiftUI

/// Header row of the shelf. Also serves as the standalone minimized surface:
/// same pixel chrome, but with corner brackets and state-aware coloring so
/// wake/drop-success/rejection remain legible when the tray is collapsed.
struct ShelfTrayHeaderView: View {
    let count: Int
    let slotState: ShelfSlotView.State
    let minimized: Bool

    @StateObject private var reducedMotion = PixelDesign.ReducedMotion.shared

    var body: some View {
        HStack {
            if let stateText = stateLabel {
                Text(stateText.text)
                    .font(PixelDesign.Font.face(stateText.role, size: stateText.size))
                    .foregroundColor(stateText.color)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("[ INVENTORY ]")
                    .font(PixelDesign.Font.face(.display, size: 10))
                    .foregroundColor(labelColor)
                Spacer()
                countChip
            }
        }
        .frame(height: PixelDesign.Geometry.trayHeaderHeight)
        .padding(.horizontal, 10)
        .background(background)
        .overlay(alignment: .bottom) {
            if !minimized {
                Rectangle().fill(PixelDesign.Palette.cyanDim).frame(height: 1)
            }
        }
        .overlay(
            CornerBracketsView(style: bracketStyle, ambientPulse: shouldAmbientPulse)
                .environmentObject(reducedMotion)
        )
        .animation(.easeInOut(duration: 0.35), value: slotState)
        .animation(.easeInOut(duration: 0.20), value: count)
    }

    /// Non-nil during transient states — the whole header renders as this
    /// label (centered) instead of `[ INVENTORY ] N/20`, so the state
    /// message doesn't collide with the static header.
    private var stateLabel: (text: String, role: PixelDesign.Font.Role, size: CGFloat, color: Color)? {
        switch slotState {
        case .dragHover:
            return ("DROP ITEM", .display, 10, PixelDesign.Palette.cyan)
        case .dropSuccess:
            return ("ACQUIRED", .display, 10, PixelDesign.Palette.gold)
        case let .rejection(reason):
            return (reason.label, .captionBold, 9, PixelDesign.Palette.danger)
        case .pending:
            return ("…", .body, 16, PixelDesign.Palette.whiteDim)
        default:
            return nil
        }
    }

    private var countChip: some View {
        Text("\(count) / \(ShelfInventory.capacity)")
            .font(PixelDesign.Font.face(.body, size: 16))
            .foregroundColor(countColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(PixelDesign.Palette.rune)
    }

    private var background: some View {
        Group {
            switch slotState {
            case .dropSuccess:
                PixelDesign.Palette.gold.opacity(0.20)
            case .rejection:
                PixelDesign.Palette.danger.opacity(0.20)
            case .dragHover:
                PixelDesign.Palette.cyan.opacity(0.10)
            default:
                PixelDesign.Palette.midnight
            }
        }
    }

    private var labelColor: Color {
        switch slotState {
        case .dropSuccess: return PixelDesign.Palette.gold
        case .rejection: return PixelDesign.Palette.danger
        default: return PixelDesign.Palette.white
        }
    }

    private var countColor: Color {
        switch slotState {
        case .dropSuccess: return PixelDesign.Palette.gold
        case .rejection: return PixelDesign.Palette.danger
        default: return PixelDesign.Palette.cyan
        }
    }

    private var bracketStyle: CornerBracketsView.Style {
        switch slotState {
        case .dragHover: return .hover
        case .dropSuccess: return .success
        case .rejection: return .danger
        default: return .idle
        }
    }

    private var shouldAmbientPulse: Bool {
        switch slotState {
        case .idleEmpty, .idleHolding: return !reducedMotion.isReduced
        default: return false
        }
    }

}
