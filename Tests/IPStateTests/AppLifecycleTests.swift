import Foundation
import Testing
import IPStateTestSupport
import IPStateCore
@testable import IPState

@MainActor
struct AppLifecycleTests {
    @Test func aVPNPathEventRestartsIPv6ChecksAtTheConfiguredInterval() async throws {
        let domain = "IPStatePathRetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = AppLookup()
        defer { Task { await client.releasePending() } }
        let lifecycle = TestLifecycle()
        let sleeper = TestSleeper()
        let app = AppModel(client: client, preferences: Preferences(defaults: defaults),
                           networkHealth: NetworkHealth(client: TestConnectivity()), history: IPHistory(defaults: defaults), notifications: NotificationService(center: TestNotificationCenter()),
                           lifecycle: lifecycle, sleep: { try await sleeper.sleep(for: $0) })
        defer { app.stop() }
        for _ in 0..<8 { await app.ipv6.refresh() }
        app.start()
        try #require(await eventually { app.ipv6.failureCount == 9 })
        lifecycle.networkChanged(true)
        try #require(await eventually { app.ipv6.failureCount == 1 })
        try #require(await eventually {
            let delays = await sleeper.remainingDelays
            return delays.count == 2 && delays.allSatisfy { $0 == .seconds(5) }
        })
        await client.enableIPv6()
        await sleeper.advance(by: .seconds(5))
        try #require(await eventually { app.ipv6.ip == "2001:db8::10" })
    }

    @Test func connectionAlertsPreserveLossThenRecoveryOrderDuringAuthorization() async throws {
        let domain = "IPStateAlertOrderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        preferences.notifyChanges = false
        preferences.notifyConnectionChanges = true
        let center = TestNotificationCenter()
        defer { center.pauseStatus = false; center.resumeStatus() }
        let lifecycle = TestLifecycle()
        let app = AppModel(client: AppLookup(), preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()), history: IPHistory(defaults: defaults),
                           notifications: NotificationService(center: center), lifecycle: lifecycle)
        defer { app.stop() }
        app.start()
        try #require(await eventually { app.ipv4.city == "Amsterdam" })
        center.pauseStatus = true
        lifecycle.networkChanged(false)
        try #require(await eventually { center.statusWaiting })
        lifecycle.networkChanged(true)
        try #require(await eventually { app.networkHealth.condition == .online })
        #expect(center.requests.isEmpty)
        center.resumeStatus()
        try #require(await eventually { center.requests.count == 2 })
        #expect(center.requests.map { $0.content.title } == ["Internet connection lost", "Internet connection restored"])
        #expect(center.requests.first?.content.body == "Last known IPv4: 203.0.113.10")
        #expect(center.requests.last?.content.body == "203.0.113.10")
    }

    @Test func startupWiresSilentBaselineHistoryAndOneLocatedAlert() async throws {
        let domain = "IPStateLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        let history = IPHistory(defaults: defaults)
        history.isEnabled = true
        let center = TestNotificationCenter()
        defer { center.pauseStatus = false; center.resumeStatus() }
        let lifecycle = TestLifecycle()
        let client = AppLookup()
        defer { Task { await client.releasePending() } }
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()), history: history,
                           notifications: NotificationService(center: center), lifecycle: lifecycle)
        defer { app.stop() }
        app.start()
        try #require(await eventually { app.ipv4.city == "Amsterdam" })
        #expect(history.entries.isEmpty)
        #expect(center.requests.isEmpty)
        await client.setIP("203.0.113.20", blockLocation: true)
        lifecycle.networkChanged(true)
        try #require(await eventually { history.entries.count == 1 })
        #expect(app.ipv4.ip == "203.0.113.20")
        #expect(center.requests.isEmpty)
        try #require(await eventually { await client.isLocating("203.0.113.20") })
        await client.completeLocation(for: "203.0.113.20")
        try #require(await eventually { center.requests.count == 1 })
        #expect(center.requests.first?.content.body == "203.0.113.20\nPrevious: 203.0.113.10")
        #expect(center.requests.first?.content.subtitle.contains("Amsterdam") == true)
        lifecycle.networkChanged(true)
        try #require(await eventually { await client.calls >= 3 })
        #expect(history.entries.count == 1)
        #expect(center.requests.count == 1)
        app.stop()
        let stoppedCalls = await client.calls
        lifecycle.networkChanged(true)
        #expect(await client.calls == stoppedCalls)
    }

    @Test func sleepCancelsQueuedAlertsAndWakeChecksEvenWhenPeriodicChecksAreOff() async throws {
        let domain = "IPStateSleepTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.notifyChanges = false
        preferences.notifyConnectionChanges = true
        let center = TestNotificationCenter()
        defer { center.pauseStatus = false; center.resumeStatus() }
        let lifecycle = TestLifecycle()
        let sleeper = TestSleeper()
        let client = AppLookup()
        defer { Task { await client.releasePending() } }
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()),
                           history: IPHistory(defaults: defaults),
                           notifications: NotificationService(center: center), lifecycle: lifecycle,
                           sleep: { try await sleeper.sleep(for: $0) })
        defer { app.stop() }
        app.start()
        try #require(await eventually { app.networkHealth.condition == .online })
        center.pauseStatus = true
        lifecycle.networkChanged(false)
        try #require(await eventually { center.statusWaiting })
        lifecycle.sleep()
        center.resumeStatus()
        try #require(await eventually { await sleeper.pendingCount == 0 })
        let callsBeforeSleep = await client.calls
        await sleeper.advance(by: .seconds(1000))
        app.refresh()
        #expect(await client.calls == callsBeforeSleep)
        #expect(center.requests.isEmpty)
        preferences.interval = .off
        lifecycle.wake(online: true)
        try #require(await eventually { await client.calls > callsBeforeSleep })
        try #require(await eventually { app.networkHealth.condition == .online })
        #expect(center.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func enablingIPAlertsDoesNotReviveChangesWaitingForLocation(alertsEnabledAtDetection: Bool) async throws {
        let domain = "IPStatePendingAlertTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        preferences.notifyChanges = alertsEnabledAtDetection
        let history = IPHistory(defaults: defaults)
        history.isEnabled = true
        let cache = IPLocationCache()
        let center = TestNotificationCenter()
        defer { center.pauseStatus = false; center.resumeStatus() }
        let lifecycle = TestLifecycle()
        let client = AppLookup()
        defer { Task { await client.releasePending() } }
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()),
                           locationCache: cache, history: history,
                           notifications: NotificationService(center: center), lifecycle: lifecycle)
        defer { app.stop() }
        app.start()
        try #require(await eventually { app.ipv4.city == "Amsterdam" })

        await client.setIP("203.0.113.20", blockLocation: true)
        lifecycle.networkChanged(true)
        try #require(await eventually { await client.isLocating("203.0.113.20") })
        #expect(history.entries.count == 1)
        #expect(center.requests.isEmpty)
        if alertsEnabledAtDetection { app.notificationsEnabled = false }
        app.notificationsEnabled = true
        await client.completeLocation(for: "203.0.113.20")
        try #require(await eventually { app.ipv4.city == "Amsterdam" })
        #expect(cache.location(for: "203.0.113.20")?.city == "Amsterdam")

        await client.setIP("203.0.113.30")
        lifecycle.networkChanged(true)
        try #require(await eventually {
            center.requests.contains { $0.content.body == "203.0.113.30\nPrevious: 203.0.113.20" }
        })
        #expect(center.requests.map { $0.content.body } == ["203.0.113.30\nPrevious: 203.0.113.20"])
        #expect(history.entries.count == 2)
    }

    @Test func disablingIPAlertsCancelsAnAlertWaitingForAuthorization() async throws {
        let domain = "IPStateAlertToggleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        let center = TestNotificationCenter()
        defer { center.pauseStatus = false; center.resumeStatus() }
        let lifecycle = TestLifecycle()
        let client = AppLookup()
        defer { Task { await client.releasePending() } }
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()),
                           history: IPHistory(defaults: defaults),
                           notifications: NotificationService(center: center), lifecycle: lifecycle)
        defer { app.stop() }
        app.start()
        try #require(await eventually { app.ipv4.city == "Amsterdam" })
        center.pauseStatus = true
        await client.setIP("203.0.113.20")
        lifecycle.networkChanged(true)
        try #require(await eventually { center.statusWaiting })
        app.notificationsEnabled = false
        let completedChecks = center.completedStatusChecks
        center.resumeStatus()
        try #require(await eventually { center.completedStatusChecks > completedChecks })
        #expect(center.requests.isEmpty)
    }
}
