import AppKit
import SwiftUI
import Testing
import IPStateCore
@testable import IPState

@MainActor
struct SettingsWindowTests {
    @Test func actualSettingsContentRendersAtItsMinimumWindowSize() async throws {
        _ = NSApplication.shared
        let domain = "IPStateSettingsLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarLayout = MenuBarLayout(enabled: Set(MenuBarComponent.allCases))
        let center = TestNotificationCenter()
        center.status = .denied
        let history = IPHistory(defaults: defaults)
        history.isEnabled = true
        let model = AppModel(client: AppLookup(), preferences: preferences,
                             networkHealth: NetworkHealth(client: TestConnectivity()), history: history,
                             notifications: NotificationService(center: center), lifecycle: TestLifecycle())
        defer { model.stop() }
        await model.ipv4.refresh()
        await model.notifications.updateAuthorization()
        let controller = SettingsWindowController(content: SettingsView(model: model))
        defer { controller.window.close() }
        controller.window.setContentSize(NSSize(width: 560, height: 520))
        controller.window.contentView?.layoutSubtreeIfNeeded()
        #expect((controller.window.contentView?.fittingSize.width ?? 0) <= 561)
        #expect(controller.window.contentView?.bounds.width == 560)
        let view = try #require(controller.window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(atPath: "build/review", withIntermediateDirectories: true)
        try image.write(to: URL(fileURLWithPath: "build/review/fixed-settings-minimum.png"))
        controller.window.setContentSize(NSSize(width: 560, height: 600))
        view.layoutSubtreeIfNeeded()
        let defaultBitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: defaultBitmap)
        let defaultImage = try #require(defaultBitmap.representation(using: .png, properties: [:]))
        try defaultImage.write(to: URL(fileURLWithPath: "build/review/fixed-settings-default.png"))
    }

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
