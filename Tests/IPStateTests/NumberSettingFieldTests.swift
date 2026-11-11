import AppKit
import SwiftUI
import Testing
import IPStateTestSupport
import IPStateCore
@testable import IPState

@MainActor
struct NumberSettingFieldTests {
    @Test func anUnfinishedHistoryCountDoesNotDeleteEntries() async throws {
        _ = NSApplication.shared
        let domain = "IPStateNumberFieldTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let history = IPHistory(defaults: defaults)
        history.isEnabled = true
        for index in 1...20 { history.record(IPChange(oldIP: "203.0.113.1", newIP: "203.0.113.\(index)")) }
        let host = NSHostingView(rootView: NumberSettingField("Keep", value: Binding(
            get: { history.retentionLimit }, set: { history.retentionLimit = $0 }
        )).frame(width: 80))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let field = try #require(findField(host))
        #expect(window.makeFirstResponder(field))
        field.stringValue = "2"
        field.currentEditor()?.string = "2"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        await Task.yield()
        #expect(history.retentionLimit == 20)
        #expect(history.entries.count == 20)
        field.stringValue = "25"
        field.currentEditor()?.string = "25"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        field.delegate?.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification,
                                                               object: field, userInfo: ["NSTextMovement": NSReturnTextMovement]))
        if let action = field.action { _ = field.sendAction(action, to: field.target) }
        #expect(await eventually { history.retentionLimit == 25 })
        #expect(history.entries.count == 20)
        field.stringValue = "invalid"
        field.currentEditor()?.string = "invalid"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        if let action = field.action { _ = field.sendAction(action, to: field.target) }
        #expect(history.retentionLimit == 25)
        #expect(history.entries.count == 20)
        #expect(window.makeFirstResponder(nil))
        #expect(window.makeFirstResponder(field))
        await Task.yield()
        field.stringValue = "15"
        field.currentEditor()?.string = "15"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(history.retentionLimit == 25)
        #expect(history.entries.count == 20)
        #expect(window.makeFirstResponder(nil))
        #expect(await eventually { history.retentionLimit == 15 })
        #expect(history.entries.count == 15)
    }

    private func findField(_ view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.compactMap { findField($0) }.first
    }
}
