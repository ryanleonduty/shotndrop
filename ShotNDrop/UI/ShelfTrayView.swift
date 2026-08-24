import SwiftUI
import AppKit

/// ESC catcher used by `ShelfContainerView` when it's expanded. Kept in
/// this file (originally the home of `ShelfTrayView`) so ESC handling has
/// a stable place after the container refactor.
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
