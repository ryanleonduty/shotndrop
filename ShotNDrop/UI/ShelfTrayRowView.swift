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

            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)
                        .background(PixelDesign.Palette.midnight)
                        .overlay {
                            PixelCartridgeBorder()
                                .stroke(PixelDesign.Palette.cyanDim, lineWidth: 2)
                                .shadow(color: PixelDesign.Palette.void, radius: 0, x: 3, y: 3)
                        }
                }
                .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)

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
        .overlay {
            PixelCartridgeBorder()
                .stroke(PixelDesign.Palette.rune2, lineWidth: 1)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
        }
        .overlay(alignment: .topLeading) {
            RankStripe(rank: rank)
                .padding(.leading, 8)
                .padding(.top, 6)
        }
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

/// Stepped corners keep the shelf tile in the app's pixel-art visual language.
private struct PixelCartridgeBorder: Shape {
    private let step: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let right = rect.maxX
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: x + step, y: y))
        path.addLine(to: CGPoint(x: right - step, y: y))
        path.addLine(to: CGPoint(x: right - step, y: y + step))
        path.addLine(to: CGPoint(x: right, y: y + step))
        path.addLine(to: CGPoint(x: right, y: bottom - step))
        path.addLine(to: CGPoint(x: right - step, y: bottom - step))
        path.addLine(to: CGPoint(x: right - step, y: bottom))
        path.addLine(to: CGPoint(x: x + step, y: bottom))
        path.addLine(to: CGPoint(x: x + step, y: bottom - step))
        path.addLine(to: CGPoint(x: x, y: bottom - step))
        path.addLine(to: CGPoint(x: x, y: y + step))
        path.addLine(to: CGPoint(x: x + step, y: y + step))
        path.closeSubpath()
        return path
    }
}
