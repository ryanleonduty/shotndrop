import SwiftUI
import AppKit

/// Vertical inventory tile — thumbnail on top, filename + stats stacked
/// below. Rank stripe hugs the left edge, drag handle on the right.
struct ShelfTrayRowView: View {
    let rank: Int
    let payload: ShelfMediaPayload
    let onDragConsumed: () -> Void

    private var thumbnail: NSImage {
        ShelfThumbnailer.shared.thumbnail(for: payload)
            ?? NSImage(size: NSSize(width: 120, height: 80))
    }

    var body: some View {
        HStack(spacing: 8) {
            RankStripe(rank: rank)

            VStack(alignment: .leading, spacing: 4) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 80)
                    .background(PixelDesign.Palette.rune)
                    .pixelBevel(.idle)

                Text(payload.originalFilename)
                    .font(PixelDesign.Font.face(.body, size: 14))
                    .foregroundColor(PixelDesign.Palette.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statLine)
                    .font(PixelDesign.Font.face(.caption, size: 9))
                    .foregroundColor(PixelDesign.Palette.whiteDim)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DragHandleRune()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: PixelDesign.Geometry.trayRowHeight)
        .background(PixelDesign.Palette.rune)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PixelDesign.Palette.rune2).frame(height: 1)
        }
        .overlay(
            ShelfRowDragOverlay(payload: payload, onDragConsumed: onDragConsumed)
                .allowsHitTesting(true)
        )
    }

    private var statLine: String {
        let age = RelativeAge.format(from: payload.capturedAt)
        let dims: String
        if let d = payload.dimensions {
            dims = "\(d.width)×\(d.height)"
        } else {
            dims = "?"
        }
        let format = payload.utiIdentifier
            .split(separator: ".").last
            .map { String($0).uppercased() } ?? "IMG"
        return "\(age) · \(dims) · \(format)"
    }
}
