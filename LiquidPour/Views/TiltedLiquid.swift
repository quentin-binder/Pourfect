import BottleSortCore
import SwiftUI

/// One band of liquid: a color and its height in layers (1 = a full layer, 0.5 = half drained).
struct LiquidSegment {
    var color: Color
    var fraction: CGFloat
}

extension Layer {
    /// Display color of a layer (gray for layer kinds that have no color).
    var liquidColor: Color { colorID.map { Palette.color($0.rawValue) } ?? .gray }
}

/// Liquid inside a bottle whose surface stays level with the world while the bottle tilts.
///
/// Drawn in bottle space: `gravity` is the angle (radians) of "down" relative to the bottle's own
/// down axis — pass the bottle's tilt angle (plus any slosh). Each band keeps its area
/// (`fraction × layerHeight × width`); its boundaries are found by bisection on the area of the
/// bottle rectangle below a level line. At `gravity == 0` it matches the upright `BottleView`.
struct TiltedLiquid: View {
    let segments: [LiquidSegment]   // bottom → top
    let layerHeight: CGFloat
    var gravity: Double = 0

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let down = CGPoint(x: sin(gravity), y: cos(gravity))
            let depth = { (p: CGPoint) in p.x * down.x + p.y * down.y }   // larger = lower
            let corners = Self.corners(of: rect)
            let deepest = corners.map(depth).max() ?? 0
            let highest = corners.map(depth).min() ?? 0

            var bottom = deepest + 1
            var area: CGFloat = 0
            for (index, segment) in segments.enumerated() where segment.fraction > 0.001 {
                area += segment.fraction * layerHeight * size.width
                let top = Self.level(forArea: area, in: corners, depth: depth, range: highest...deepest)
                // Overlap the next band by 1pt so no background seam shows between bands.
                let isTop = index == segments.count - 1
                var band = Self.clip(corners) { depth($0) - (isTop ? top : top - 1) }
                band = Self.clip(band) { bottom - depth($0) }
                if band.count >= 3 {
                    context.fill(Path { $0.addLines(band); $0.closeSubpath() },
                                 with: .style(segment.color.gradient))
                }
                bottom = top
            }
        }
    }

    // MARK: Geometry

    private static func corners(of r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    /// Level line (depth value) under which the polygon holds `area`.
    private static func level(forArea area: CGFloat, in polygon: [CGPoint],
                              depth: (CGPoint) -> CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        var low = range.lowerBound, high = range.upperBound   // low = surface high up (more area)
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if self.area(clip(polygon) { depth($0) - mid }) > area { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    /// Keeps the part of a convex polygon where `side(p) >= 0` (Sutherland–Hodgman, one edge).
    private static func clip(_ polygon: [CGPoint], side: (CGPoint) -> CGFloat) -> [CGPoint] {
        guard !polygon.isEmpty else { return [] }
        var out: [CGPoint] = []
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let sa = side(a), sb = side(b)
            if sa >= 0 { out.append(a) }
            if (sa >= 0) != (sb >= 0) {
                let t = sa / (sa - sb)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out
    }

    private static func area(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}
