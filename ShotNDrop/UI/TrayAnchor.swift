import Foundation
import CoreGraphics

/// Pure enum + resolver used to pick the tray-open corner that keeps the
/// tray inside `screenFrame`. Priority: `belowTrailing` → `belowLeading` →
/// `aboveTrailing` → `aboveLeading`; degrade to `belowTrailing` if none fit.
public enum TrayAnchor: Sendable, Equatable, CaseIterable {
    case belowTrailing
    case belowLeading
    case aboveTrailing
    case aboveLeading

    public static func resolve(
        slotFrame: CGRect,
        screenFrame: CGRect,
        traySize: CGSize
    ) -> TrayAnchor {
        for candidate in [Self.belowTrailing, .belowLeading, .aboveTrailing, .aboveLeading] {
            let origin = candidate.origin(slotFrame: slotFrame, traySize: traySize)
            let frame = CGRect(origin: origin, size: traySize)
            if screenFrame.contains(frame) { return candidate }
        }
        return .belowTrailing
    }

    public func origin(slotFrame: CGRect, traySize: CGSize) -> CGPoint {
        switch self {
        case .belowTrailing:
            return CGPoint(x: slotFrame.maxX - traySize.width, y: slotFrame.minY - traySize.height)
        case .belowLeading:
            return CGPoint(x: slotFrame.minX, y: slotFrame.minY - traySize.height)
        case .aboveTrailing:
            return CGPoint(x: slotFrame.maxX - traySize.width, y: slotFrame.maxY)
        case .aboveLeading:
            return CGPoint(x: slotFrame.minX, y: slotFrame.maxY)
        }
    }
}
