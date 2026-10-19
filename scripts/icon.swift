// Generates the Celah app icon set: a black squircle with a notch silhouette and one amber dot.
// Usage: swift scripts/icon.swift build/AppIcon.iconset
import AppKit

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let s = CGFloat(px)
    let inset = s * 0.055   // macOS icons leave a margin inside the canvas
    let box = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSColor(calibratedWhite: 0.05, alpha: 1).setFill(); bg.fill()
    bg.addClip()
    // notch silhouette hanging from the top edge
    let nw = box.width * 0.48, nh = box.height * 0.19, r = box.width * 0.055
    let notch = NSBezierPath(roundedRect: NSRect(x: box.midX - nw / 2, y: box.maxY - nh, width: nw, height: nh + r * 3),
                             xRadius: r, yRadius: r)
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); notch.fill()
    // amber dot
    let d = box.width * 0.085
    NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: box.midX - d / 2, y: box.minY + box.height * 0.36, width: d, height: d)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
print("icons written to \(outDir)")
