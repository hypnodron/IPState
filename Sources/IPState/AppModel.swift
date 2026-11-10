import Observation
import ServiceManagement
import IPStateCore

@MainActor @Observable
final class AppModel {
    let ipv4: IPMonitor
    let ipv6: IPMonitor
    let preferences: Preferences
    let history: IPHistory
    @ObservationIgnored private let notificationOverride: NotificationService?
    @ObservationIgnored lazy var notifications = notificationOverride ?? NotificationService()
    let networkHealth: NetworkHealth
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginError: String?
    private(set) var displayFamily: IPFamily = .ipv4

    @ObservationIgnored private let lifecycle: any AppLifecycleMonitoring
    @ObservationIgnored private var refreshTasks: [IPFamily: Task<Void, Never>] = [:]
    @ObservationIgnored private var timerTasks: [IPFamily: Task<Void, Never>] = [:]
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var connectionNotificationTask: Task<Void, Never>?
    @ObservationIgnored private var ipNotificationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingIPAlerts: [IPFamily: IPChange] = [:]
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    init(client: any IPLookingUp = LookupClient(), preferences: Preferences = Preferences(),
         networkHealth: NetworkHealth = NetworkHealth(), locationCache: IPLocationCache = IPLocationCache(),
         history: IPHistory = IPHistory(), notifications: NotificationService? = nil,
         lifecycle: any AppLifecycleMonitoring = SystemAppLifecycleMonitor(),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        ipv4 = IPMonitor(client: client, family: .ipv4, locationCache: locationCache)
        ipv6 = IPMonitor(client: client, family: .ipv6, locationCache: locationCache)
        self.preferences = preferences
        self.networkHealth = networkHealth
        self.history = history
        self.notificationOverride = notifications
        self.lifecycle = lifecycle
        self.sleep = sleep
        for family in IPFamily.allCases {
            addressMonitor(for: family).onAddressResolved = { [weak self] in
                guard let self else { return }
                displayFamily = .automatic(ipv4: ipv4, ipv6: ipv6, previous: displayFamily)
                networkHealth.lookupSucceeded()
                scheduleRecoveryCheck()
            }
        }
        preferences.onIntervalChange = { [weak self] in
            guard let self else { return }
            for family in IPFamily.allCases { scheduleNextCheck(for: family) }
            scheduleRecoveryCheck()
        }
    }

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
            else { cancelIPNotifications() }
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
        isRunning = true
        networkHealth.onConnectionChange = { [weak self] change in self?.notifyConnectionChange(change) }
        for family in IPFamily.allCases {
            addressMonitor(for: family).onChange = { [weak self] change in
                guard let self, isRunning else { return }
                history.record(change)
                // Capture eligibility before location enrichment can outlive the alert setting.
                pendingIPAlerts[change.family] = preferences.notifyChanges ? change : nil
            }
            addressMonitor(for: family).onChangeWithLocation = { [weak self] change, location in
                guard let self, isRunning else { return }
                notifyIPChange(change, location: location)
            }
        }
        lifecycle.start(networkChanged: { [weak self] online in
            guard let self, isRunning else { return }
            networkChanged(online: online)
        }, willSleep: { [weak self] in
            guard let self, isRunning else { return }
            isAsleep = true
            networkHealth.resetConnectionBaseline()
            cancelConnectionNotifications()
            cancelPendingWork()
            for family in IPFamily.allCases { addressMonitor(for: family).cancelRefresh() }
        }, didWake: { [weak self] online in
            guard let self, isRunning else { return }
            isAsleep = false
            networkHealth.resetConnectionBaseline()
            networkChanged(online: online)
        })
        refresh()
        Task {
            if anyNotificationsEnabled { await notifications.requestAuthorizationIfNeeded() }
            else { await notifications.updateAuthorization() }
        }
    }

    func stop() {
        isRunning = false
        cancelIPNotifications()
        cancelConnectionNotifications()
        cancelPendingWork()
        for family in IPFamily.allCases { addressMonitor(for: family).cancelRefresh() }
        lifecycle.stop()
    }

    func refresh() {
        for family in IPFamily.allCases { refresh(family) }
    }

    private func refresh(_ family: IPFamily) {
        timerTasks[family]?.cancel()
        refreshTasks[family]?.cancel()
        let monitor = addressMonitor(for: family)
        guard !monitor.isOffline, !isAsleep else { return }
        refreshTasks[family] = Task { [weak self] in
            guard let self else { return }
            await monitor.refreshAddress()
            guard !Task.isCancelled else { return }
            displayFamily = .automatic(ipv4: ipv4, ipv6: ipv6, previous: displayFamily)
            await networkHealth.update(monitors: [ipv4, ipv6])
            guard !Task.isCancelled else { return }
            scheduleNextCheck(for: family)
            scheduleRecoveryCheck()
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

    private func notifyIPChange(_ change: IPChange, location: IPLocation?) {
        guard pendingIPAlerts[change.family] == change else { return }
        pendingIPAlerts[change.family] = nil
        guard preferences.notifyChanges, isRunning else { return }
        let previous = ipNotificationTask
        ipNotificationTask = Task { [weak self] in
            await withTaskCancellationHandler {
                await previous?.value
            } onCancel: {
                previous?.cancel()
            }
            guard let self, !Task.isCancelled, isRunning, preferences.notifyChanges else { return }
            await notifications.send(change, location: location)
        }
    }

    private func cancelIPNotifications() {
        pendingIPAlerts.removeAll()
        ipNotificationTask?.cancel()
        ipNotificationTask = nil
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
        timerTasks[family] = Task { [weak self, sleep] in
            do { try await sleep(.seconds(delay)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh(family)
        }
    }

    private func cancelPendingWork() {
        networkHealth.cancelPendingCheck()
        recoveryTask?.cancel()
        recoveryTask = nil
        for task in timerTasks.values { task.cancel() }
        for task in refreshTasks.values { task.cancel() }
        timerTasks.removeAll()
        refreshTasks.removeAll()
    }

    private func scheduleRecoveryCheck() {
        guard !isAsleep, preferences.interval != .off else {
            recoveryTask?.cancel()
            recoveryTask = nil
            return
        }
        // A normal refresh may share the successful probe. Let its recovery continuation refresh the addresses.
        if networkHealth.condition == .lookupUnavailable, recoveryTask != nil { return }
        guard networkHealth.condition == .unreachable else {
            recoveryTask?.cancel()
            recoveryTask = nil
            return
        }
        guard recoveryTask == nil else { return }
        recoveryTask = Task { [weak self, sleep] in
            do { try await sleep(.seconds(3)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            let recovered = await networkHealth.checkRecovery()
            guard !Task.isCancelled else { return }
            recoveryTask = nil
            if recovered || networkHealth.condition == .lookupUnavailable { refresh() }
            else { scheduleRecoveryCheck() }
        }
    }
}
