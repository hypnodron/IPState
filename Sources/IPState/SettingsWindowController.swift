import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let controller: NSWindowController
    private var restoredFrame = false
    private var isApplyingBounds = false
    private static let minimumContentSize = NSSize(width: 560, height: 520)

    init<Content: View>(content: Content) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let hosting = NSHostingController(rootView: content)
        // AppKit owns the window bounds; SwiftUI must not replace them with content limits.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.title = "IP State Settings"
        window.identifier = NSUserInterfaceItemIdentifier("IPStateSettings")
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumContentSize
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.setContentSize(NSSize(width: 560, height: 600))
        controller = NSWindowController(window: window)
        super.init()
        window.delegate = self
        enforceMinimumSize()
    }

    func show() {
        if !restoredFrame {
            let restored = window.setFrameUsingName("IPStateSettings")
            window.setFrameAutosaveName("IPStateSettings")
            if !restored { window.center() }
            restoredFrame = true
        }
        enforceMinimumSize()
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        enforceMinimumSize()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        return NSSize(width: max(frameSize.width, minimum.width), height: max(frameSize.height, minimum.height))
    }

    func windowDidResize(_ notification: Notification) {
        enforceMinimumSize()
    }

    private func enforceMinimumSize() {
        guard !isApplyingBounds else { return }
        isApplyingBounds = true
        defer { isApplyingBounds = false }

        let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        if window.contentMinSize != Self.minimumContentSize { window.contentMinSize = Self.minimumContentSize }
        if window.minSize != minimum { window.minSize = minimum }
        let size = NSSize(width: max(window.frame.width, minimum.width), height: max(window.frame.height, minimum.height))
        guard size != window.frame.size else { return }
        var frame = window.frame
        frame.origin.y -= size.height - frame.height
        frame.size = size
        window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: window.isVisible)
    }
}
