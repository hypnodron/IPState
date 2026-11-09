import SwiftUI
import UserNotifications
import IPStateCore

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                MenuBarSettingsView(model: model)
                GeneralSettingsView(model: model)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 560, idealWidth: 560, maxWidth: .infinity,
               minHeight: 520, idealHeight: 600, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.notifications.updateAuthorization()
            model.syncLoginStatus()
        }
    }
}

private struct SettingsHelp: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuBarSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences

        GroupBox("Menu bar") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Preview") {
                    Text(model.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                List {
                    ForEach(preferences.menuBarLayout.order) { component in
                        HStack(spacing: 10) {
                            Toggle(component.label, isOn: $preferences[shows: component])
                                .toggleStyle(.checkbox)
                                .help(component == .ip ? "Automatically uses IPv4 when available, otherwise IPv6." : component.label)
                            Spacer(minLength: 8)
                            componentOptions(component)
                            if let index = preferences.menuBarLayout.order.firstIndex(of: component) {
                                Button {
                                    preferences.moveMenuBarItems(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .disabled(index == 0)
                                .help("Move up")
                                .accessibilityLabel("Move \(component.label) up")
                                Button {
                                    preferences.moveMenuBarItems(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .disabled(index == preferences.menuBarLayout.order.count - 1)
                                .help("Move down")
                                .accessibilityLabel("Move \(component.label) down")
                            }
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                                .help("Drag to reorder")
                                .accessibilityHidden(true)
                        }
                        // Keep rows aligned when optional text fields appear.
                        .frame(height: 28)
                        .listRowInsets(EdgeInsets())
                        .buttonStyle(.borderless)
                    }
                    .onMove { source, destination in
                        preferences.moveMenuBarItems(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 28)
                .frame(height: 180)

                VStack(alignment: .leading, spacing: 2) {
                    SettingsHelp("Drag rows or use the arrows to reorder.")
                    let showsNameLimits = !preferences.menuBarLayout.enabled.isDisjoint(with: [.city, .country])
                    // Reserve the note's height so the sections below stay in place.
                    SettingsHelp("A name limit of 0 means no limit. Longer names end with …")
                        .opacity(showsNameLimits ? 1 : 0)
                        .accessibilityHidden(!showsNameLimits)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func componentOptions(_ component: MenuBarComponent) -> some View {
        @Bindable var preferences = model.preferences

        switch component {
        case .country where preferences.menuBarLayout.enabled.contains(.country):
            NameLimitField("Country name limit", value: $preferences.countryCharacterLimit)
        case .city where preferences.menuBarLayout.enabled.contains(.city):
            NameLimitField("City name limit", value: $preferences.cityCharacterLimit)
        case .cityCode where preferences.menuBarLayout.enabled.contains(.cityCode):
            if let city = model.monitor.city {
                let key = Preferences.cityKey(city: city, countryCode: model.monitor.countryCode)
                TextField("City code", text: $preferences[cityCodeFor: key], prompt: Text(suggestedCityCode(city)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .help("Leave empty to use \(suggestedCityCode(city)) for \(city).")
            } else {
                Text("Waiting for city…")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        default:
            EmptyView()
        }
    }
}

private struct NameLimitField: View {
    let title: String
    @Binding var value: Int

    init(_ title: String, value: Binding<Int>) {
        self.title = title
        _value = value
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("Max")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            NumberSettingField(title, value: $value)
                .frame(width: 44)
            Text("characters")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .help("0 means no limit.")
    }
}

private struct GeneralSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var history = model.history

        VStack(spacing: 8) {
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("Start at login", isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        Spacer()
                        Text("Check IP every")
                        Picker("Check IP every", selection: $preferences.interval) {
                            ForEach(RefreshInterval.allCases, id: \.self) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 110)
                    }
                    SettingsHelp("Also checks on wake and network changes, even when periodic checks are off.")
                    if let message = model.loginError { SettingsHelp(message) }
                }
                .padding(4)
                .frame(maxWidth: .infinity)
            }

            GroupBox("Notifications") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("Notify when IP changes", isOn: $model.notificationsEnabled)
                        Spacer()
                        Button(model.notifications.isSendingTest ? "Sending…" : "Test Notification") {
                            let info = model.notificationInfo()
                            Task { await model.notifications.sendTest(info) }
                        }
                        .controlSize(.small)
                        .disabled(model.notifications.isSendingTest)
                    }
                    HStack {
                        Toggle("Notify when connection is lost or restored", isOn: $model.connectionNotificationsEnabled)
                        Spacer(minLength: 8)
                        if model.anyNotificationsEnabled {
                            if model.notifications.authorization == .denied {
                                Button("Open System Settings") {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                                }
                                .controlSize(.small)
                            } else if model.notifications.authorization == .notDetermined {
                                Button("Allow Notifications…") {
                                    Task { await model.notifications.requestAuthorizationIfNeeded() }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    SettingsHelp(model.anyNotificationsEnabled && model.notifications.authorization == .denied
                                 ? "Notifications are blocked. Enable them in System Settings → Notifications."
                                 : "Manage banners and sounds in System Settings → Notifications.")
                    if let result = model.notifications.testResult { SettingsHelp(result) }
                    if let message = model.notifications.errorMessage { SettingsHelp(message) }
                }
                .padding(4)
                .frame(maxWidth: .infinity)
            }

            GroupBox("History") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("Keep recent IP changes", isOn: $history.isEnabled)
                        if history.isEnabled {
                            Spacer()
                            Text("Keep")
                            NumberSettingField("Recent changes to keep", value: $history.retentionLimit)
                                .frame(width: 52)
                            Text("changes")
                        }
                    }
                    SettingsHelp(history.isEnabled
                                 ? "Keep 1–200 changes on this Mac. Reducing the count removes older entries; turning history off clears them."
                                 : "Saved only on this Mac. Turning this off clears saved history.")
                    if let message = history.errorMessage { SettingsHelp(message) }
                }
                .padding(4)
                .frame(maxWidth: .infinity)
            }
        }
        .toggleStyle(.checkbox)
    }
}
