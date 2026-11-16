// Flattens App Store screenshots: App Store Connect rejects images with an alpha
// channel or transparent pixels (Mac window captures have transparent rounded
// corners). Each file is drawn over the launch-screen brown into an opaque RGB
// image of the same pixel size and written back as PNG.
//
//   swift scripts/appstore-flatten.swift FILE.png [FILE.png ...]
import AppKit

let files = CommandLine.arguments.dropFirst()
guard !files.isEmpty else {
    FileHandle.standardError.write("usage: appstore-flatten FILE.png [FILE.png ...]\n".data(using: .utf8)!)
    exit(2)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
var failed = false
for path in files {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
        failed = true
        continue
    }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.setFillColor(CGColor(colorSpace: space, components: [0x22 / 255.0, 0x1E / 255.0, 0x16 / 255.0, 1])!)
    ctx.fill(rect)
    ctx.draw(image, in: rect)
    guard let flat = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        failed = true
        continue
    }
    CGImageDestinationAddImage(dest, flat, nil)
    if !CGImageDestinationFinalize(dest) { failed = true }
}
exit(failed ? 1 : 0)
