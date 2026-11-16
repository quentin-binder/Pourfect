import BottleSortCore
import SwiftUI

/// One band of liquid: a color and its height in layers (1 = a full layer, 0.5 = half drained),
/// plus the glyph `BottleView` shows on that layer, if any.
struct LiquidSegment {
    enum Glyph {
        /// "?" of a hidden layer.
        case hidden
        /// Key icon in the key's color.
        case key(Color)
    }

    var color: Color
    var fraction: CGFloat
    var glyph: Glyph? = nil
    /// Colorblind rune drawn on this layer. Unlike glyphs, runes don't stop a run of equal
    /// layers from merging into one band: they are drawn per layer, on top of the bands.
    var rune: Rune? = nil
}

/// Liquid inside a bottle whose surface stays level with the world while the bottle tilts.
///
/// Drawn in bottle space: `gravity` is the angle (radians) of "down" relative to the bottle's own
/// down axis — pass the bottle's tilt angle (plus any slosh). Each band keeps its area
/// (`fraction × layerHeight × width`); its boundaries are found by bisection on the area of the
/// bottle rectangle below a level line. At `gravity == 0` it matches the upright `BottleView`.
///
/// `rigidLayers` bottom layers don't move (D1: a frozen layer and everything under it): they are
/// drawn upright and level with the bottle whatever the tilt, and the free liquid above them
/// tilts in the space that is left.
struct TiltedLiquid: View {
    let segments: [LiquidSegment]   // bottom → top
    let layerHeight: CGFloat
    var gravity: Double = 0
    var rigidLayers = 0
    /// A pouring source's lip in bottle space (a narrower mouth, R7 flask shapes): with `lipReach`
    /// 1 the top surface rises to the lip, so the potion runs out of the mouth instead of stopping
    /// at the shoulder that the shape clips off (0 = the plain level surface).
    var lip: CGPoint? = nil
    var lipReach: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let rigid = min(max(rigidLayers, 0), segments.count)
            let pinned = Array(segments.prefix(rigid))
            let free = Array(segments.dropFirst(rigid))
            let rigidHeight = pinned.reduce(CGFloat(0)) { $0 + $1.fraction * layerHeight }
            if !pinned.isEmpty {
                drawUpright(pinned, bottom: size.height, width: size.width,
                            overlapsTop: free.contains { $0.fraction > 0.001 }, in: context)
            }
            let rect = CGRect(x: 0, y: 0, width: size.width, height: max(0, size.height - rigidHeight))
            guard rect.height > 0.5 else { return }
            let down = CGPoint(x: sin(gravity), y: cos(gravity))
            let depth = { (p: CGPoint) in p.x * down.x + p.y * down.y }   // larger = lower
            let corners = Self.corners(of: rect)
            let deepest = corners.map(depth).max() ?? 0
            let highest = corners.map(depth).min() ?? 0

            var bottom = deepest + 1
            var area: CGFloat = 0
            let bands = Self.merged(free)
            let surfaceIndex = bands.lastIndex { $0.fraction > 0.001 }
            for (index, segment) in bands.enumerated() where segment.fraction > 0.001 {
                area += segment.fraction * layerHeight * size.width
                var top = Self.level(forArea: area, in: corners, depth: depth, range: highest...deepest)
                if index == surfaceIndex, let lip, lipReach > 0 {
                    // Up to (just over) the lip, never down.
                    let lipDepth = depth(lip) - 1
                    if top > lipDepth { top += (lipDepth - top) * min(lipReach, 1) }
                }
                // Overlap the next band by 1pt so no background seam shows between bands.
                let isTop = index == bands.count - 1
                var band = Self.clip(corners) { depth($0) - (isTop ? top : top - 1) }
                band = Self.clip(band) { bottom - depth($0) }
                if band.count >= 3 {
                    context.fill(Path { $0.addLines(band); $0.closeSubpath() },
                                 with: .style(segment.color.gradient))
                    if let glyph = segment.glyph {
                        drawGlyph(glyph, at: Self.center(of: band), size: layerHeight * min(segment.fraction, 1),
                                  in: context)
                    }
                }
                bottom = top
            }
            if free.contains(where: { $0.rune != nil }) {
                drawRunes(free, in: context, corners: corners, depth: depth, range: highest...deepest,
                          width: size.width)
            }
        }
    }

    /// The pinned bottom layers, level in the bottle's frame like `BottleView` draws them: runs of
    /// the same color share one band (and one gradient), glyphs and runes sit in each layer's middle.
    private func drawUpright(_ pinned: [LiquidSegment], bottom: CGFloat, width: CGFloat, overlapsTop: Bool,
                             in context: GraphicsContext) {
        var y = bottom
        let bands = Self.merged(pinned)
        for (index, segment) in bands.enumerated() {
            let h = segment.fraction * layerHeight
            // The top band reaches 1pt under the free liquid, so no seam shows.
            let extra: CGFloat = index < bands.count - 1 || overlapsTop ? 1 : 0
            let rect = CGRect(x: 0, y: y - h - extra, width: width, height: h + extra)
            context.fill(Path(rect), with: .style(segment.color.gradient))
            if let glyph = segment.glyph {
                drawGlyph(glyph, at: CGPoint(x: width / 2, y: y - h / 2), size: layerHeight * min(segment.fraction, 1),
                          in: context)
            }
            y -= h
        }
        y = bottom
        for segment in pinned {
            let h = segment.fraction * layerHeight
            if let rune = segment.rune, segment.fraction > 0.25 {
                let side = layerHeight * 0.5 * min(segment.fraction, 1)
                rune.draw(in: context, rect: CGRect(x: width / 2 - side / 2, y: y - h / 2 - side / 2,
                                                    width: side, height: side))
            }
            y -= h
        }
    }

    /// One rune per layer (also inside merged bands), at the center of that layer's own slice,
    /// the same size as `BottleView`'s; it shrinks with a draining or filling layer.
    private func drawRunes(_ segments: [LiquidSegment], in context: GraphicsContext, corners: [CGPoint],
                           depth: (CGPoint) -> CGFloat, range: ClosedRange<CGFloat>, width: CGFloat) {
        var bottom = range.upperBound + 1
        var area: CGFloat = 0
        for segment in segments where segment.fraction > 0.001 {
            area += segment.fraction * layerHeight * width
            let top = Self.level(forArea: area, in: corners, depth: depth, range: range)
            if let rune = segment.rune, segment.fraction > 0.25 {
                var slice = Self.clip(corners) { depth($0) - top }
                slice = Self.clip(slice) { bottom - depth($0) }
                if slice.count >= 3 {
                    let center = Self.center(of: slice)
                    let side = layerHeight * 0.5 * min(segment.fraction, 1)
                    rune.draw(in: context, rect: CGRect(x: center.x - side / 2, y: center.y - side / 2,
                                                        width: side, height: side))
                }
            }
            bottom = top
        }
    }

    /// Same glyphs as `BottleView`'s layers, drawn upright in bottle space (they tilt with the bottle).
    private func drawGlyph(_ glyph: LiquidSegment.Glyph, at point: CGPoint, size: CGFloat, in context: GraphicsContext) {
        var context = context
        context.translateBy(x: point.x, y: point.y)
        switch glyph {
        case .hidden:
            let text = Text(verbatim: "?")
                .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            context.draw(context.resolve(text), at: .zero)
        case .key(let color):
            context.rotate(by: .degrees(-45))
            let icon = Text(Image(systemName: "key.fill"))
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(color)
            context.draw(context.resolve(icon), at: .zero)
        }
    }

    /// Joins consecutive glyph-less segments of the same color into one band, so a run of equal
    /// layers shares one gradient (like `BottleView`'s runs). Glyph segments stay separate.
    private static func merged(_ segments: [LiquidSegment]) -> [LiquidSegment] {
        var out: [LiquidSegment] = []
        for segment in segments where segment.fraction > 0.001 {
            if segment.glyph == nil, let last = out.last, last.glyph == nil, last.color == segment.color {
                out[out.count - 1].fraction += segment.fraction
            } else {
                out.append(segment)
            }
        }
        return out
    }

    // MARK: Geometry

    /// Average of the polygon's corners: inside a convex band, good enough to place a glyph.
    private static func center(of polygon: [CGPoint]) -> CGPoint {
        let n = CGFloat(polygon.count)
        return CGPoint(x: polygon.map(\.x).reduce(0, +) / n, y: polygon.map(\.y).reduce(0, +) / n)
    }

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
