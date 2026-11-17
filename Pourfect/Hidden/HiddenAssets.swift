import Accelerate
import CoreGraphics
import Foundation
import HiddenCore
import ImageIO

/// A decoded picture with straight (not premultiplied) RGBA, 8 bits per channel, row-major.
nonisolated struct HiddenPixels: Sendable {
    var width: Int
    var height: Int
    var rgba: [UInt8]

    init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    init(width: Int, height: Int) {
        self.init(width: width, height: height, rgba: [UInt8](repeating: 0, count: width * height * 4))
    }

    /// Decodes a PNG / JPEG as straight RGBA. The image's own bytes are used when they already are 8-bit RGBA
    /// (no colour conversion, like Pillow); anything else goes through an sRGB context.
    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        self.init(image: image)
    }

    init?(image: CGImage) {
        let w = image.width, h = image.height
        let info = image.bitmapInfo
        let alpha = image.alphaInfo
        let byteOrder = info.intersection(.byteOrderMask)
        if image.bitsPerComponent == 8, image.bitsPerPixel == 32, alpha == .last,
           byteOrder == [] || byteOrder == .byteOrder32Big,
           let data = image.dataProvider?.data as Data? {
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let rowBytes = image.bytesPerRow
            data.withUnsafeBytes { raw in
                px.withUnsafeMutableBytes { dst in
                    for y in 0..<h {
                        dst.baseAddress!.advanced(by: y * w * 4)
                            .copyMemory(from: raw.baseAddress!.advanced(by: y * rowBytes), byteCount: w * 4)
                    }
                }
            }
            self.init(width: w, height: h, rgba: px)
            return
        }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, rgba: px)
        if alpha != .none, alpha != .noneSkipLast, alpha != .noneSkipFirst { unpremultiply() }
    }

    var alpha: [UInt8] {
        var a = [UInt8](repeating: 0, count: width * height)
        rgba.withUnsafeBufferPointer { src in
            a.withUnsafeMutableBufferPointer { dst in
                for i in 0..<dst.count { dst[i] = src[i &* 4 &+ 3] }
            }
        }
        return a
    }

    mutating func premultiply() {
        let (w, h) = (width, height)
        rgba.withUnsafeMutableBytes { b in
            var buf = vImage_Buffer(data: b.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
            _ = vImagePremultiplyData_RGBA8888(&buf, &buf, vImage_Flags(kvImageNoFlags))
        }
    }

    mutating func unpremultiply() {
        let (w, h) = (width, height)
        rgba.withUnsafeMutableBytes { b in
            var buf = vImage_Buffer(data: b.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
            _ = vImageUnpremultiplyData_RGBA8888(&buf, &buf, vImage_Flags(kvImageNoFlags))
        }
    }

    /// A premultiplied copy as a CGImage (what Core Animation draws).
    func cgImage() -> CGImage? {
        var copy = self
        copy.premultiply()
        let data = Data(copy.rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Pillow's `resize(..., LANCZOS)` on RGBA: premultiplied, resampled, back to straight alpha.
    func resized(width w: Int, height h: Int) -> HiddenPixels {
        if w == width, h == height { return self }
        var src = self
        src.premultiply()
        var out = HiddenPixels(width: w, height: h)
        src.rgba.withUnsafeMutableBytes { s in
            out.rgba.withUnsafeMutableBytes { d in
                var sb = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                       rowBytes: width * 4)
                var db = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w),
                                       rowBytes: w * 4)
                _ = vImageScale_ARGB8888(&sb, &db, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        out.unpremultiply()
        return out
    }

    /// Turned clockwise by `degrees` onto the canvas `HiddenRotation.canvasSize` gives (bilinear, premultiplied).
    func rotated(degrees: Double) -> HiddenPixels {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return self }
        let canvas = HiddenRotation.canvasSize(width: width, height: height, degrees: degrees)
        var src = self
        src.premultiply()
        var out = HiddenPixels(width: canvas.width, height: canvas.height)
        func px(_ x: Int, _ y: Int, _ k: Int) -> Double {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return Double(src.rgba[(y * width + x) * 4 + k])
        }
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let s = HiddenRotation.source(x: Double(x) + 0.5, y: Double(y) + 0.5, width: width, height: height,
                                              canvas: canvas, degrees: degrees)
                let fx = s.x - 0.5, fy = s.y - 0.5
                let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
                let ax = fx - Double(x0), ay = fy - Double(y0)
                guard x0 >= -1, y0 >= -1, x0 < width, y0 < height else { continue }
                for k in 0..<4 {
                    let v = (px(x0, y0, k) * (1 - ax) + px(x0 + 1, y0, k) * ax) * (1 - ay)
                        + (px(x0, y0 + 1, k) * (1 - ax) + px(x0 + 1, y0 + 1, k) * ax) * ay
                    out.rgba[(y * canvas.width + x) * 4 + k] = UInt8(min(255, max(0, v.rounded())))
                }
            }
        }
        out.unpremultiply()
        return out
    }

    func flippedHorizontally() -> HiddenPixels {
        var out = self
        for y in 0..<height {
            for x in 0..<width {
                let s = (y * width + (width - 1 - x)) * 4, d = (y * width + x) * 4
                for k in 0..<4 { out.rgba[d + k] = rgba[s + k] }
            }
        }
        return out
    }

    /// Gaussian blur of all four channels (straight alpha, like Pillow's `GaussianBlur` on RGBA), edges extended.
    func blurred(sigma: Double) -> HiddenPixels {
        let radius = max(1, Int((sigma * 3).rounded(.up)))
        var weights = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = weights.reduce(0, +)
        weights = weights.map { $0 / total }
        // Integer kernel for vImage (sum = divisor).
        let scale = 4096.0
        var kernel = weights.map { Int16(($0 * scale).rounded()) }
        let divisor = Int32(kernel.reduce(0) { $0 + Int32($1) })
        var src = self
        var tmp = HiddenPixels(width: width, height: height)
        var out = HiddenPixels(width: width, height: height)
        let size = UInt32(kernel.count)
        src.rgba.withUnsafeMutableBytes { s in
            tmp.rgba.withUnsafeMutableBytes { t in
                out.rgba.withUnsafeMutableBytes { d in
                    var sb = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                    var tb = vImage_Buffer(data: t.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                    var db = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                    kernel.withUnsafeMutableBufferPointer { k in
                        _ = vImageConvolve_ARGB8888(&sb, &tb, nil, 0, 0, k.baseAddress!, 1, size, divisor, nil,
                                                    vImage_Flags(kvImageEdgeExtend))
                        _ = vImageConvolve_ARGB8888(&tb, &db, nil, 0, 0, k.baseAddress!, size, 1, divisor, nil,
                                                    vImage_Flags(kvImageEdgeExtend))
                    }
                }
            }
        }
        return out
    }
}

/// What a room needs on screen, loaded once per room and kept: the scene file, both backgrounds, the full
/// background's pixels (tint means and occluder patches), and every object's picture and hit mask.
nonisolated final class HiddenRoomAssets: @unchecked Sendable {
    let scene: HiddenScene
    let background: CGImage
    /// `background_1376.jpg` (half size) for zoomed-out views; nil if the scene has none.
    let backgroundSmall: CGImage?
    let raster: HiddenRaster
    /// Natural-size object pictures (straight RGBA), their CGImages (find-list thumbnails) and hit masks.
    let pixels: [String: HiddenPixels]
    let images: [String: CGImage]
    let masks: [String: HiddenAlphaMask]
    /// The ten fixed rounds (`rounds.json`), in order.
    let rounds: [HiddenRoundLayout]

    private init(scene: HiddenScene, background: CGImage, backgroundSmall: CGImage?, raster: HiddenRaster,
                 pixels: [String: HiddenPixels], images: [String: CGImage], masks: [String: HiddenAlphaMask],
                 rounds: [HiddenRoundLayout]) {
        self.rounds = rounds
        self.scene = scene
        self.background = background
        self.backgroundSmall = backgroundSmall
        self.raster = raster
        self.pixels = pixels
        self.images = images
        self.masks = masks
    }

    /// Hit masks for a round: the natural ones, turned for objects a fixed layout turns.
    func masks(for layout: HiddenRoundLayout) -> [String: HiddenAlphaMask] {
        var out = masks
        for p in layout.drawOrder where p.rotation != 0 {
            guard let px = pixels[p.objectID] else { continue }
            let r = HiddenRotation.rotateAlpha(px.alpha, width: px.width, height: px.height, degrees: p.rotation)
            out[p.objectID] = HiddenAlphaMask(alpha: r.alpha, width: r.width, height: r.height)
        }
        return out
    }

    static func folder(_ room: HiddenSceneID) -> URL? {
        Bundle.main.url(forResource: room.rawValue, withExtension: nil, subdirectory: "HiddenScenes")
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [HiddenSceneID: HiddenRoomAssets] = [:]

    /// Loads (or returns the cached) room. Slow the first time (about a quarter second): call off the main actor.
    static func load(_ room: HiddenSceneID) throws -> HiddenRoomAssets {
        // One load at a time: a round opened while the room screen is still prefetching waits for it.
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[room] { return hit }
        guard let dir = folder(room) else { throw HiddenAssetError.missing("HiddenScenes/\(room.rawValue)") }
        let scene = try HiddenScene(data: Data(contentsOf: dir.appending(path: "scene.json")))
        guard let full = scene.images.first(where: { $0.scale == 1 }) else { throw HiddenAssetError.missing("background") }
        guard let bg = image(dir.appending(path: full.file)) else { throw HiddenAssetError.missing(full.file) }
        let small = scene.images.filter { $0.scale < 1 }.max { $0.scale < $1.scale }.flatMap { image(dir.appending(path: $0.file)) }
        guard let bgPixels = HiddenPixels(image: bg) else { throw HiddenAssetError.missing(full.file) }
        let raster = HiddenRaster(width: bgPixels.width, height: bgPixels.height, pixels: bgPixels.rgba, bytesPerPixel: 4)
        // The objects in parallel: decode, thumbnail image, hit mask.
        let objects = scene.objects
        let decoded = HiddenSlots<(HiddenPixels, CGImage?, HiddenAlphaMask)>(objects.count)
        DispatchQueue.concurrentPerform(iterations: objects.count) { i in
            guard let p = HiddenPixels(url: dir.appending(path: objects[i].png)) else { return }
            decoded[i] = (p, p.cgImage(), HiddenAlphaMask(alpha: p.alpha, width: p.width, height: p.height))
        }
        var pixels: [String: HiddenPixels] = [:], images: [String: CGImage] = [:], masks: [String: HiddenAlphaMask] = [:]
        for (i, o) in objects.enumerated() {
            guard let d = decoded[i] else { throw HiddenAssetError.missing(o.png) }
            pixels[o.id] = d.0
            images[o.id] = d.1
            masks[o.id] = d.2
        }
        let rounds = try HiddenFixedLayouts.load(Data(contentsOf: dir.appending(path: "rounds.json")), scene: scene)
        let assets = HiddenRoomAssets(scene: scene, background: bg, backgroundSmall: small, raster: raster,
                                      pixels: pixels, images: images, masks: masks, rounds: rounds)
        cache[room] = assets
        return assets
    }

    private static func image(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

enum HiddenAssetError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let what): "Missing hidden-object file: \(what)"
        }
    }
}

/// One object of a round, ready to draw: its contact shadow, the tinted object and (on a container spot) the
/// occluder patch, each with its top-left corner in background pixels. Drawn in that order, back to front.
nonisolated struct HiddenLayerSet: @unchecked Sendable, Identifiable {
    let placement: HiddenPlacement
    let shadow: CGImage?
    let shadowOrigin: CGPoint
    let object: CGImage?
    let occluder: CGImage?
    let occluderOrigin: CGPoint
    var id: String { placement.objectID }
}

/// The art pipeline's blending (`hocommon.py`: `match_to_scene`, `shadow_for`, `occluder_from_polygon`), done on
/// the pixels with the numbers and formulas from `HiddenBlend`.
nonisolated enum HiddenRenderer {
    static func layers(_ layout: HiddenRoundLayout, assets: HiddenRoomAssets) -> [HiddenLayerSet] {
        let order = layout.drawOrder
        let out = HiddenSlots<HiddenLayerSet>(order.count)
        DispatchQueue.concurrentPerform(iterations: order.count) { i in out[i] = layers(for: order[i], assets: assets) }
        return (0..<order.count).compactMap { out[$0] }
    }

    static func layers(for p: HiddenPlacement, assets: HiddenRoomAssets) -> HiddenLayerSet {
        let scene = assets.scene
        var object: HiddenPixels?
        if let natural = assets.pixels[p.objectID] {
            var im = natural.rotated(degrees: p.rotation).resized(width: p.width, height: p.height)
            if p.flipped { im = im.flippedHorizontally() }
            // match_to_scene: tint toward the mean of the surroundings, then the 0.35 px blur.
            let mean = assets.raster.mean(p.tintSampleRect(sceneWidth: scene.width, sceneHeight: scene.height))
            let tint = HiddenBlend.tint(mean: mean, strength: p.tint)
            for i in stride(from: 0, to: im.rgba.count, by: 4) {
                let c = tint.apply(Int(im.rgba[i]), Int(im.rgba[i + 1]), Int(im.rgba[i + 2]))
                im.rgba[i] = c.r; im.rgba[i + 1] = c.g; im.rgba[i + 2] = c.b
            }
            object = im.blurred(sigma: HiddenBlend.objectBlur)
        }
        // shadow_for: the tinted object's alpha × 0.38 in the shadow colour on a padded canvas, blurred σ 5.
        var shadowImage: CGImage?
        if let im = object {
            let pad = HiddenBlend.shadowPad
            var canvas = HiddenPixels(width: im.width + 2 * pad, height: im.height + 2 * pad)
            let col = HiddenBlend.shadowColor
            for y in 0..<im.height {
                for x in 0..<im.width {
                    let a = Double(im.rgba[(y * im.width + x) * 4 + 3])
                    let d = ((y + pad) * canvas.width + x + pad) * 4
                    canvas.rgba[d] = UInt8(col.r); canvas.rgba[d + 1] = UInt8(col.g); canvas.rgba[d + 2] = UInt8(col.b)
                    canvas.rgba[d + 3] = UInt8(Int(a * HiddenBlend.shadowAlpha))
                }
            }
            shadowImage = canvas.blurred(sigma: HiddenBlend.shadowBlur).cgImage()
        }
        // occluder_from_polygon: the background inside the polygon, its top edge feathered, over the object.
        var occluder: CGImage?
        var occluderOrigin = CGPoint.zero
        if let g = p.occlusion {
            let mask = HiddenBlend.occluderMask(g)
            let r = g.rect
            var patch = HiddenPixels(width: r.width, height: r.height)
            let raster = assets.raster
            for y in 0..<r.height {
                let by = r.y + y
                guard by >= 0, by < raster.height else { continue }
                for x in 0..<r.width {
                    let bx = r.x + x
                    guard bx >= 0, bx < raster.width else { continue }
                    let s = by * raster.bytesPerRow + bx * raster.bytesPerPixel
                    let d = (y * r.width + x) * 4
                    patch.rgba[d] = raster.pixels[s]; patch.rgba[d + 1] = raster.pixels[s + 1]
                    patch.rgba[d + 2] = raster.pixels[s + 2]
                    patch.rgba[d + 3] = mask.alpha(x: x, y: y)
                }
            }
            occluder = patch.cgImage()
            occluderOrigin = CGPoint(x: r.x, y: r.y)
        }
        let s = p.shadowRect
        return HiddenLayerSet(placement: p, shadow: shadowImage, shadowOrigin: CGPoint(x: s.x, y: s.y),
                              object: object?.cgImage(), occluder: occluder, occluderOrigin: occluderOrigin)
    }
}

/// Results of `concurrentPerform`: each iteration writes its own slot only.
nonisolated final class HiddenSlots<T>: @unchecked Sendable {
    private let buffer: UnsafeMutableBufferPointer<T?>
    init(_ count: Int) {
        buffer = .allocate(capacity: count)
        buffer.initialize(repeating: nil)
    }
    deinit {
        _ = buffer.deinitialize()
        buffer.deallocate()
    }
    subscript(i: Int) -> T? {
        get { buffer[i] }
        set { buffer[i] = newValue }
    }
}
