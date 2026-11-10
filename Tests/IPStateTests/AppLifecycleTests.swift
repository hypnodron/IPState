import Foundation
import Testing
import IPStateCore
@testable import IPState

@MainActor
struct AppLifecycleTests {
    @Test func aVPNPathEventRestartsIPv6ChecksAtTheConfiguredInterval() async {
        let domain = "IPStatePathRetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = AppLookup()
        let lifecycle = TestLifecycle()
        let sleeper = TestSleeper()
        let app = AppModel(client: client, preferences: Preferences(defaults: defaults),
                           networkHealth: NetworkHealth(client: TestConnectivity()), history: IPHistory(defaults: defaults), notifications: NotificationService(center: TestNotificationCenter()),
                           lifecycle: lifecycle, sleep: { try await sleeper.sleep(for: $0) })
        defer { app.stop() }
        for _ in 0..<8 { await app.ipv6.refresh() }
        app.start()
        #expect(await eventually { app.ipv6.failureCount == 9 })
        lifecycle.networkChanged(true)
        #expect(await eventually { app.ipv6.failureCount == 1 })
        #expect(await eventually {
            let delays = await sleeper.remainingDelays
            return delays.count == 2 && delays.allSatisfy { $0 == .seconds(5) }
        })
        await client.enableIPv6()
        await sleeper.advance(by: .seconds(5))
        #expect(await eventually { app.ipv6.ip == "2001:db8::10" })
    }

    @Test func connectionAlertsPreserveLossThenRecoveryOrderDuringAuthorization() async {
        let domain = "IPStateAlertOrderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        preferences.notifyChanges = false
        preferences.notifyConnectionChanges = true
        let center = TestNotificationCenter()
        let lifecycle = TestLifecycle()
        let app = AppModel(client: AppLookup(), preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()), history: IPHistory(defaults: defaults),
                           notifications: NotificationService(center: center), lifecycle: lifecycle)
        defer { app.stop() }
        app.start()
        #expect(await eventually { app.ipv4.city == "Amsterdam" })
        center.pauseStatus = true
        lifecycle.networkChanged(false)
        #expect(await eventually { center.statusWaiting })
        lifecycle.networkChanged(true)
        #expect(await eventually { app.networkHealth.condition == .online })
        #expect(center.requests.isEmpty)
        center.resumeStatus()
        #expect(await eventually { center.requests.count == 2 })
        #expect(center.requests.map { $0.content.title } == ["Internet connection lost", "Internet connection restored"])
        #expect(center.requests.first?.content.body == "Last known IPv4: 203.0.113.10")
        #expect(center.requests.last?.content.body == "203.0.113.10")
    }

    @Test func startupWiresSilentBaselineHistoryAndOneLocatedAlert() async {
        let domain = "IPStateLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        let history = IPHistory(defaults: defaults)
        history.isEnabled = true
        let center = TestNotificationCenter()
        let lifecycle = TestLifecycle()
        let client = AppLookup()
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()), history: history,
                           notifications: NotificationService(center: center), lifecycle: lifecycle)
        defer { app.stop() }
        app.start()
        #expect(await eventually { app.ipv4.city == "Amsterdam" })
        #expect(history.entries.isEmpty)
        #expect(center.requests.isEmpty)
        await client.setIP("203.0.113.20", blockLocation: true)
        lifecycle.networkChanged(true)
        #expect(await eventually { history.entries.count == 1 })
        #expect(app.ipv4.ip == "203.0.113.20")
        #expect(center.requests.isEmpty)
        #expect(await eventually { await client.isLocating("203.0.113.20") })
        await client.completeLocation(for: "203.0.113.20")
        #expect(await eventually { center.requests.count == 1 })
        #expect(center.requests.first?.content.body == "203.0.113.20\nPrevious: 203.0.113.10")
        #expect(center.requests.first?.content.subtitle.contains("Amsterdam") == true)
        lifecycle.networkChanged(true)
        #expect(await eventually { await client.calls >= 3 })
        #expect(history.entries.count == 1)
        #expect(center.requests.count == 1)
        app.stop()
        let stoppedCalls = await client.calls
        lifecycle.networkChanged(true)
        #expect(await client.calls == stoppedCalls)
    }

    @Test func sleepCancelsQueuedAlertsAndWakeChecksEvenWhenPeriodicChecksAreOff() async {
        let domain = "IPStateSleepTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.notifyChanges = false
        preferences.notifyConnectionChanges = true
        let center = TestNotificationCenter()
        let lifecycle = TestLifecycle()
        let sleeper = TestSleeper()
        let client = AppLookup()
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()),
                           history: IPHistory(defaults: defaults),
                           notifications: NotificationService(center: center), lifecycle: lifecycle,
                           sleep: { try await sleeper.sleep(for: $0) })
        defer { app.stop() }
        app.start()
        #expect(await eventually { app.networkHealth.condition == .online })
        center.pauseStatus = true
        lifecycle.networkChanged(false)
        #expect(await eventually { center.statusWaiting })
        lifecycle.sleep()
        center.resumeStatus()
        #expect(await eventually { await sleeper.pendingCount == 0 })
        let callsBeforeSleep = await client.calls
        await sleeper.advance(by: .seconds(1000))
        app.refresh()
        #expect(await client.calls == callsBeforeSleep)
        #expect(center.requests.isEmpty)
        preferences.interval = .off
        lifecycle.wake(online: true)
        #expect(await eventually { await client.calls > callsBeforeSleep })
        #expect(await eventually { app.networkHealth.condition == .online })
        #expect(center.requests.isEmpty)
    }

    @Test func disablingIPAlertsCancelsAnAlertWaitingForAuthorization() async throws {
        let domain = "IPStateAlertToggleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        let center = TestNotificationCenter()
        let lifecycle = TestLifecycle()
        let client = AppLookup()
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()),
                           history: IPHistory(defaults: defaults),
                           notifications: NotificationService(center: center), lifecycle: lifecycle)
        defer { app.stop() }
        app.start()
        #expect(await eventually { app.ipv4.city == "Amsterdam" })
        center.pauseStatus = true
        await client.setIP("203.0.113.20")
        lifecycle.networkChanged(true)
        #expect(await eventually { center.statusWaiting })
        app.notificationsEnabled = false
        center.resumeStatus()
        try await Task.sleep(for: .milliseconds(30))
        #expect(center.requests.isEmpty)
    }
}
