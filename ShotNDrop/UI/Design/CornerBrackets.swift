import SwiftUI

/// Four `L`-shaped corner brackets that sit outside the slot rect. Idle
/// variant uses cyan-dim; hover extends length and offset and switches to
/// full cyan; success/danger override the color. Pure Shape → clean pixel
/// edges at 1x/2x.
struct CornerBracketsView: View {
    enum Style: Equatable {
        case idle
        case hover
        case success
        case danger
    }

    let style: Style
    let ambientPulse: Bool

    @EnvironmentObject private var reducedMotion: PixelDesign.ReducedMotion

    var body: some View {
        TimelineView(.animation) { context in
            let phase = pulsePhase(at: context.date)
            drawCanvas(pulsePhase: phase)
        }
    }

    /// 4-step opacity ramp over `PixelDesign.Motion.ambientPulsePeriod`.
    /// Reduced Motion pins to 1.0 (steady, no animation).
    private func pulsePhase(at date: Date) -> Double {
        guard ambientPulse, !reducedMotion.isReduced else { return 1.0 }
        let period = PixelDesign.Motion.ambientPulsePeriod
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        let step = Int((t / period) * 4) % 4
        // Stepped opacity: bright → dim → bright → mid
        switch step {
        case 0: return 1.00
        case 1: return 0.55
        case 2: return 0.90
        default: return 0.75
        }
    }

    @ViewBuilder
    private func drawCanvas(pulsePhase: Double) -> some View {
        Canvas { context, size in
            let color = strokeColor(reducedIntensity: false).opacity(pulsePhase)
            let bracketLen = length
            let offset = self.offset
            let lineWidth: CGFloat = PixelDesign.Geometry.slotBorderWidth

            let rect = CGRect(origin: .zero, size: size)

            // Top-left
            context.stroke(bracketPath(at: CGPoint(x: rect.minX - offset, y: rect.minY - offset),
                                       horizontal: bracketLen,
                                       vertical: bracketLen),
                           with: .color(color), lineWidth: lineWidth)
            // Top-right
            context.stroke(bracketPath(at: CGPoint(x: rect.maxX + offset, y: rect.minY - offset),
                                       horizontal: -bracketLen,
                                       vertical: bracketLen),
                           with: .color(color), lineWidth: lineWidth)
            // Bottom-left
            context.stroke(bracketPath(at: CGPoint(x: rect.minX - offset, y: rect.maxY + offset),
                                       horizontal: bracketLen,
                                       vertical: -bracketLen),
                           with: .color(color), lineWidth: lineWidth)
            // Bottom-right
            context.stroke(bracketPath(at: CGPoint(x: rect.maxX + offset, y: rect.maxY + offset),
                                       horizontal: -bracketLen,
                                       vertical: -bracketLen),
                           with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
    // Note: end of drawCanvas below is auto-closed by the outer body wrapper.

    private var length: CGFloat {
        switch style {
        case .hover: return PixelDesign.Geometry.bracketLengthHover
        default: return PixelDesign.Geometry.bracketLength
        }
    }

    private var offset: CGFloat {
        switch style {
        case .hover: return PixelDesign.Geometry.bracketOffsetHover
        default: return PixelDesign.Geometry.bracketOffsetIdle
        }
    }

    private func strokeColor(reducedIntensity: Bool) -> Color {
        switch style {
        case .idle: return PixelDesign.Palette.cyanDim
        case .hover: return PixelDesign.Palette.cyan
        case .success: return PixelDesign.Palette.gold
        case .danger: return PixelDesign.Palette.danger
        }
    }

    private func bracketPath(at corner: CGPoint, horizontal: CGFloat, vertical: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: corner.x + horizontal, y: corner.y))
        path.addLine(to: corner)
        path.addLine(to: CGPoint(x: corner.x, y: corner.y + vertical))
        return path
    }
}
