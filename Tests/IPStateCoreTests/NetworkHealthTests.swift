import Foundation
import Testing
@testable import IPStateCore

private actor HealthLookup: IPLookingUp {
    var fails = true
    func recover() { fails = false }
    func publicIPv4() async throws -> String {
        if fails { throw URLError(.cannotConnectToHost) }
        return "203.0.113.10"
    }
    func location(for ip: String) async throws -> IPLocation { IPLocation(countryCode: "NL", city: "Amsterdam") }
}

private actor Probe: ConnectivityChecking {
    let reachable: Bool
    private(set) var calls = 0
    init(reachable: Bool) { self.reachable = reachable }
    func isInternetReachable() async -> Bool { calls += 1; return reachable }
}

private actor GatedProbe: ConnectivityChecking {
    private(set) var calls = 0
    var continuation: CheckedContinuation<Bool, Never>?
    var waiter: CheckedContinuation<Void, Never>?
    func isInternetReachable() async -> Bool {
        calls += 1
        if calls > 1 { return true }
        return await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
    }
    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func complete() { continuation?.resume(returning: true); continuation = nil }
}

@MainActor
struct NetworkHealthTests {
    @Test func disconnectedPathImmediatelyOverridesOldSuccessfulLookups() async {
        let client = HealthLookup()
        await client.recover()
        let monitor = IPMonitor(client: client)
        await monitor.refresh()
        let health = NetworkHealth(client: Probe(reachable: true))
        health.pathChanged(available: false)
        await health.update(monitors: [monitor])
        #expect(health.condition == .offline)
    }

    @Test func successfulLookupConfirmsInternetWithoutAProbe() async {
        let client = HealthLookup()
        let probe = Probe(reachable: false)
        let health = NetworkHealth(client: probe)
        health.pathChanged(available: true)
        await client.recover()
        let monitor = IPMonitor(client: client)
        await monitor.refresh()
        await health.update(monitors: [monitor])
        #expect(health.condition == .online)
        #expect(await probe.calls == 0)
    }

    @Test func serviceOutageIsDistinctFromAnUnreachableInternet() async {
        let monitor = IPMonitor(client: HealthLookup())
        await monitor.refresh()
        let available = NetworkHealth(client: Probe(reachable: true))
        available.pathChanged(available: true)
        await available.update(monitors: [monitor])
        #expect(available.condition == .lookupUnavailable)
        let unreachable = NetworkHealth(client: Probe(reachable: false))
        unreachable.pathChanged(available: true)
        await unreachable.update(monitors: [monitor])
        #expect(unreachable.condition == .unreachable)
    }

    @Test func repeatedFailuresDoNotProbeOnEveryRefresh() async {
        let monitor = IPMonitor(client: HealthLookup())
        await monitor.refresh()
        let probe = Probe(reachable: false)
        let health = NetworkHealth(client: probe)
        health.pathChanged(available: true)
        await health.update(monitors: [monitor])
        await health.update(monitors: [monitor])
        #expect(health.condition == .unreachable)
        #expect(await probe.calls == 1)
    }

    @Test func aLateProbeCannotReplaceTheOfflineState() async {
        let monitor = IPMonitor(client: HealthLookup())
        await monitor.refresh()
        let probe = GatedProbe()
        let health = NetworkHealth(client: probe)
        health.pathChanged(available: true)
        let pending = Task { await health.update(monitors: [monitor]) }
        await probe.waitForStart()
        health.pathChanged(available: false)
        await probe.complete()
        await pending.value
        #expect(health.condition == .offline)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["IPSTATE_LIVE_CONNECTIVITY"] == "1"))
    func liveConnectivityProbe() async {
        #expect(await ConnectivityClient().isInternetReachable())
    }

    @Test func cancelledProbeDoesNotBlockTheNextCheck() async {
        let monitor = IPMonitor(client: HealthLookup())
        await monitor.refresh()
        let probe = GatedProbe()
        let health = NetworkHealth(client: probe)
        health.pathChanged(available: true)
        let pending = Task { await health.update(monitors: [monitor]) }
        await probe.waitForStart()
        pending.cancel()
        await probe.complete()
        await pending.value
        await health.update(monitors: [monitor])
        #expect(health.condition == .lookupUnavailable)
        #expect(await probe.calls == 2)
    }
}
