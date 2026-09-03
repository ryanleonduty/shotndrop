import SwiftUI

/// Composed content of the single shelf panel. In `.minimized` mode the
/// container renders only the pixel `[ SHOTNDROP // INVENTORY ]` bar with
/// corner brackets and state-aware coloring — that bar IS the minimized
/// affordance (there is no separate 96×96 slot). Hover or click expands
/// the tray in place; on the way out, the container morphs back.
struct ShelfContainerView: View {
    enum Mode: Equatable {
        case minimized
        case expandedBelow
        case expandedAbove
    }

    let mode: Mode
    let slotState: ShelfSlotView.State
    let payloads: [ShelfMediaPayload]
    let maxTrayHeight: CGFloat
    let onRowDragConsumed: (UUID) -> Void
    let onEscape: () -> Void

    var body: some View {
        Group {
            switch mode {
            case .minimized:
                ShelfChipView(count: payloads.count, slotState: slotState)
                    .transition(.opacity)
            case .expandedBelow:
                VStack(spacing: 0) {
                    headerView
                    bodyView
                }
                .frame(width: PixelDesign.Geometry.trayWidth)
                .background(EscKeyCatcher(onEscape: onEscape))
                .transition(.opacity)
            case .expandedAbove:
                VStack(spacing: 0) {
                    bodyView
                    headerView
                }
                .frame(width: PixelDesign.Geometry.trayWidth)
                .background(EscKeyCatcher(onEscape: onEscape))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.20), value: mode)
    }

    private var headerView: some View {
        ShelfTrayHeaderView(
            count: payloads.count,
            slotState: slotState,
            minimized: mode == .minimized
        )
    }

    @ViewBuilder
    private var bodyView: some View {
        VStack(spacing: 0) {
            rowsBlock
            ShelfTrayFooterView()
        }
    }

    @ViewBuilder
    private var rowsBlock: some View {
        if payloads.isEmpty {
            Text("EMPTY")
                .font(PixelDesign.Font.face(.caption, size: 10))
                .foregroundColor(PixelDesign.Palette.whiteDim)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(PixelDesign.Palette.midnight)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(payloads.enumerated()), id: \.element.id) { index, payload in
                        ShelfTrayRowView(
                            rank: index + 1,
                            payload: payload,
                            onDragConsumed: { onRowDragConsumed(payload.id) }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: payloads.map(\.id))
                .background {
                    PixelScrollViewConfigurator()
                }
            }
            .frame(maxHeight: maxTrayHeight)
            .background(PixelDesign.Palette.midnight)
        }
    }
}

private struct PixelScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var ancestor: NSView? = nsView
            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    guard !(scrollView.verticalScroller is PixelScroller) else { return }
                    let scroller = PixelScroller()
                    scroller.scrollerStyle = .overlay
                    scrollView.verticalScroller = scroller
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

private final class PixelScroller: NSScroller {
    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard !knobRect.isEmpty else { return }
        NSColor(PixelDesign.Palette.cyan)
            .withAlphaComponent(0.92)
            .setFill()
        NSBezierPath(rect: knobRect).fill()
    }
}
