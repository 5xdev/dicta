#!/usr/bin/env swift
// Renders the Dicta app icon with CoreGraphics and writes Dicta/Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift            # writes Dicta/Resources/AppIcon.icns (16–256pt @1x/@2x)
//   swift scripts/make-icon.swift out.png    # writes a single 1024×1024 preview instead
//
// Design: the overlay HUD's waveform (7 capsules sweeping accent → aqua, soft glow) on a deep indigo
// squircle, so the Dock/Finder icon matches what the user sees while dictating.

import AppKit
import CoreGraphics

// MARK: - Palette (kept in sync with AccentColor.colorset and OverlayPanel.swift)

let accent = (r: 0.38, g: 0.56, b: 0.98)            // AccentColor
let accentLifted = (r: 0.504, g: 0.648, b: 0.984)   // accent.mix(with: .white, by: 0.2) — gradientStart
let aqua = (r: 0.45, g: 0.92, b: 0.95)              // gradientEnd

func cg(_ c: (r: Double, g: Double, b: Double), _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: a)
}
func mix(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double), _ t: Double)
    -> (r: Double, g: Double, b: Double) {
    (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
}

// MARK: - Geometry

/// Apple's macOS icon grid: on a 1024 canvas the tile is 824 wide, centered, leaving room for the shadow.
let canvas: CGFloat = 1024
let tile: CGFloat = 824
let inset = (canvas - tile) / 2

/// Continuous-curvature rounded rect (superellipse-ish), close to the system icon mask.
func squircle(in rect: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let r = min(radius, min(rect.width, rect.height) / 2)
    let k: CGFloat = 0.605   // control-point factor tuned for a softer, Apple-like corner
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    p.move(to: CGPoint(x: minX + r, y: maxY))
    p.addLine(to: CGPoint(x: maxX - r, y: maxY))
    p.addCurve(to: CGPoint(x: maxX, y: maxY - r),
               control1: CGPoint(x: maxX - r + r * k, y: maxY),
               control2: CGPoint(x: maxX, y: maxY - r + r * k))
    p.addLine(to: CGPoint(x: maxX, y: minY + r))
    p.addCurve(to: CGPoint(x: maxX - r, y: minY),
               control1: CGPoint(x: maxX, y: minY + r - r * k),
               control2: CGPoint(x: maxX - r + r * k, y: minY))
    p.addLine(to: CGPoint(x: minX + r, y: minY))
    p.addCurve(to: CGPoint(x: minX, y: minY + r),
               control1: CGPoint(x: minX + r - r * k, y: minY),
               control2: CGPoint(x: minX, y: minY + r - r * k))
    p.addLine(to: CGPoint(x: minX, y: maxY - r))
    p.addCurve(to: CGPoint(x: minX + r, y: maxY),
               control1: CGPoint(x: minX, y: maxY - r + r * k),
               control2: CGPoint(x: minX + r - r * k, y: maxY))
    p.closeSubpath()
    return p
}

// MARK: - Render

func render(size: CGFloat) -> CGImage {
    let scale = size / canvas
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    // Draw at 16 bits/channel: CoreGraphics dithers gradients into 8-bit contexts, and that ±1 noise roughly
    // triples the PNG size. At 16-bit the dither lives in the low byte, which `quantize` discards.
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 16, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                            | CGBitmapInfo.byteOrder16Little.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let tileRect = CGRect(x: inset, y: inset, width: tile, height: tile)
    let mask = squircle(in: tileRect, radius: tile * 0.225)

    // Drop shadow (macOS icons carry their own soft shadow).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(mask)
    ctx.setFillColor(cg((r: 0.08, g: 0.09, b: 0.16)))
    ctx.fillPath()
    ctx.restoreGState()

    // Everything below is clipped to the tile.
    ctx.saveGState()
    ctx.addPath(mask)
    ctx.clip()

    // Base: deep indigo, slightly lighter at the top (like the HUD's dark glass).
    let base = CGGradient(colorsSpace: cs,
                          colors: [cg((r: 0.16, g: 0.18, b: 0.34)), cg((r: 0.07, g: 0.08, b: 0.15))] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: canvas), end: CGPoint(x: 0, y: 0), options: [])

    // Ambient glow: accent bloom from the upper-left, aqua bloom from the lower-right.
    let accentBloom = CGGradient(colorsSpace: cs,
                                 colors: [cg(accent, 0.55), cg(accent, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(accentBloom, startCenter: CGPoint(x: 300, y: 760), startRadius: 0,
                           endCenter: CGPoint(x: 300, y: 760), endRadius: 620, options: [])
    let aquaBloom = CGGradient(colorsSpace: cs,
                               colors: [cg(aqua, 0.28), cg(aqua, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(aquaBloom, startCenter: CGPoint(x: 760, y: 240), startRadius: 0,
                           endCenter: CGPoint(x: 760, y: 240), endRadius: 560, options: [])

    // Glass rim: a faint light hairline just inside the edge (same trick as the overlay pill).
    ctx.saveGState()
    ctx.addPath(squircle(in: tileRect.insetBy(dx: 3, dy: 3), radius: tile * 0.225 - 3))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // Waveform: 7 capsules, heights shaped like a spoken syllable, sweeping accent → aqua.
    let count = 7
    let heights: [CGFloat] = [0.30, 0.56, 0.82, 1.00, 0.70, 0.46, 0.26]   // fraction of maxHeight
    let maxHeight: CGFloat = 470
    let barWidth: CGFloat = 70
    let gap: CGFloat = 36
    let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
    let startX = (canvas - totalWidth) / 2
    let centerY = canvas / 2

    func barPath(_ i: Int) -> CGPath {
        let h = max(barWidth, heights[i] * maxHeight)
        let x = startX + CGFloat(i) * (barWidth + gap)
        let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
        return CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    }

    // Glow pass: blurred, tinted copies underneath the bars (the HUD's `.shadow(color: glow, radius:)`).
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: cg(accentLifted, 0.85))
    for i in 0..<count {
        ctx.addPath(barPath(i))
        ctx.setFillColor(cg(mix(accentLifted, aqua, Double(i) / Double(count - 1))))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Crisp pass: the bars themselves, each with a vertical highlight so they read as lit capsules.
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let c = mix(accentLifted, aqua, t)
        let top = mix(c, (r: 1, g: 1, b: 1), 0.22)
        let path = barPath(i)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let g = CGGradient(colorsSpace: cs, colors: [cg(top), cg(c)] as CFArray, locations: [0, 1])!
        let box = path.boundingBox
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
        ctx.restoreGState()
    }

    ctx.restoreGState()   // end tile clip
    return quantize(ctx)
}

/// 16-bit premultiplied RGBA context → 8-bit CGImage (rounded, not dithered).
func quantize(_ ctx: CGContext) -> CGImage {
    let w = ctx.width, h = ctx.height
    let src = ctx.data!.assumingMemoryBound(to: UInt16.self)
    let srcStride = ctx.bytesPerRow / 2
    var out = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h {
        for i in 0..<(w * 4) {
            out[y * w * 4 + i] = UInt8((UInt32(src[y * srcStride + i]) + 128) / 257)
        }
    }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return out.withUnsafeMutableBytes { buf in
        CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

// MARK: - Output

let args = CommandLine.arguments
if args.count > 1 {
    try writePNG(render(size: 1024), to: URL(fileURLWithPath: args[1]))
    print("wrote \(args[1])")
    exit(0)
}

let scriptPath = URL(fileURLWithPath: args[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    .standardizedFileURL.path
let repoRoot = ((scriptPath as NSString).deletingLastPathComponent + "/..") as NSString
let iconset = URL(fileURLWithPath: repoRoot.standardizingPath + "/build/AppIcon.iconset")
let icns = URL(fileURLWithPath: repoRoot.standardizingPath + "/Dicta/Resources/AppIcon.icns")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) → pixel size; filenames follow iconutil's convention.
// 512 and 512@2x are deliberately omitted: they'd add ~560 KB to a ~400 KB app and only matter for Finder at
// maximum icon zoom / Quick Look on Retina, where macOS upscales 256@2x instead. Add (512, 1), (512, 2) to restore.
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2)]
for (pt, scale) in slots {
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@\(scale)x.png"
    try writePNG(render(size: CGFloat(pt * scale)), to: iconset.appendingPathComponent(name))
}

// Ship a plain .icns (CFBundleIconFile) rather than going through the asset catalog: actool also embeds the
// raw bitmaps in Assets.car, which adds ~1.4 MB to an app that is otherwise ~400 K.
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
try? FileManager.default.removeItem(at: iconset)
print("wrote \(icns.path)")
