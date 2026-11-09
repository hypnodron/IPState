import Foundation
import Testing
@testable import IPStateCore

private actor ConnectionLookup: IPLookingUp {
    var available = true
    func setAvailable(_ value: Bool) { available = value }
    func publicIPv4() async throws -> String {
        guard available else { throw URLError(.cannotConnectToHost) }
        return "203.0.113.10"
    }
    func location(for ip: String) async throws -> IPLocation { IPLocation(countryCode: "NL", city: nil) }
}

private actor ConnectionProbe: ConnectivityChecking {
    var reachable: Bool
    init(reachable: Bool) { self.reachable = reachable }
    func setReachable(_ value: Bool) { reachable = value }
    func isInternetReachable() async -> Bool { reachable }
}

@MainActor
struct ConnectionAlertTests {
    @Test func lossAndRecoveryEmitOnceAcrossDuplicateUpdatesAndUnavailableIPv6() async {
        let client = ConnectionLookup()
        let ipv4 = IPMonitor(client: client)
        let ipv6 = IPMonitor(client: client, family: .ipv6)
        let health = NetworkHealth(client: ConnectionProbe(reachable: false))
        var changes: [ConnectionChange] = []
        health.onConnectionChange = { changes.append($0) }

        health.pathChanged(available: true)
        await ipv4.refresh()
        await ipv6.refresh()
        await health.update(monitors: [ipv4, ipv6])
        await health.update(monitors: [ipv4, ipv6])
        #expect(changes.isEmpty)

        health.pathChanged(available: false)
        health.pathChanged(available: false)
        #expect(changes == [.lost])
        health.pathChanged(available: true)
        #expect(changes == [.lost])
        await ipv4.refresh()
        await health.update(monitors: [ipv4, ipv6])
        await health.update(monitors: [ipv4, ipv6])
        #expect(changes == [.lost, .restored])
    }

    @Test func anUnreachableInternetCountsAsLossAndProbeSuccessConfirmsRecovery() async {
        let client = ConnectionLookup()
        let monitor = IPMonitor(client: client)
        let probe = ConnectionProbe(reachable: false)
        let health = NetworkHealth(client: probe)
        var changes: [ConnectionChange] = []
        health.onConnectionChange = { changes.append($0) }
        health.pathChanged(available: true)
        await monitor.refresh()
        await health.update(monitors: [monitor])

        await client.setAvailable(false)
        health.pathChanged(available: true)
        await monitor.refresh()
        await health.update(monitors: [monitor])
        #expect(health.condition == .unreachable)
        #expect(changes == [.lost])

        health.pathChanged(available: false)
        #expect(changes == [.lost])
        health.pathChanged(available: true)
        await probe.setReachable(true)
        await health.update(monitors: [monitor])
        #expect(health.condition == .lookupUnavailable)
        #expect(changes == [.lost, .restored])
    }

    @Test func lookupServiceFailuresAndConnectionChecksDoNotCountAsOutages() async {
        let client = ConnectionLookup()
        let monitor = IPMonitor(client: client)
        let health = NetworkHealth(client: ConnectionProbe(reachable: true))
        var changes: [ConnectionChange] = []
        health.onConnectionChange = { changes.append($0) }
        health.pathChanged(available: true)
        await monitor.refresh()
        await health.update(monitors: [monitor])

        await client.setAvailable(false)
        health.pathChanged(available: true)
        await monitor.refresh()
        await health.update(monitors: [monitor])
        #expect(health.condition == .lookupUnavailable)
        #expect(changes.isEmpty)
        health.pathChanged(available: true)
        #expect(changes.isEmpty)
        health.pathChanged(available: false)
        #expect(changes == [.lost])
    }

    @Test func launchingOfflineSetsASilentBaselineThenReportsRecovery() async {
        let monitor = IPMonitor(client: ConnectionLookup())
        let health = NetworkHealth(client: ConnectionProbe(reachable: true))
        var changes: [ConnectionChange] = []
        health.onConnectionChange = { changes.append($0) }
        health.pathChanged(available: false)
        #expect(changes.isEmpty)
        health.pathChanged(available: true)
        await monitor.refresh()
        await health.update(monitors: [monitor])
        #expect(changes == [.restored])
    }

    @Test func resettingTheBaselineSuppressesSleepAndWakeTransitions() async {
        let monitor = IPMonitor(client: ConnectionLookup())
        let health = NetworkHealth(client: ConnectionProbe(reachable: true))
        var changes: [ConnectionChange] = []
        health.onConnectionChange = { changes.append($0) }
        health.pathChanged(available: true)
        await monitor.refresh()
        await health.update(monitors: [monitor])

        health.resetConnectionBaseline()
        health.pathChanged(available: false)
        health.resetConnectionBaseline()
        health.pathChanged(available: true)
        await monitor.refresh()
        await health.update(monitors: [monitor])
        #expect(changes.isEmpty)
        health.pathChanged(available: false)
        #expect(changes == [.lost])
    }

    @Test func connectionAlertsDefaultToOffAndPersistIndependentlyOfIPAlerts() {
        let domain = "IPStateConnectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.notifyConnectionChanges)
        preferences.notifyChanges = false
        preferences.notifyConnectionChanges = true
        let restored = Preferences(defaults: defaults)
        #expect(restored.notifyConnectionChanges)
        #expect(!restored.notifyChanges)
    }
}
