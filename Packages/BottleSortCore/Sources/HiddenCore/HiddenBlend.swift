import Foundation

/// How an object is blended into the painting, ported from the art pipeline's `hocommon.py` (scene.json "render").
/// The app does the pixel work (Core Image / Core Graphics); the numbers and formulas live here.
public enum HiddenBlend {
    // MARK: Contact shadow (`shadow_for`)
    public static let shadowColor: (r: Int, g: Int, b: Int) = (40, 25, 15)
    /// Shadow alpha = object alpha × 0.38.
    public static let shadowAlpha = 0.38
    /// Gaussian blur σ (Pillow's `GaussianBlur(5)` radius is the standard deviation).
    public static let shadowBlur = 5.0
    public static let shadowPad = 16
    public static let shadowOffset: (x: Int, y: Int) = (5, 4)

    // MARK: Tint (`match_to_scene`)
    /// Gaussian blur σ applied to the tinted object (all four channels, straight alpha).
    public static let objectBlur = 0.35
    /// Saturation kept after tinting (toward the per-pixel grey = mean of r, g, b).
    public static let saturation = 0.85

    /// The colour transform for tint strength `t` toward `mean` (0–255 per channel):
    /// rgb·(1−t) + mean·t, then × (0.72 + 0.35 · luminance(mean)/255), then grey + (c − grey)·0.85;
    /// clipped to 0…255 and truncated, then the 0.35 px blur (app side).
    public static func tint(mean: HiddenRGB, strength t: Double) -> HiddenTint {
        HiddenTint(mean: mean, strength: t)
    }

    // MARK: Occluder (`occluder_from_polygon`)
    /// The occluder's soft mask, exactly as numpy builds it: the polygon filled (edges inclusive) into a patch that
    /// starts `feather` px above the polygon's top, *shifted down by another `feather` px* (`py − y0 + feather`),
    /// then a vertical box blur over 2·feather + 1 rows done with `np.roll`, which wraps: the patch's top `feather`
    /// rows pick up the opaque bottom rows (a faint 6 px fade above the cut that is part of the approved look).
    /// Values are truncated to UInt8 like `astype(uint8)`.
    public static func occluderMask(_ g: HiddenOcclusionGeometry) -> HiddenOccluderMask {
        let w = g.rect.width, h = g.rect.height, f = g.feather
        var hard = [UInt8](repeating: 0, count: w * h)
        let poly = g.polygon.map { HiddenPoint(x: $0.x - Double(g.rect.x), y: $0.y - Double(g.rect.y) + Double(f)) }
        for r in 0..<h {
            for c in 0..<w where pointInPolygonInclusive(HiddenPoint(x: Double(c), y: Double(r)), poly) {
                hard[r * w + c] = 255
            }
        }
        var soft = [UInt8](repeating: 0, count: w * h)
        let span = Double(2 * f + 1)
        for c in 0..<w {
            for r in 0..<h {
                var sum = 0
                for k in -f...f {
                    let src = ((r - k) % h + h) % h
                    sum += Int(hard[src * w + c])
                }
                soft[r * w + c] = UInt8(min(255, max(0, Int(Double(sum) / span))))
            }
        }
        return HiddenOccluderMask(rect: g.rect, alpha: soft)
    }

    /// Inside or on the boundary (Pillow fills axis-aligned polygons including their edges).
    static func pointInPolygonInclusive(_ p: HiddenPoint, _ poly: [HiddenPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            // on the edge a–b?
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if abs(cross) < 1e-9, p.x >= min(a.x, b.x), p.x <= max(a.x, b.x), p.y >= min(a.y, b.y), p.y <= max(a.y, b.y) {
                return true
            }
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}

public struct HiddenRGB: Sendable, Hashable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    /// 0.299 r + 0.587 g + 0.114 b (0–255).
    public var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
}

/// The tint as an affine colour transform out = M · rgb + bias (0–255 scale), which is what `match_to_scene` amounts
/// to: c' = k·((1−t)·c + t·m) with k = 0.72 + 0.35·lum(m)/255, then 0.85·c' + 0.05·(r' + g' + b').
public struct HiddenTint: Sendable, Hashable {
    public let mean: HiddenRGB
    public let strength: Double
    /// Brightness factor k.
    public let brightness: Double
    /// Row-major 3×3.
    public let matrix: [Double]
    /// 0–255 scale.
    public let bias: [Double]

    init(mean m: HiddenRGB, strength t: Double) {
        mean = m
        strength = t
        let k = 0.72 + 0.35 * m.luminance / 255
        brightness = k
        let s = HiddenBlend.saturation, g = (1 - s) / 3
        let diag = k * (1 - t) * (s + g), off = k * (1 - t) * g
        matrix = [diag, off, off, off, diag, off, off, off, diag]
        let mt = [m.r, m.g, m.b].map { k * t * $0 }
        let sum = mt.reduce(0, +)
        bias = mt.map { s * $0 + g * sum }
    }

    /// One pixel, as Pillow / numpy produce it before the blur (clip, then truncate).
    public func apply(_ r: Int, _ g: Int, _ b: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let v = [Double(r), Double(g), Double(b)]
        func ch(_ i: Int) -> UInt8 {
            let x = matrix[3 * i] * v[0] + matrix[3 * i + 1] * v[1] + matrix[3 * i + 2] * v[2] + bias[i]
            return UInt8(min(255, max(0, x)).rounded(.towardZero))
        }
        return (ch(0), ch(1), ch(2))
    }

    /// The same transform for 0–1 colour values (e.g. `CIColorMatrix` vectors: rows of `matrix`, bias / 255).
    public var unitBias: [Double] { bias.map { $0 / 255 } }
}

/// A spot's occluder: the background clipped to `polygon` drawn again over the object, inside `rect`.
public struct HiddenOcclusionGeometry: Sendable, Hashable, Codable {
    /// The patch: x from min(polygon x) to max + 1, y from min(polygon y) − feather to max(polygon y) + 1.
    public let rect: HiddenRect
    public let polygon: [HiddenPoint]
    public let feather: Int

    public init(_ o: HiddenOcclusion) {
        let xs = o.polygon.map { $0[0] }, ys = o.polygon.map { $0[1] }
        let x0 = xs.min() ?? 0, y0 = (ys.min() ?? 0) - o.feather
        rect = HiddenRect(x: x0, y: y0, width: (xs.max() ?? 0) + 1 - x0, height: (ys.max() ?? 0) + 1 - y0)
        polygon = o.polygon.map { HiddenPoint(x: Double($0[0]), y: Double($0[1])) }
        feather = o.feather
    }
}

/// Alpha (0–255) for each pixel of the occluder patch, row-major, `rect.width × rect.height`.
public struct HiddenOccluderMask: Sendable, Hashable {
    public let rect: HiddenRect
    public let alpha: [UInt8]
    public func alpha(x: Int, y: Int) -> UInt8 { alpha[y * rect.width + x] }
}

/// An RGB(A) picture in memory (e.g. the decoded background) for box means.
public struct HiddenRaster: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerPixel: Int
    public let bytesPerRow: Int
    public let pixels: [UInt8]

    /// `pixels`: `bytesPerPixel` interleaved bytes per pixel (3 = RGB, 4 = RGBA / RGBX, colour first), `bytesPerRow`
    /// per row.
    public init(width: Int, height: Int, pixels: [UInt8], bytesPerPixel: Int, bytesPerRow: Int? = nil) {
        precondition(bytesPerPixel >= 3)
        self.width = width
        self.height = height
        self.bytesPerPixel = bytesPerPixel
        self.bytesPerRow = bytesPerRow ?? width * bytesPerPixel
        precondition(pixels.count >= self.bytesPerRow * max(0, height - 1) + width * bytesPerPixel)
        self.pixels = pixels
    }

    /// Mean colour of `rect` (clipped to the raster), like `np.array(crop).mean(0)`.
    public func mean(_ rect: HiddenRect) -> HiddenRGB {
        let x0 = max(0, rect.x), y0 = max(0, rect.y)
        let x1 = min(width, rect.maxX), y1 = min(height, rect.maxY)
        guard x1 > x0, y1 > y0 else { return HiddenRGB(r: 0, g: 0, b: 0) }
        var sum: (UInt64, UInt64, UInt64) = (0, 0, 0)
        pixels.withUnsafeBufferPointer { p in
            for y in y0..<y1 {
                var i = y * bytesPerRow + x0 * bytesPerPixel
                for _ in x0..<x1 {
                    sum.0 += UInt64(p[i]); sum.1 += UInt64(p[i + 1]); sum.2 += UInt64(p[i + 2])
                    i += bytesPerPixel
                }
            }
        }
        let n = Double((x1 - x0) * (y1 - y0))
        return HiddenRGB(r: Double(sum.0) / n, g: Double(sum.1) / n, b: Double(sum.2) / n)
    }

    /// The mean for a rect given in background pixels, when this raster is the background at `scale`
    /// (e.g. 0.5 for `background_1376.jpg`): the rect is scaled and rounded outward.
    public func mean(backgroundRect r: HiddenRect, scale: Double) -> HiddenRGB {
        if scale == 1 { return mean(r) }
        let x0 = Int((Double(r.x) * scale).rounded(.down)), y0 = Int((Double(r.y) * scale).rounded(.down))
        let x1 = Int((Double(r.maxX) * scale).rounded(.up)), y1 = Int((Double(r.maxY) * scale).rounded(.up))
        return mean(HiddenRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
    }
}
