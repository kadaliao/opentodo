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
// instead (the Settings window next to the main one). Needs the permission.
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
}

/// The process's windows below the menu bar's levels (its status item and
/// menus are left out). `onScreen`: only those on the current Space; else
/// also those on another one (when the person is in a full-screen app, an
/// app started with `open -g` gets its window on the desktop's Space, where
/// `screencapture -l` still captures it).
func windows(of pid: Int32, onScreen: Bool = true) -> [Win] {
    let list = CGWindowListCopyWindowInfo(onScreen ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll],
                                          kCGNullWindowID)
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
    let normal = wins.filter { $0.layer == 0 && $0.bounds.height > 100 }
    let byArea = normal.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
    guard let base = which == "settings" ? byArea.last : byArea.first else { fail("no window") }
    // What sticks out of the base window: popovers and sheets that touch it.
    var crop = base.bounds
    for w in wins where w.number != base.number && w.bounds.intersects(base.bounds.insetBy(dx: -40, dy: -40)) {
        crop = crop.union(w.bounds)
    }
    crop = crop.insetBy(dx: -24, dy: -24)

    let content: SCShareableContent
    do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) } catch {
        fail("no shareable content: \(error)")
    }
    guard let app = content.applications.first(where: { $0.processID == pid }) else { fail("app not shareable") }
    let center = CGPoint(x: base.bounds.midX, y: base.bounds.midY)
    guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
        fail("no display")
    }
    crop = crop.intersection(display.frame)
    let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
    let config = SCStreamConfiguration()
    let scale = CGFloat(filter.pointPixelScale)
    config.sourceRect = crop.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    config.width = Int(crop.width * scale)
    config.height = Int(crop.height * scale)
    config.showsCursor = false
    let image: CGImage
    do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) } catch {
        fail("capture failed: \(error)")
    }
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(out.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot write \(out.path)") }
    exit(0)
}

guard args.count == 1, let pid = Int32(args[0]) else {
    FileHandle.standardError.write(Data("usage: windowid <pid>\n".utf8))
    exit(2)
}
guard let match = windows(of: pid).first(where: { $0.layer == 0 && $0.bounds.height > 100 })
    ?? windows(of: pid, onScreen: false).first(where: { $0.layer == 0 && $0.bounds.height > 100 })
else { exit(1) }
print(match.number)
