import SwiftUI

/// The design's icons, reproduced from the Paper file's SVG paths rather than
/// substituted with SF Symbols. All are drawn in a 12×12 box.
enum Glyph {
    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// One corner bracket: a line in, a 1pt rounded turn, a line out.
    static func cornerPath(_ corner: Corner) -> Path {
        var path = Path()
        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: 1.5, y: 3.5))
            path.addArc(tangent1End: CGPoint(x: 1.5, y: 1.5),
                        tangent2End: CGPoint(x: 3.5, y: 1.5), radius: 1)
            path.addLine(to: CGPoint(x: 3.5, y: 1.5))
        case .topRight:
            path.move(to: CGPoint(x: 8.5, y: 1.5))
            path.addArc(tangent1End: CGPoint(x: 10.5, y: 1.5),
                        tangent2End: CGPoint(x: 10.5, y: 3.5), radius: 1)
            path.addLine(to: CGPoint(x: 10.5, y: 3.5))
        case .bottomRight:
            path.move(to: CGPoint(x: 10.5, y: 8.5))
            path.addArc(tangent1End: CGPoint(x: 10.5, y: 10.5),
                        tangent2End: CGPoint(x: 8.5, y: 10.5), radius: 1)
            path.addLine(to: CGPoint(x: 8.5, y: 10.5))
        case .bottomLeft:
            path.move(to: CGPoint(x: 3.5, y: 10.5))
            path.addArc(tangent1End: CGPoint(x: 1.5, y: 10.5),
                        tangent2End: CGPoint(x: 1.5, y: 8.5), radius: 1)
            path.addLine(to: CGPoint(x: 1.5, y: 8.5))
        }
        return path
    }

    /// The circular-arrow reset mark.
    static var resetPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 1.5, y: 6))
        path.addArc(center: CGPoint(x: 6, y: 6), radius: 4.5,
                    startAngle: .degrees(180), endAngle: .degrees(150),
                    clockwise: false)
        var tick = Path()
        tick.move(to: CGPoint(x: 1.5, y: 1.5))
        tick.addLine(to: CGPoint(x: 1.5, y: 4))
        tick.addLine(to: CGPoint(x: 4, y: 4))
        path.addPath(tick)
        return path
    }
}

/// All four corner brackets, with `lit` drawn at full strength and the rest at
/// 10% — the design's per-field glyph.
struct CornerGlyph: View {
    /// nil lights every corner, which is the expand button's state.
    var lit: Glyph.Corner?

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 12
            for corner in Glyph.Corner.allCases {
                let isLit = lit == nil || lit == corner
                let path = Glyph.cornerPath(corner)
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                context.stroke(path,
                               with: .color(.white.opacity(isLit ? 1 : 0.10)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

struct ResetGlyph: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 12
            context.stroke(Glyph.resetPath.applying(CGAffineTransform(scaleX: scale, y: scale)),
                           with: .color(.white),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
