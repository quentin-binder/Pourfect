#if DEBUG
import CoreGraphics
import Foundation
import HiddenCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Dev aid for the layout review (`-LPHiddenExport <dir>`): renders every fixed round of every room with the app's
/// own renderer: `<room>_rNN.png` (full resolution), `<room>_rNN_half.png` and `<room>_rNN_close.png` (a close-up of
/// every object with its role, id, spot, long side and rotation). `-LPHiddenExportRooms attic,hoard` limits the rooms.
enum HiddenExport {
    static func run(to dir: URL, rooms: [HiddenSceneID]) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for room in rooms {
            guard let assets = try? await Task.detached(operation: { try HiddenRoomAssets.load(room) }).value else {
                NSLog("HiddenExport: cannot load \(room.rawValue)")
                continue
            }
            for layout in assets.rounds {
                let layers = await Task.detached { HiddenRenderer.layers(layout, assets: assets) }.value
                guard let full = composite(assets: assets, layers: layers) else { continue }
                let name = "\(room.rawValue)_r\(String(format: "%02d", layout.round))"
                write(full, dir.appending(path: "\(name).png"))
                if let half = scaled(full, by: 0.5) { write(half, dir.appending(path: "\(name)_half.png")) }
                if let sheet = closeups(full, layout: layout, scene: assets.scene) { write(sheet, dir.appending(path: "\(name)_close.png")) }
            }
        }
        try? "done\n".write(to: dir.appending(path: "DONE"), atomically: true, encoding: .utf8)
    }

    static func composite(assets: HiddenRoomAssets, layers: [HiddenLayerSet]) -> CGImage? {
        let w = assets.scene.width, h = assets.scene.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        func draw(_ image: CGImage?, _ origin: CGPoint) {
            guard let image else { return }
            ctx.draw(image, in: CGRect(x: origin.x, y: CGFloat(h) - origin.y - CGFloat(image.height),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        draw(assets.background, .zero)
        for l in layers {
            draw(l.shadow, l.shadowOrigin)
            draw(l.object, CGPoint(x: l.placement.x, y: l.placement.y))
            draw(l.occluder, l.occluderOrigin)
        }
        return ctx.makeImage()
    }

    static func scaled(_ image: CGImage, by f: CGFloat) -> CGImage? {
        let w = Int(CGFloat(image.width) * f), h = Int(CGFloat(image.height) * f)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    @MainActor
    static func closeups(_ full: CGImage, layout: HiddenRoundLayout, scene: HiddenScene) -> CGImage? {
        let tile: CGFloat = 170
        let items: [(CGImage, String, Bool)] = (layout.targets + layout.decoys).compactMap { p in
            let pad = max(26, max(p.width, p.height) / 2)
            let r = CGRect(x: p.x - pad, y: p.y - pad, width: p.width + 2 * pad, height: p.height + 2 * pad)
                .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
            guard let crop = full.cropping(to: r) else { return nil }
            var label = "\(p.role == .target ? "T" : "d") \(p.objectID) @\(p.spotID) L\(p.longSide)"
            if p.rotation != 0 { label += " r\(Int(p.rotation))" }
            if p.dx != 0 || p.dy != 0 { label += " (\(p.dx),\(p.dy))" }
            return (crop, label, p.role == .target)
        }
        let columns = 8
        let view = VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(scene.id.rawValue) round \(layout.round): \(layout.targets.count) targets, \(layout.decoys.count) decoys")
                .font(.system(size: 14, weight: .bold))
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<((items.count + columns - 1) / columns), id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { col in
                            let i = row * columns + col
                            if i < items.count {
                                VStack(spacing: 1) {
                                    Image(decorative: items[i].0, scale: 1).resizable().interpolation(.high).scaledToFit()
                                        .frame(width: tile, height: tile)
                                    Text(verbatim: items[i].1).font(.system(size: 9.5, weight: items[i].2 ? .bold : .regular))
                                        .foregroundStyle(items[i].2 ? Color.yellow : Color.white)
                                        .lineLimit(1).frame(width: tile)
                                }
                            } else {
                                Color.clear.frame(width: tile, height: tile)
                            }
                        }
                    }
                }
            }
        }
        .padding(6)
        .foregroundStyle(.white)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    static func write(_ image: CGImage, _ url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
