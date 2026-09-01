import SwiftUI

/// Compact pixel chip used as the shelf's minimized surface. Renders the
/// current count inside pixel corner brackets with state-aware color
/// feedback (hover cyan, drop-success gold, rejection red). Approximately
/// 60 × 32pt.
struct ShelfChipView: View {
    let count: Int
    let slotState: ShelfSlotView.State

    @StateObject private var reducedMotion = PixelDesign.ReducedMotion.shared

    var body: some View {
        ZStack {
            background
                .transition(.opacity)
            if let stateLabel = Self.stateLabel(for: slotState) {
                Text(stateLabel)
                    .font(PixelDesign.Font.face(.display, size: 9))
                    .foregroundColor(PixelDesign.Palette.cyan)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(spacing: 6) {
                    Text("[")
                        .font(PixelDesign.Font.face(.display, size: 15))
                        .foregroundColor(labelColor)
                    Text("\(count)")
                        .font(PixelDesign.Font.face(.body, size: 24))
                        .foregroundColor(countColor)
                        .contentTransition(.numericText())
                    Text("]")
                        .font(PixelDesign.Font.face(.display, size: 15))
                        .foregroundColor(labelColor)
                }
            }
        }
        .frame(width: PixelDesign.Geometry.chipWidth,
               height: PixelDesign.Geometry.chipHeight)
        .overlay(
            CornerBracketsView(style: bracketStyle, ambientPulse: shouldAmbientPulse)
                .environmentObject(reducedMotion)
        )
        .animation(.easeInOut(duration: 0.35), value: slotState)
        .animation(.easeInOut(duration: 0.20), value: count)
    }

    static func stateLabel(for state: ShelfSlotView.State) -> String? {
        if case .dragHover = state {
            return "DROP ITEM"
        }
        return nil
    }

    private var background: some View {
        ZStack {
            PixelDesign.Palette.midnight
            switch slotState {
            case .dropSuccess:
                Rectangle().fill(PixelDesign.Palette.gold.opacity(0.20))
            case .rejection:
                Rectangle().fill(PixelDesign.Palette.danger.opacity(0.10))
            case .dragHover:
                Rectangle().fill(PixelDesign.Palette.cyan.opacity(0.10))
            default:
                EmptyView()
            }
        }
    }

    private var labelColor: Color {
        switch slotState {
        case .dropSuccess: return PixelDesign.Palette.gold
        case .rejection: return PixelDesign.Palette.danger
        default: return PixelDesign.Palette.cyan
        }
    }

    private var countColor: Color {
        switch slotState {
        case .dropSuccess: return PixelDesign.Palette.gold
        case .rejection: return PixelDesign.Palette.danger
        default: return PixelDesign.Palette.white
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

    @ViewBuilder
    private var overlayLabel: some View {
        // Very compact overlay — no wide text; state color already
        // communicates hover/success/rejection.
        EmptyView()
    }
}
