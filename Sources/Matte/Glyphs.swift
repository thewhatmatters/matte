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

    /// The run for one edge: out of the adjoining side, round the first corner,
    /// along the edge, round the second, and out again. Matches the design's
    /// two-corners-per-edge treatment.
    static func edgePath(_ edge: EdgePadding.Edge) -> Path {
        let near: CGFloat = 1.5, far: CGFloat = 10.5, stub: CGFloat = 3.5, radius: CGFloat = 1
        var path = Path()
        switch edge {
        case .top:
            path.move(to: CGPoint(x: near, y: stub))
            path.addArc(tangent1End: CGPoint(x: near, y: near), tangent2End: CGPoint(x: far, y: near), radius: radius)
            path.addArc(tangent1End: CGPoint(x: far, y: near), tangent2End: CGPoint(x: far, y: stub), radius: radius)
            path.addLine(to: CGPoint(x: far, y: stub))
        case .right:
            path.move(to: CGPoint(x: far - stub + near, y: near))
            path.addArc(tangent1End: CGPoint(x: far, y: near), tangent2End: CGPoint(x: far, y: far), radius: radius)
            path.addArc(tangent1End: CGPoint(x: far, y: far), tangent2End: CGPoint(x: far - stub + near, y: far), radius: radius)
            path.addLine(to: CGPoint(x: far - stub + near, y: far))
        case .bottom:
            path.move(to: CGPoint(x: near, y: far - stub + near))
            path.addArc(tangent1End: CGPoint(x: near, y: far), tangent2End: CGPoint(x: far, y: far), radius: radius)
            path.addArc(tangent1End: CGPoint(x: far, y: far), tangent2End: CGPoint(x: far, y: far - stub + near), radius: radius)
            path.addLine(to: CGPoint(x: far, y: far - stub + near))
        case .left:
            path.move(to: CGPoint(x: stub, y: near))
            path.addArc(tangent1End: CGPoint(x: near, y: near), tangent2End: CGPoint(x: near, y: far), radius: radius)
            path.addArc(tangent1End: CGPoint(x: near, y: far), tangent2End: CGPoint(x: stub, y: far), radius: radius)
            path.addLine(to: CGPoint(x: stub, y: far))
        }
        return path
    }

    /// The two corners an edge does not touch, kept faint for context.
    static func oppositeCorners(_ edge: EdgePadding.Edge) -> [Corner] {
        switch edge {
        case .top: return [.bottomLeft, .bottomRight]
        case .bottom: return [.topLeft, .topRight]
        case .left: return [.topRight, .bottomRight]
        case .right: return [.topLeft, .bottomLeft]
        }
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

/// One edge lit through both of its corners, with the opposite pair faint —
/// the design's per-field mark.
struct EdgeGlyph: View {
    let edge: EdgePadding.Edge

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 12
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let style = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)

            for corner in Glyph.oppositeCorners(edge) {
                context.stroke(Glyph.cornerPath(corner).applying(transform),
                               with: .color(.white.opacity(0.10)), style: style)
            }
            context.stroke(Glyph.edgePath(edge).applying(transform),
                           with: .color(.white), style: style)
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
