import Foundation
import Testing
import IPStateCore
@testable import IPState

private actor RecoveryLookup: IPLookingUp {
    private let family: IPFamily
    private var locationRequest: CheckedContinuation<Void, Never>?
    private var locationResult: CheckedContinuation<IPLocation, Never>?

    init(family: IPFamily) { self.family = family }
    func publicIPv4() async throws -> String {
        if family == .ipv4 { return "203.0.113.10" }
        try await Task.sleep(for: .seconds(60))
        throw URLError(.cannotConnectToHost)
    }
    func publicIPv6() async throws -> String {
        if family == .ipv6 { return "2001:db8::10" }
        try await Task.sleep(for: .seconds(60))
        throw URLError(.cannotConnectToHost)
    }
    func location(for ip: String) async throws -> IPLocation {
        await withCheckedContinuation {
            locationResult = $0
            locationRequest?.resume()
            locationRequest = nil
        }
    }
    func waitForLocation() async {
        if locationResult != nil { return }
        await withCheckedContinuation { locationRequest = $0 }
    }
    func completeLocation() {
        locationResult?.resume(returning: IPLocation(countryCode: "NL", city: "Amsterdam"))
        locationResult = nil
    }
}

private struct UnavailableLookup: IPLookingUp {
    func publicIPv4() async throws -> String { throw URLError(.notConnectedToInternet) }
    func location(for ip: String) async throws -> IPLocation { throw URLError(.notConnectedToInternet) }
}

private struct UnreachableProbe: ConnectivityChecking {
    func isInternetReachable() async -> Bool { false }
}

private actor RecoverableLookup: IPLookingUp {
    private var available = false
    func recover() { available = true }
    func publicIPv4() async throws -> String {
        guard available else { throw URLError(.notConnectedToInternet) }
        return "203.0.113.20"
    }
    func location(for ip: String) async throws -> IPLocation { IPLocation(countryCode: "NL", city: "Amsterdam") }
}

private actor RecoverableProbe: ConnectivityChecking {
    private var available = false
    func recover() { available = true }
    func isInternetReachable() async -> Bool { available }
}

@MainActor
struct ConnectionRecoveryTests {
    @Test(arguments: IPFamily.allCases)
    func recoveredAddressClearsTheOutageBeforeLocationFinishes(family: IPFamily) async {
        let domain = "IPStateRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        let health = NetworkHealth(client: UnreachableProbe())
        health.pathChanged(available: true)
        let failed = IPMonitor(client: UnavailableLookup())
        await failed.refresh()
        await health.update(monitors: [failed])
        #expect(health.condition == .unreachable)

        var changes: [ConnectionChange] = []
        health.onConnectionChange = { changes.append($0) }
        let client = RecoveryLookup(family: family)
        let app = AppModel(client: client, preferences: preferences, networkHealth: health)
        defer { app.stop() }
        app.refresh()
        await client.waitForLocation()
        #expect(app.monitor.family == family)
        #expect(app.monitor.ip == (family == .ipv4 ? "203.0.113.10" : "2001:db8::10"))
        #expect(app.monitor.isRefreshing)
        #expect(health.condition == .online)
        #expect(changes == [.restored])
        await client.completeLocation()
    }

    @Test(arguments: [RefreshInterval.fiveSeconds, .off])
    func recoveryBypassesLookupBackoffOnlyWhenPeriodicChecksAreEnabled(interval: RefreshInterval) async throws {
        let domain = "IPStateRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .fiveSeconds
        let probe = RecoverableProbe()
        let health = NetworkHealth(client: probe)
        health.pathChanged(available: true)
        let client = RecoverableLookup()
        let app = AppModel(client: client, preferences: preferences, networkHealth: health)
        defer { app.stop() }
        for _ in 0..<6 { await app.ipv4.refresh(); await app.ipv6.refresh() }
        app.refresh()
        let clock = ContinuousClock()
        let initialDeadline = clock.now.advanced(by: .seconds(1))
        while health.condition != .unreachable, clock.now < initialDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(health.condition == .unreachable)
        preferences.interval = interval
        await client.recover()
        await probe.recover()

        let deadline = clock.now.advanced(by: .seconds(6))
        while health.condition != .online, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        if interval == .off {
            #expect(health.condition == .unreachable)
            #expect(app.ipv4.ip == nil)
        } else {
            #expect(health.condition == .online)
            #expect(app.ipv4.ip == "203.0.113.20")
        }
    }
}
