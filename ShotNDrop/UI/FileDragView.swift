import SwiftUI
import AppKit

/// SwiftUI wrapper that hosts SwiftUI `content` inside an AppKit view that
/// begins an existing-file `NSDraggingSession` with `.copy`. The session owns
/// an immutable URL/thumbnail payload independent of any queue lifecycle.
public struct FileDragView<Content: View>: NSViewRepresentable {
    public let url: URL
    public let content: Content

    public init(url: URL, @ViewBuilder content: () -> Content) {
        self.url = url
        self.content = content()
    }

    public func makeNSView(context: Context) -> DragHostingView<Content> {
        let host = DragHostingView(url: url, rootView: content)
        return host
    }

    public func updateNSView(_ nsView: DragHostingView<Content>, context: Context) {
        nsView.update(url: url, rootView: content)
    }
}

public final class DragHostingView<Content: View>: NSView, NSDraggingSource {
    private var payloadURL: URL
    private let hosting: NSHostingView<Content>
    private var mouseDownEvent: NSEvent?

    init(url: URL, rootView: Content) {
        self.payloadURL = url
        self.hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        self.hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layout() {
        super.layout()
        hosting.frame = bounds
    }

    func update(url: URL, rootView: Content) {
        self.payloadURL = url
        self.hosting.rootView = rootView
    }

    // MARK: - Drag source

    override public func mouseDown(with event: NSEvent) {
        self.mouseDownEvent = event
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = convert(down.locationInWindow, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        let threshold: CGFloat = 4
        let dx = current.x - start.x
        let dy = current.y - start.y
        guard hypot(dx, dy) >= threshold else { return }

        // Session-owned immutable payload: snapshot the URL now.
        let url = payloadURL
        let image = NSImage(contentsOf: url) ?? NSImage(size: .init(width: 32, height: 32))
        // Primary representation: file URL (Finder, Slack file targets).
        let urlItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        // Compatible representation: image bytes for readers that want pixels.
        let imageItem = NSDraggingItem(pasteboardWriter: image)

        let dragOrigin = current
        let frame = CGRect(
            origin: CGPoint(x: dragOrigin.x - 32, y: dragOrigin.y - 24),
            size: CGSize(width: 64, height: 48)
        )
        urlItem.setDraggingFrame(frame, contents: image)
        imageItem.setDraggingFrame(frame, contents: image)

        beginDraggingSession(with: [urlItem, imageItem], event: down, source: self)
        self.mouseDownEvent = nil
    }

    override public func mouseUp(with event: NSEvent) {
        self.mouseDownEvent = nil
    }

    public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return .copy
    }
}
