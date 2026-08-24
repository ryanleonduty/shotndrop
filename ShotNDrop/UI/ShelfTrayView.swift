import SwiftUI
import AppKit

/// Hunter-inventory tray. Header + footer sit outside the scroll region so
/// pixel chrome does not scroll. Row list is capped to
/// `0.6 × visibleFrame.height`. Rows use `.onDrag` with a file
/// representation that invokes the consume callback once the drop resolves.
struct ShelfTrayView: View {
    let payloads: [ShelfMediaPayload]
    let maxHeight: CGFloat
    let onRowDragConsumed: (UUID) -> Void
    let onEscape: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ShelfTrayHeaderView(count: payloads.count)
            if payloads.isEmpty {
                emptyBody
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(payloads.enumerated()), id: \.element.id) { index, payload in
                            ShelfTrayRowView(
                                rank: index + 1,
                                payload: payload,
                                onDragConsumed: { onRowDragConsumed(payload.id) }
                            )
                        }
                    }
                }
                .frame(maxHeight: maxHeight)
            }
            ShelfTrayFooterView()
        }
        .frame(width: PixelDesign.Geometry.trayWidth)
        .background(PixelDesign.Palette.midnight)
        .overlay(alignment: .topLeading) { trayCornerBracket(rotation: 0) }
        .overlay(alignment: .topTrailing) { trayCornerBracket(rotation: 90) }
        .background(EscKeyCatcher(onEscape: onEscape))
    }

    private var emptyBody: some View {
        Text("EMPTY")
            .font(PixelDesign.Font.face(.caption, size: 10))
            .foregroundColor(PixelDesign.Palette.whiteDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(PixelDesign.Palette.midnight)
    }

    @ViewBuilder
    private func trayCornerBracket(rotation: Double) -> some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 10))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 10, y: 0))
            context.stroke(path, with: .color(PixelDesign.Palette.cyan), lineWidth: 2)
        }
        .frame(width: 12, height: 12)
        .rotationEffect(.degrees(rotation))
        .padding(4)
        .allowsHitTesting(false)
    }
}

struct EscKeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onEscape = onEscape
    }

    final class KeyCatcherView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onEscape?()
                return
            }
            super.keyDown(with: event)
        }
    }
}
