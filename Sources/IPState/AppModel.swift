import AppKit
import Network
import Observation
import ServiceManagement
import IPStateCore

@MainActor @Observable
final class AppModel {
    let ipv4 = IPMonitor(client: LookupClient(), family: .ipv4)
    let ipv6 = IPMonitor(client: LookupClient(), family: .ipv6)
    let preferences = Preferences()
    let history = IPHistory()
    let notifications = NotificationService()
    let networkHealth = NetworkHealth()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginError: String?
    private(set) var displayFamily: IPFamily = .ipv4

    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var refreshTasks: [IPFamily: Task<Void, Never>] = [:]
    @ObservationIgnored private var timerTasks: [IPFamily: Task<Void, Never>] = [:]
    @ObservationIgnored private var connectionNotificationTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var hasStarted = false

    var monitor: IPMonitor { addressMonitor(for: displayFamily) }

    func addressMonitor(for family: IPFamily) -> IPMonitor { family == .ipv4 ? ipv4 : ipv6 }

    var title: String {
        return preferences.menuBarLayout.title(
            ip: monitor.ip, countryCode: monitor.countryCode, stale: false, country: countryName,
            city: monitor.city, cityCode: preferences.cityCode(city: monitor.city, countryCode: monitor.countryCode),
            cityLimit: preferences.cityCharacterLimit, countryLimit: preferences.countryCharacterLimit
        )
    }

    var countryName: String {
        guard let code = monitor.countryCode else { return "Country unavailable" }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    var locationName: String {
        guard let city = monitor.city else { return countryName }
        return "\(city), \(countryName)"
    }

    func notificationInfo(markStale: Bool = false) -> IPNotificationInfo {
        IPNotificationInfo(monitor: monitor, markStale: markStale)
    }

    var notificationsEnabled: Bool {
        get { preferences.notifyChanges }
        set {
            preferences.notifyChanges = newValue
            if newValue { Task { await notifications.requestAuthorizationIfNeeded() } }
        }
    }

    var connectionNotificationsEnabled: Bool {
        get { preferences.notifyConnectionChanges }
        set {
            preferences.notifyConnectionChanges = newValue
            if newValue { Task { await notifications.requestAuthorizationIfNeeded() } }
            else { cancelConnectionNotifications() }
        }
    }

    var anyNotificationsEnabled: Bool { preferences.notifyChanges || preferences.notifyConnectionChanges }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        preferences.onIntervalChange = { [weak self] in
            for family in IPFamily.allCases { self?.scheduleNextCheck(for: family) }
        }
        networkHealth.onConnectionChange = { [weak self] change in self?.notifyConnectionChange(change) }
        for family in IPFamily.allCases {
            addressMonitor(for: family).onChange = { [weak self] change in
                self?.history.record(change)
            }
            addressMonitor(for: family).onChangeWithLocation = { [weak self] change, location in
                guard let self else { return }
                guard preferences.notifyChanges else { return }
                Task { await self.notifications.send(change, location: location) }
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.networkChanged(online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.hypnodron.IPState.network"))

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isAsleep = false
                networkHealth.resetConnectionBaseline()
                refresh()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isAsleep = true
                networkHealth.resetConnectionBaseline()
                cancelConnectionNotifications()
                cancelPendingWork()
                for family in IPFamily.allCases { addressMonitor(for: family).cancelRefresh() }
            }
        })
        refresh()
        Task {
            if anyNotificationsEnabled { await notifications.requestAuthorizationIfNeeded() }
            else { await notifications.updateAuthorization() }
        }
    }

    func stop() {
        cancelConnectionNotifications()
        cancelPendingWork()
        for family in IPFamily.allCases { addressMonitor(for: family).cancelRefresh() }
        pathMonitor.cancel()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    func refresh() {
        for family in IPFamily.allCases { refresh(family) }
    }

    private func refresh(_ family: IPFamily) {
        timerTasks[family]?.cancel()
        refreshTasks[family]?.cancel()
        let monitor = addressMonitor(for: family)
        monitor.cancelRefresh()
        guard !monitor.isOffline, !isAsleep else { return }
        refreshTasks[family] = Task { [weak self] in
            guard let self else { return }
            await monitor.refresh()
            guard !Task.isCancelled else { return }
            displayFamily = .automatic(ipv4: ipv4, ipv6: ipv6, previous: displayFamily)
            await networkHealth.update(monitors: [ipv4, ipv6])
            guard !Task.isCancelled else { return }
            scheduleNextCheck(for: family)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow IP State in System Settings → General → Login Items."
                : nil
        } catch {
            loginError = "Could not change launch at login: \(error.localizedDescription)"
        }
        syncLoginStatus()
    }

    func syncLoginStatus() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    private func notifyConnectionChange(_ change: ConnectionChange) {
        guard preferences.notifyConnectionChanges, !isAsleep else { return }
        let info = notificationInfo(markStale: change == .lost)
        let previous = connectionNotificationTask
        connectionNotificationTask = Task { [weak self] in
            // Keep loss and recovery in order, including during permission checks.
            await withTaskCancellationHandler {
                await previous?.value
            } onCancel: {
                previous?.cancel()
            }
            guard let self, !Task.isCancelled, !isAsleep, preferences.notifyConnectionChanges else { return }
            await notifications.send(change, info: info)
        }
    }

    private func cancelConnectionNotifications() {
        connectionNotificationTask?.cancel()
        connectionNotificationTask = nil
    }

    private func networkChanged(online: Bool) {
        cancelPendingWork()
        networkHealth.pathChanged(available: online)
        for family in IPFamily.allCases {
            let monitor = addressMonitor(for: family)
            monitor.cancelRefresh(markStale: true)
            monitor.setOffline(!online)
        }
        if online { refresh() }
    }

    private func scheduleNextCheck(for family: IPFamily) {
        timerTasks[family]?.cancel()
        let monitor = addressMonitor(for: family)
        guard !isAsleep, !monitor.isOffline,
              let delay = preferences.interval.delay(afterFailures: monitor.failureCount) else { return }
        timerTasks[family] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh(family)
        }
    }

    private func cancelPendingWork() {
        for task in timerTasks.values { task.cancel() }
        for task in refreshTasks.values { task.cancel() }
        timerTasks.removeAll()
        refreshTasks.removeAll()
    }
}
