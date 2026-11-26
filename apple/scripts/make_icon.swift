// Draws the app icon into App/Assets.xcassets/AppIcon.appiconset and
// rewrites its Contents.json. Run from anywhere:
//
//     swift apple/scripts/make_icon.swift [--preview <dir>]
//
// The mark: three rows of a list, each a round checkbox and a line, the
// first ticked. White on a teal (#14A38B) gradient.
//
// iOS gets one full-bleed 1024 square per appearance (the system rounds
// the corners): light; dark (teal mark on near-black); tinted (a grey mark
// on black, which the system colours). macOS gets the rounded square drawn
// in, inside the standard 1024 grid (an 824 square, 100 margin) with the
// standard drop shadow, at every size the Mac asks for.
//
// `--preview <dir>` also writes the 1024 images there to look at.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconSet = scriptDir.appending(path: "../App/Assets.xcassets/AppIcon.appiconset").standardizedFileURL
var previewDir: URL?
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    previewDir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
}

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

enum Look { case light, dark, tinted }

struct Palette {
    var top: CGColor
    var bottom: CGColor
    var mark: CGColor
    var markShadow: CGColor?

    static func of(_ look: Look) -> Palette {
        switch look {
        case .light: Palette(top: rgb(0x2BC4A6), bottom: rgb(0x0F8E79), mark: rgb(0xFFFFFF), markShadow: rgb(0x064A3F, 0.28))
        case .dark: Palette(top: rgb(0x1C2B28), bottom: rgb(0x0B1412), mark: rgb(0x2BC9AA), markShadow: nil)
        case .tinted: Palette(top: rgb(0x000000), bottom: rgb(0x000000), mark: rgb(0xD9D9D9), markShadow: nil)
        }
    }
}

/// A point of the 1024 design square `box` (y down).
func point(_ box: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: box.minX + x * box.width / 1024, y: box.minY + y * box.width / 1024)
}

func drawBackground(_ ctx: CGContext, _ rect: CGRect, _ pal: Palette) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [pal.top, pal.bottom] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Three rows of a list, each a round checkbox and a line; the first is
/// ticked. Rows are drawn in the 1024 design square `box`.
func drawMark(_ ctx: CGContext, _ box: CGRect, _ pal: Palette) {
    let k = box.width / 1024
    let rows: [(y: CGFloat, end: CGFloat, alpha: CGFloat)] = [(300, 806, 1), (512, 738, 0.82), (724, 664, 0.82)]
    let cx: CGFloat = 300, r: CGFloat = 84, ring: CGFloat = 30, bar: CGFloat = 76, barStart: CGFloat = 438

    ctx.saveGState()
    if let shadow = pal.markShadow {
        ctx.setShadow(offset: CGSize(width: 0, height: 10 * k), blur: 26 * k, color: shadow)
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for (i, row) in rows.enumerated() {
        let color = pal.mark.copy(alpha: pal.mark.alpha * row.alpha)!
        ctx.setFillColor(color)
        let c = point(box, cx, row.y)
        let disc = CGRect(x: c.x - r * k, y: c.y - r * k, width: 2 * r * k, height: 2 * r * k)
        if i == 0 {
            ctx.fillEllipse(in: disc)
            // The tick, cut out of the disc.
            let tick = CGMutablePath()
            tick.move(to: point(box, cx - 40, row.y + 2))
            tick.addLine(to: point(box, cx - 12, row.y + 30))
            tick.addLine(to: point(box, cx + 42, row.y - 30))
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.addPath(tick.copy(strokingWithWidth: 26 * k, lineCap: .round, lineJoin: .round, miterLimit: 10))
            ctx.fillPath()
            ctx.restoreGState()
        } else {
            ctx.addEllipse(in: disc.insetBy(dx: ring * k / 2, dy: ring * k / 2))
            ctx.setStrokeColor(color)
            ctx.setLineWidth(ring * k)
            ctx.strokePath()
        }
        let line = CGRect(x: point(box, barStart, 0).x, y: c.y - bar * k / 2, width: (row.end - barStart) * k, height: bar * k)
        ctx.addPath(CGPath(roundedRect: line, cornerWidth: bar * k / 2, cornerHeight: bar * k / 2, transform: nil))
        ctx.fillPath()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// A context with y pointing down, like the path's coordinates.
func makeContext(_ px: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

/// iOS: full bleed, no transparency.
func iosIcon(_ look: Look) -> CGImage {
    let ctx = makeContext(1024)
    let rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let pal = Palette.of(look)
    drawBackground(ctx, rect, pal)
    drawMark(ctx, rect.insetBy(dx: 4, dy: 4).offsetBy(dx: 6, dy: 0), pal)
    return ctx.makeImage()!
}

/// macOS: the rounded square inside the 1024 grid, with its shadow.
func macIcon(_ px: Int) -> CGImage {
    let ctx = makeContext(px)
    let k = CGFloat(px) / 1024
    ctx.scaleBy(x: k, y: k)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: tile).cgPath
    let pal = Palette.of(.light)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(pal.bottom)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    drawBackground(ctx, tile, pal)
    drawMark(ctx, tile.insetBy(dx: -4, dy: -4).offsetBy(dx: 5, dy: 0), pal)
    ctx.restoreGState()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

// ---- write the set ----

var images: [[String: Any]] = []
for (look, name, appearance) in [(Look.light, "ios-light", nil), (.dark, "ios-dark", "dark"), (.tinted, "ios-tinted", "tinted")] as [(Look, String, String?)] {
    let file = "\(name).png"
    let image = iosIcon(look)
    write(image, to: iconSet.appending(path: file))
    if let previewDir { write(image, to: previewDir.appending(path: file)) }
    var entry: [String: Any] = ["filename": file, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if let appearance { entry["appearances"] = [["appearance": "luminosity", "value": appearance]] }
    images.append(entry)
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let file = "mac-\(px).png"
        write(macIcon(px), to: iconSet.appending(path: file))
        images.append(["filename": file, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
if let previewDir { write(macIcon(1024), to: previewDir.appending(path: "mac-1024.png")) }

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSet.appending(path: "Contents.json"))
print(iconSet.path)
