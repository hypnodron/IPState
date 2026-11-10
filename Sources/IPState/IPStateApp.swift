import SwiftUI
import AppKit
import IPStateCore

@main
struct IPStateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            IPStateMenu(model: delegate.model, showSettings: { delegate.showSettings() })
        } label: {
            MenuBarStatusLabel(title: delegate.model.title, condition: delegate.model.networkHealth.condition,
                               isStale: delegate.model.monitor.isStale && delegate.model.monitor.ip != nil)
        }
        .menuBarExtraStyle(.menu)

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(locationCache: IPLocationCache(defaults: UserDefaults(suiteName: "IPStateSettings")))
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) { model.start() }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(content: SettingsView(model: model))
        }
        settingsController?.show()
        model.syncLoginStatus()
        Task { await model.notifications.updateAuthorization() }
    }
}

private struct IPStateMenu: View {
    let model: AppModel
    let showSettings: () -> Void

    var body: some View {
        Text(model.networkHealth.condition.description)
        Divider()
        ForEach(IPFamily.allCases, id: \.self) { family in
            Section(family.label) {
                AddressSummary(monitor: model.addressMonitor(for: family))
            }
        }
        Divider()
        ForEach(IPFamily.allCases, id: \.self) { family in
            Button("Copy \(family.label)") {
                if let ip = model.addressMonitor(for: family).ip { copy(ip) }
            }
            .disabled(model.addressMonitor(for: family).ip == nil)
        }
        Button(model.monitor.isRefreshing ? "Refreshing…" : "Refresh Now") { model.refresh() }
            .keyboardShortcut("r")
            .disabled(model.monitor.isOffline || model.monitor.isRefreshing)
        if model.history.isEnabled {
            Menu("Recent IP Changes") {
                if model.history.entries.isEmpty { Text("No IP changes recorded") }
                ForEach(model.history.entries) { entry in
                    Menu("\(entry.date.formatted(date: .abbreviated, time: .standard)) · \(entry.change.family.label)") {
                        Text("Previous: \(entry.change.oldIP)")
                        Button("Copy new IP: \(entry.change.newIP)") { copy(entry.change.newIP) }
                    }
                }
                if let message = model.history.errorMessage { Text(message) }
                Divider()
                Button("Clear History", role: .destructive) { model.history.clear() }
                    .disabled(model.history.entries.isEmpty && model.history.errorMessage == nil)
            }
        }
        Divider()
        Button("Settings…") {
            showSettings()
        }
            .keyboardShortcut(",")
        Button("Quit IP State") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func copy(_ ip: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
    }
}

private struct AddressSummary: View {
    let monitor: IPMonitor
    @Environment(\.locale) private var locale

    var body: some View {
        let info = IPNotificationInfo(monitor: monitor)
        let location = info.locationText(locale: locale)
        if !location.isEmpty {
            Text(location)
        }
        Text(monitor.ip == nil && monitor.isRefreshing ? "Checking…" : info.addressText)
        if let date = monitor.lastSuccess {
            Text("Updated \(date.formatted(date: .omitted, time: .standard))")
        }
        if monitor.isOffline {
            Text("Offline")
        } else if monitor.isStale {
            if let message = monitor.lastError { Text(message) }
        }
        if let message = monitor.lastLocationError { Text(message) }
    }
}
