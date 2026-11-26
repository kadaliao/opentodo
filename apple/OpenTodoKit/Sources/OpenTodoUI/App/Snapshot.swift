// `-OTSnapshot <file.png>` (debug builds, macOS): once the window has
// settled, draw it — title bar and toolbar included — into a PNG and quit.
// It needs no screen recording permission, unlike `screencapture`, but the
// drawing is AppKit's own (`cacheDisplay`): Liquid Glass and other
// materials — the whole sidebar column of a NavigationSplitView, for one —
// come out empty. Prefer `screencapture` where the permission is there. On iOS `xcrun simctl io … screenshot` is
// used instead and this does nothing.

import OpenTodoDomain
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SnapshotOnAppear: ViewModifier {
    let url: URL?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        #if os(macOS)
        content.task {
            guard let url else { return }
            // Seeding the demo can take a while on a busy machine; routes
            // wait for the data, so the picture does too (20 s at most).
            for _ in 0..<200 where !model.loaded { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(1.5))
            Snapshot.writeKeyWindow(to: url)
            NSApplication.shared.terminate(nil)
        }
        #else
        content
        #endif
    }
}

#if os(macOS)
enum Snapshot {
    static func writeKeyWindow(to url: URL) {
        let app = NSApplication.shared
        // A sheet open on the window (an editor) is drawn instead of the
        // window under it.
        let base = app.keyWindow ?? app.mainWindow ?? app.windows.first(where: \.isVisible)
        guard let window = base?.attachedSheet ?? base,
              let frameView = window.contentView?.superview
        else {
            FileHandle.standardError.write(Data("OTSnapshot: no window\n".utf8))
            return
        }
        let bounds = frameView.bounds
        guard let drawn = frameView.bitmapImageRepForCachingDisplay(in: bounds),
              let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return }
        frameView.cacheDisplay(in: bounds, to: drawn)
        // Glass and other materials draw nothing here: put the window's
        // background under the drawing so they come out as a plain surface.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        frameView.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        drawn.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            FileHandle.standardError.write(Data("OTSnapshot: \(error)\n".utf8))
        }
    }
}
#endif

#if os(macOS)
/// `-OTWindowSize`: sets its window's content size once it has one, over
/// the size the window was restored to.
struct DebugWindowSizer: NSViewRepresentable {
    let size: DebugWindowSize

    func makeNSView(context: Context) -> NSView { Probe(size: size) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        let size: DebugWindowSize
        private var done = false

        init(size: DebugWindowSize) {
            self.size = size
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !done else { return }
            done = true
            DispatchQueue.main.async { [size] in
                let top = window.frame.maxY
                window.setContentSize(NSSize(width: size.width, height: size.height))
                window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
                // Scripts start the app in the background while someone may
                // be using the machine: keep the window behind theirs
                // (`screencapture -l` captures it there all the same).
                window.orderBack(nil)
            }
        }
    }
}
#endif
