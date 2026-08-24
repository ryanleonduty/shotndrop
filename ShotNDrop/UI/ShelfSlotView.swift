import SwiftUI

/// The 96×96 pt pixel slot. Renders every documented state via
/// `PixelDesign` primitives — palette tokens, corner brackets, chunky bevel,
/// scanline overlay, ambient pulse hint, gold/red flashes. Ambient pulse
/// itself is a lightweight `TimelineView` (steps of 4 per period, phase
/// aware). Reduced Motion collapses the pulse to a static frame.
struct ShelfSlotView: View {
    enum State: Equatable {
        case idleEmpty(count: Int)
        case idleHolding(count: Int, topPeek: NSImage?)
        case dragHover(hadItems: Bool)
        case pending(count: Int)
        case dropSuccess(count: Int)
        case postConsume(count: Int)
        case rejection(RejectionReason)
    }

    enum RejectionReason: Equatable {
        case shelfFull
        case duplicate
        case unavailable

        var label: String {
            switch self {
            case .shelfFull: return "— SHELF FULL —"
            case .duplicate: return "— DUPLICATE —"
            case .unavailable: return "— UNAVAILABLE —"
            }
        }
    }

    let state: State

    @StateObject private var reducedMotion = PixelDesign.ReducedMotion.shared

    var body: some View {
        ZStack {
            PixelDesign.Palette.midnight

            // Peek content — only visible when we're holding something.
            if case let .idleHolding(_, peek) = state, let peek {
                Image(nsImage: peek)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: PixelDesign.Geometry.slotSize - 4,
                           height: PixelDesign.Geometry.slotSize - 4)
                    .clipped()
                    .overlay(scanlineOverlay(opacity: 0.04))
            } else if case .dropSuccess = state {
                Rectangle().fill(PixelDesign.Palette.gold.opacity(0.28))
            } else if case .rejection = state {
                Rectangle().fill(PixelDesign.Palette.danger.opacity(0.22))
            } else if case .dragHover = state {
                scanlineOverlay(opacity: 0.10)
            } else if case .pending = state {
                Rectangle().fill(PixelDesign.Palette.cyanDim.opacity(0.20))
            }

            centerGlyph
            countBadge
            overlayLabel
        }
        .frame(width: PixelDesign.Geometry.slotSize, height: PixelDesign.Geometry.slotSize)
        .pixelBevel(bevelTone)
        .overlay(
            CornerBracketsView(style: bracketStyle, ambientPulse: shouldAmbientPulse)
                .environmentObject(reducedMotion)
        )
    }

    // MARK: derived

    private var bevelTone: PixelBevel.Tone {
        switch state {
        case .dragHover: return .hover
        case .dropSuccess: return .success
        case .rejection: return .danger
        case .idleHolding, .pending, .postConsume: return .holding
        case .idleEmpty: return .idle
        }
    }

    private var bracketStyle: CornerBracketsView.Style {
        switch state {
        case .dragHover: return .hover
        case .dropSuccess: return .success
        case .rejection: return .danger
        default: return .idle
        }
    }

    private var shouldAmbientPulse: Bool {
        switch state {
        case .idleEmpty, .idleHolding: return !reducedMotion.isReduced
        default: return false
        }
    }

    // MARK: glyphs

    @ViewBuilder
    private var centerGlyph: some View {
        switch state {
        case .idleEmpty:
            Text("◧")
                .font(PixelDesign.Font.face(.display, size: 18))
                .foregroundColor(PixelDesign.Palette.cyanDim)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var countBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if !hidesBadge {
                    Text(countText)
                        .font(PixelDesign.Font.face(.body, size: 12))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(PixelDesign.Palette.midnight.opacity(0.75))
                }
            }
        }
    }

    private var hidesBadge: Bool {
        if case .dragHover = state { return true }
        if case .rejection = state { return true }
        return false
    }

    private var badgeColor: Color {
        if case .idleEmpty = state { return PixelDesign.Palette.whiteDim }
        return PixelDesign.Palette.cyan
    }

    private var countText: String {
        switch state {
        case let .idleEmpty(count),
             let .idleHolding(count, _),
             let .pending(count),
             let .dropSuccess(count),
             let .postConsume(count):
            return "×\(count)/\(ShelfInventory.capacity)"
        default:
            return ""
        }
    }

    @ViewBuilder
    private var overlayLabel: some View {
        switch state {
        case .dragHover:
            VStack {
                Text("DROP ITEM")
                    .font(PixelDesign.Font.face(.display, size: 9))
                    .foregroundColor(PixelDesign.Palette.cyan)
                    .padding(.top, 6)
                Spacer()
            }
        case .dropSuccess:
            VStack {
                Text("ACQUIRED")
                    .font(PixelDesign.Font.face(.display, size: 9))
                    .foregroundColor(PixelDesign.Palette.gold)
                    .padding(.top, 6)
                Spacer()
            }
        case .postConsume:
            Text("— CONSUMED")
                .font(PixelDesign.Font.face(.caption, size: 9))
                .foregroundColor(PixelDesign.Palette.whiteDim)
        case .pending:
            Text("…")
                .font(PixelDesign.Font.face(.body, size: 20))
                .foregroundColor(PixelDesign.Palette.whiteDim)
        case let .rejection(reason):
            Text(reason.label)
                .font(PixelDesign.Font.face(.captionBold, size: 9))
                .foregroundColor(PixelDesign.Palette.danger)
        default:
            EmptyView()
        }
    }

    // MARK: scanline overlay

    @ViewBuilder
    private func scanlineOverlay(opacity: Double) -> some View {
        GeometryReader { proxy in
            Canvas { context, size in
                var y: CGFloat = 0
                let step: CGFloat = 2
                let color = PixelDesign.Palette.cyan.opacity(opacity)
                while y < size.height {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(color))
                    y += step
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}
