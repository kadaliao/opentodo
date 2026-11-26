// windowid <pid>: prints the number of the process's frontmost normal
// window, for `screencapture -l` (on another Space if it isn't on this one). Built and cached by shot.sh. Window
// numbers and owners are listed without the screen recording permission.
// windowid --can-capture: exits 0 if this process (that is, the terminal
// it runs in) has the screen recording permission, 1 if not.
// windowid --shot <pid> <out.png> [main|settings]: captures the process's
// windows with ScreenCaptureKit — only that app's windows, so its popovers
// and sheets come out over the window and nothing else on the screen does —
// cropped to the main window (the largest) with whatever of its popovers
// and sheets sticks out of it; `settings` crops to the smallest window
// instead (the Settings window next to the main one). Each window is
// captured by itself, so it works behind the desktop too (-OTHiddenWindows).
// Needs the permission.
// windowid --bounds <pid>: prints each of the process's windows: number,
// layer and bounds (x y width height, from the top left of the main screen).
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("windowid: \(message)\n".utf8))
    exit(1)
}

if args.first == "--can-capture" {
    exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
}

struct Win {
    let number: Int
    let layer: Int
    let bounds: CGRect

    /// A document window: the normal level, or just below the desktop
    /// picture where -OTHiddenWindows puts every window.
    var isNormal: Bool { layer == 0 || layer == Int(CGWindowLevelForKey(.desktopWindow)) - 1 }
}

/// The process's windows below the menu bar's levels (its status item and
/// menus are left out). `onScreen`: only those on the current Space; else
/// also those on another one (when the person is in a full-screen app, an
/// app started with `open -g` gets its window on the desktop's Space, where
/// `screencapture -l` still captures it).
func windows(of pid: Int32, onScreen: Bool = true) -> [Win] {
    // Not .excludeDesktopElements: shot.sh puts the app's windows behind the
    // desktop picture (-OTHiddenWindows); only this pid's are kept anyway.
    let list = CGWindowListCopyWindowInfo(onScreen ? [.optionOnScreenOnly] : [.optionAll], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
              let number = w[kCGWindowNumber as String] as? Int,
              let layer = w[kCGWindowLayer as String] as? Int, layer < 20,
              let b = w[kCGWindowBounds as String] as? [String: Double]
        else { return nil }
        let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        guard rect.width > 20, rect.height > 20 else { return nil }
        return Win(number: number, layer: layer, bounds: rect)
    }
}

if args.first == "--shot" {
    guard args.count >= 3, let pid = Int32(args[1]) else { fail("usage: windowid --shot <pid> <out.png> [main|settings]") }
    let out = URL(fileURLWithPath: args[2])
    let which = args.count > 3 ? args[3] : "main"
    let wins = windows(of: pid)
    let normal = wins.filter { $0.isNormal && $0.bounds.height > 100 }
    let byArea = normal.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
    guard let base = which == "settings" ? byArea.last : byArea.first else { fail("no window") }
    // What sticks out of the base window: popovers and sheets that touch it.
    var crop = base.bounds
    for w in wins where w.number != base.number && w.bounds.intersects(base.bounds.insetBy(dx: -40, dy: -40)) {
        crop = crop.union(w.bounds)
    }
    crop = crop.insetBy(dx: -24, dy: -24)

    // Each window on its own (`desktopIndependentWindow`), covered or not —
    // shot.sh keeps the app's windows behind the desktop (-OTHiddenWindows) —
    // then drawn together back to front, as they'd be stacked on a screen.
    let content: SCShareableContent
    do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) } catch {
        fail("no shareable content: \(error)")
    }
    let stack = wins.filter { $0.number == base.number || crop.intersects($0.bounds) }.reversed()
    var scale: CGFloat = 2
    if let first = content.windows.first(where: { $0.windowID == CGWindowID(base.number) }) {
        scale = CGFloat(SCContentFilter(desktopIndependentWindow: first).pointPixelScale)
    }
    let width = Int(crop.width * scale), height = Int(crop.height * scale)
    guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no canvas") }
    for w in stack {
        guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(w.number) }) else { continue }
        let config = SCStreamConfiguration()
        config.width = Int(w.bounds.width * scale)
        config.height = Int(w.bounds.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let shot: CGImage
        do {
            shot = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: scWindow),
                                                               configuration: config)
        } catch {
            fail("capture failed: \(error)")
        }
        // Window bounds count down from the top; the canvas up from the bottom.
        let rect = CGRect(x: (w.bounds.minX - crop.minX) * scale, y: (crop.maxY - w.bounds.maxY) * scale,
                          width: w.bounds.width * scale, height: w.bounds.height * scale)
        canvas.draw(shot, in: rect)
    }
    guard let image = canvas.makeImage() else { fail("no image") }
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(out.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot write \(out.path)") }
    exit(0)
}

if args.first == "--bounds" {
    guard args.count == 2, let pid = Int32(args[1]) else { fail("usage: windowid --bounds <pid>") }
    for w in windows(of: pid, onScreen: false) {
        print(w.number, w.layer, Int(w.bounds.minX), Int(w.bounds.minY), Int(w.bounds.width), Int(w.bounds.height))
    }
    exit(0)
}

guard args.count == 1, let pid = Int32(args[0]) else {
    FileHandle.standardError.write(Data("usage: windowid <pid>\n".utf8))
    exit(2)
}
guard let match = windows(of: pid).first(where: { $0.isNormal && $0.bounds.height > 100 })
    ?? windows(of: pid, onScreen: false).first(where: { $0.isNormal && $0.bounds.height > 100 })
else { exit(1) }
print(match.number)
