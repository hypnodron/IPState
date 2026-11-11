import Foundation
import Testing
import IPStateTestSupport
import IPStateCore
@testable import IPState

private actor RecoveryLookup: IPLookingUp {
    private let family: IPFamily
    private var ipv4 = "203.0.113.10"
    private(set) var addressCalls = 0
    private(set) var locationCalls = 0
    private var locationResult: CheckedContinuation<IPLocation, Never>?
    private var holdsLocation = true
    var isLocating: Bool { locationResult != nil }

    init(family: IPFamily) { self.family = family }
    func setIPv4(_ value: String) { ipv4 = value }
    func publicIPv4() async throws -> String {
        if family == .ipv4 { addressCalls += 1; return ipv4 }
        try await Task.sleep(for: .seconds(60))
        throw URLError(.cannotConnectToHost)
    }
    func publicIPv6() async throws -> String {
        if family == .ipv6 { return "2001:db8::10" }
        try await Task.sleep(for: .seconds(60))
        throw URLError(.cannotConnectToHost)
    }
    func location(for ip: String) async throws -> IPLocation {
        locationCalls += 1
        if !holdsLocation { return IPLocation(countryCode: "NL", city: "Amsterdam") }
        return await withCheckedContinuation { locationResult = $0 }
    }
    func completeLocation() {
        locationResult?.resume(returning: IPLocation(countryCode: "NL", city: "Amsterdam"))
        locationResult = nil
    }
    func releasePending() { holdsLocation = false; completeLocation() }
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
    private(set) var calls = 0
    func recover() { available = true }
    func publicIPv4() async throws -> String {
        calls += 1
        guard available else { throw URLError(.notConnectedToInternet) }
        return "203.0.113.20"
    }
    func location(for ip: String) async throws -> IPLocation { IPLocation(countryCode: "NL", city: "Amsterdam") }
}

private actor SharedRecoveryProbe: ConnectivityChecking {
    private var calls = 0
    private var pending: CheckedContinuation<Bool, Never>?
    private var closed = false
    var isWaiting: Bool { pending != nil }
    func isInternetReachable() async -> Bool {
        guard !closed else { return false }
        calls += 1
        if calls == 1 { return false }
        return await withCheckedContinuation { pending = $0 }
    }
    func recover() { pending?.resume(returning: true); pending = nil }
    func releasePending() { closed = true; pending?.resume(returning: false); pending = nil }
}

private actor RecoverableProbe: ConnectivityChecking {
    private var available = false
    func recover() { available = true }
    func isInternetReachable() async -> Bool { available }
}

@MainActor
struct ConnectionRecoveryTests {
    @Test func aSharedRecoveryResultAlwaysTriggersAFreshAddressCheck() async throws {
        let domain = "IPStateSharedRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = RecoverableLookup()
        let probe = SharedRecoveryProbe()
        defer { Task { await probe.releasePending() } }
        let sleeper = TestSleeper()
        let app = AppModel(client: client, preferences: Preferences(defaults: defaults),
                           networkHealth: NetworkHealth(client: probe),
                           sleep: { try await sleeper.sleep(for: $0) })
        defer { app.stop() }
        for _ in 0..<6 { await app.ipv4.refresh(); await app.ipv6.refresh() }
        try #require(await taskCompletes(Task(priority: .background) { app.refresh() }))
        try #require(await eventually {
            let pending = await sleeper.pendingCount
            return app.networkHealth.condition == .unreachable && pending >= 3
        })
        await sleeper.advance(by: .seconds(3))
        try #require(await eventually { await probe.isWaiting })
        let calls = await client.calls
        try #require(await taskCompletes(Task(priority: .userInitiated) { app.refresh() }))
        try #require(await eventually { (await client.calls) > calls && !app.ipv4.isRefreshing && !app.ipv6.isRefreshing })
        await client.recover()
        await probe.recover()
        try #require(await eventually { app.ipv4.ip == "203.0.113.20" })
        #expect(app.networkHealth.condition == .online)
    }

    @Test func addressPollingContinuesWithoutRestartingPendingLocation() async throws {
        let domain = "IPStatePollingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        let cache = IPLocationCache()
        cache.store(IPLocation(countryCode: "NL", city: "Amsterdam"), for: "203.0.113.10")
        let sleeper = TestSleeper()
        let client = RecoveryLookup(family: .ipv4)
        defer { Task { await client.releasePending() } }
        let app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()), locationCache: cache,
                           sleep: { try await sleeper.sleep(for: $0) })
        defer { app.stop() }
        try #require(await taskCompletes(Task { await app.ipv4.refresh() }))
        var located: [String] = []
        app.ipv4.onChangeWithLocation = { change, _ in located.append(change.newIP) }
        await client.setIPv4("203.0.113.20")
        app.refresh()
        try #require(await eventually { await client.isLocating })
        try #require(await eventually { await sleeper.pendingCount > 0 })
        await sleeper.advance(by: .seconds(5))
        try #require(await eventually { await client.addressCalls >= 3 })
        #expect(await client.locationCalls == 1)
        #expect(located.isEmpty)
        await client.completeLocation()
        try #require(await eventually { app.ipv4.city == "Amsterdam" })
        #expect(located == ["203.0.113.20"])
    }

    @Test(arguments: IPFamily.allCases)
    func recoveredAddressClearsTheOutageBeforeLocationFinishes(family: IPFamily) async throws {
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
        defer { Task { await client.releasePending() } }
        let app = AppModel(client: client, preferences: preferences, networkHealth: health)
        defer { app.stop() }
        app.refresh()
        try #require(await eventually { await client.isLocating })
        #expect(app.monitor.family == family)
        #expect(app.monitor.ip == (family == .ipv4 ? "203.0.113.10" : "2001:db8::10"))
        #expect(!app.monitor.isRefreshing)
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
        let sleeper = TestSleeper()
        let app = AppModel(client: client, preferences: preferences, networkHealth: health,
                           sleep: { try await sleeper.sleep(for: $0) })
        defer { app.stop() }
        for _ in 0..<6 { await app.ipv4.refresh(); await app.ipv6.refresh() }
        app.refresh()
        try #require(await eventually { health.condition == .unreachable })
        try #require(health.condition == .unreachable)
        try #require(await eventually { await sleeper.remainingDelays.contains(.seconds(3)) })
        preferences.interval = interval
        await client.recover()
        await probe.recover()

        if interval == .off { try #require(await eventually { await sleeper.pendingCount == 0 }) }
        await sleeper.advance(by: .seconds(3))
        if interval == .off {
            #expect(health.condition == .unreachable)
            #expect(app.ipv4.ip == nil)
        } else {
            try #require(await eventually { health.condition == .online })
            #expect(health.condition == .online)
            #expect(app.ipv4.ip == "203.0.113.20")
        }
    }
}
