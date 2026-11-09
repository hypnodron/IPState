import AppKit
import SwiftUI
import Testing
@testable import IPState

@MainActor
struct SettingsWindowTests {
    @Test func settingsWindowHasAnActualResizeStyleAndFlexibleBounds() {
        _ = NSApplication.shared
        let controller = SettingsWindowController(content: Color.clear.frame(width: 560, height: 760))
        let window = controller.window
        defer { window.isReleasedWhenClosed = false; window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.styleMask.contains(.resizable))
        #expect(window.contentMinSize == NSSize(width: 560, height: 520))
        #expect(window.contentMaxSize.width > 2000)
        #expect(window.contentMaxSize.height > 2000)
    }

    @Test func hostingContentDoesNotClampTheWindowToItsOriginalSize() {
        _ = NSApplication.shared
        let controller = SettingsWindowController(content: Color.clear.frame(width: 560, height: 760))
        let window = controller.window
        defer { window.isReleasedWhenClosed = false; window.close() }
        window.setContentSize(NSSize(width: 800, height: 900))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(abs((window.contentView?.bounds.width ?? 0) - 800) < 1)
        #expect(abs((window.contentView?.bounds.height ?? 0) - 900) < 1)
        #expect(!window.isReleasedWhenClosed)
    }

    @Test func nativeFrameMinimumPreventsClippingTheSettingsContent() {
        _ = NSApplication.shared
        let controller = SettingsWindowController(content: Color.clear.frame(minWidth: 560, minHeight: 520))
        let window = controller.window
        defer { window.isReleasedWhenClosed = false; window.close() }
        let minimum = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 560, height: 520)).size
        #expect(window.minSize.width >= minimum.width)
        #expect(window.minSize.height >= minimum.height)
        let dragSize = window.delegate?.windowWillResize?(window, to: NSSize(width: 200, height: 200))
        #expect(dragSize != nil)
        #expect((dragSize?.width ?? 0) >= minimum.width)
        #expect((dragSize?.height ?? 0) >= minimum.height)
    }

    @Test func anUndersizedRestoredFrameGetsExpanded() {
        _ = NSApplication.shared
        let controller = SettingsWindowController(content: Color.clear.frame(minWidth: 560, minHeight: 520))
        let window = controller.window
        defer { window.isReleasedWhenClosed = false; window.close() }
        window.setFrame(NSRect(x: 100, y: 100, width: 240, height: 300), display: false)
        #expect(window.contentView!.bounds.width >= 560)
        #expect(window.contentView!.bounds.height >= 520)
    }
}
