// Composites an App Store screenshot with a caption band on top.
//
//   swift scripts/appstore-caption.swift RAW.png OUT.png "Headline" ["Smaller line"]
//
// The output has the raw screenshot's pixel size (so it stays a valid App Store
// size), or CAPTION_SIZE=WxH when set (e.g. a Mac window shot into 2880x1800): a dark workbench-brown background, the caption in the
// system serif face (New York) in parchment and gold, and the screenshot
// scaled down below it with rounded corners and a soft shadow.
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: appstore-caption RAW.png OUT.png HEADLINE [SUBLINE]\n".data(using: .utf8)!)
    exit(2)
}
let rawURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let headline = args[3]
let subline = args.count > 4 ? args[4] : nil

guard let src = CGImageSourceCreateWithURL(rawURL as CFURL, nil),
      let raw = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("cannot read \(rawURL.path)\n".data(using: .utf8)!)
    exit(1)
}
let custom = ProcessInfo.processInfo.environment["CAPTION_SIZE"]?.split(separator: "x").compactMap { Int($0) }
let pixelW = custom?.count == 2 ? custom![0] : raw.width
let pixelH = custom?.count == 2 ? custom![1] : raw.height
let W = CGFloat(pixelW), H = CGFloat(pixelH)
let rawW = CGFloat(raw.width), rawH = CGFloat(raw.height)
let landscape = W > H

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// Background: LaunchBackground (#3A3426) fading to a deeper brown, with a warm glow behind the text.
let bg = CGGradient(colorsSpace: space,
                    colors: [rgb(0x4A / 255, 0x40 / 255, 0x2E / 255), rgb(0x3A / 255, 0x34 / 255, 0x26 / 255),
                             rgb(0x22 / 255, 0x1E / 255, 0x16 / 255)] as CFArray,
                    locations: [0, 0.45, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(1.0, 0.78, 0.35, 0.22), rgb(1.0, 0.78, 0.35, 0)] as CFArray,
                      locations: [0, 1])!
let bandH = landscape ? H * 0.20 : H * 0.17
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: H - bandH * 0.5), startRadius: 0,
                       endCenter: CGPoint(x: W / 2, y: H - bandH * 0.5), endRadius: W * 0.55, options: [])

// Caption text.
func serif(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
func drawCentered(_ text: String, font: NSFont, color: CGColor, centerY: CGFloat, maxWidth: CGFloat) {
    var f = font
    var line: CTLine
    repeat {
        let attr = NSAttributedString(string: text, attributes: [
            .font: f, .foregroundColor: NSColor(cgColor: color)!, .kern: f.pointSize * 0.01,
        ])
        line = CTLineCreateWithAttributedString(attr)
        if CTLineGetTypographicBounds(line, nil, nil, nil) <= maxWidth { break }
        f = serif(f.pointSize * 0.95, .bold)
    } while f.pointSize > 10
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -f.pointSize * 0.06), blur: f.pointSize * 0.25,
                  color: rgb(0, 0, 0, 0.55))
    ctx.textPosition = CGPoint(x: (W - width) / 2, y: centerY - (ascent - descent) / 2)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}
let unit = min(W, H)
let headSize = unit * (landscape ? 0.075 : 0.085)
let maxTextW = W * 0.9
if let subline {
    drawCentered(headline, font: serif(headSize, .bold), color: rgb(0.99, 0.93, 0.78),
                 centerY: H - bandH * 0.40, maxWidth: maxTextW)
    drawCentered(subline, font: serif(headSize * 0.5, .semibold), color: rgb(1.0, 0.80, 0.42),
                 centerY: H - bandH * 0.78, maxWidth: maxTextW)
} else {
    drawCentered(headline, font: serif(headSize, .bold), color: rgb(0.99, 0.93, 0.78),
                 centerY: H - bandH * 0.55, maxWidth: maxTextW)
}

// The screenshot, scaled to fit under the band.
let margin = unit * 0.05
let availH = H - bandH - margin
let availW = W - 2 * margin
let scale = min(availH / rawH, availW / rawW)
let sw = rawW * scale, sh = rawH * scale
let rect = CGRect(x: (W - sw) / 2, y: (H - bandH - sh) / 2 + (landscape ? 0 : -margin * 0.2), width: sw, height: sh)
let radius = sw * (landscape ? 0.02 : 0.06)
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -unit * 0.01), blur: unit * 0.04, color: rgb(0, 0, 0, 0.6))
ctx.addPath(path); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(path); ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(raw, in: rect)
ctx.restoreGState()
ctx.addPath(path); ctx.setStrokeColor(rgb(1.0, 0.85, 0.55, 0.45)); ctx.setLineWidth(unit * 0.004); ctx.strokePath()

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
