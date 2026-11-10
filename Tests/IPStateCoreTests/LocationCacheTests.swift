import Foundation
import Testing
@testable import IPStateCore

private actor CachedLookup: IPLookingUp {
    private let holdLocation: Bool
    private(set) var locationCalls = 0
    private var started: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<IPLocation, any Error>?
    private var address = "203.0.113.10"
    init(holdLocation: Bool = false) { self.holdLocation = holdLocation }
    func setIP(_ ip: String) { address = ip }
    func publicIPv4() async throws -> String { address }
    func location(for ip: String) async throws -> IPLocation {
        locationCalls += 1
        if !holdLocation { return IPLocation(countryCode: "DK", city: "Copenhagen") }
        return try await withCheckedThrowingContinuation {
            result = $0
            started?.resume()
            started = nil
        }
    }
    func waitForLocation() async {
        if result != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func completeLocation(failing: Bool = false) {
        if failing { result?.resume(throwing: URLError(.timedOut)) }
        else { result?.resume(returning: IPLocation(countryCode: "DK", city: "Copenhagen")) }
        result = nil
    }
}

@MainActor
struct LocationCacheTests {
    @Test func failedRevalidationKeepsTheExactIPsCachedLocationForItsAlert() async {
        var now = Date()
        let cache = IPLocationCache(now: { now })
        cache.store(IPLocation(countryCode: "NL", city: "Amsterdam"), for: "203.0.113.10")
        cache.store(IPLocation(countryCode: "DK", city: "Copenhagen"), for: "203.0.113.20")
        let client = CachedLookup(holdLocation: true)
        let monitor = IPMonitor(client: client, locationCache: cache)
        await monitor.refresh()
        now = now.addingTimeInterval(2 * 24 * 60 * 60)
        var locations: [IPLocation?] = []
        monitor.onChangeWithLocation = { _, location in locations.append(location) }
        await client.setIP("203.0.113.20")
        let change = Task { await monitor.refresh() }
        await client.waitForLocation()
        #expect(monitor.city == "Copenhagen")
        await client.completeLocation(failing: true)
        await change.value
        #expect(monitor.city == "Copenhagen")
        #expect(monitor.lastLocationError != nil)
        #expect(locations == [IPLocation(countryCode: "DK", city: "Copenhagen")])
    }

    @Test func aKnownIPUsesCachedLocationWithoutAnotherProviderRequest() async {
        let cache = IPLocationCache()
        cache.store(IPLocation(countryCode: "NL", city: "Amsterdam"), for: "203.0.113.10")
        let client = CachedLookup()
        let monitor = IPMonitor(client: client, locationCache: cache)
        await monitor.refresh()
        #expect(monitor.countryCode == "NL")
        #expect(monitor.city == "Amsterdam")
        #expect(await client.locationCalls == 0)
    }

    @Test func anOldCachedLocationAppearsBeforeItsUpdatedLocationArrives() async {
        var now = Date()
        let cache = IPLocationCache(now: { now })
        cache.store(IPLocation(countryCode: "NL", city: "Amsterdam"), for: "203.0.113.10")
        now = now.addingTimeInterval(2 * 24 * 60 * 60)
        let client = CachedLookup(holdLocation: true)
        let monitor = IPMonitor(client: client, locationCache: cache)
        let pending = Task { await monitor.refresh() }
        await client.waitForLocation()
        #expect(monitor.countryCode == "NL")
        #expect(monitor.city == "Amsterdam")
        await client.completeLocation()
        await pending.value
        #expect(monitor.countryCode == "DK")
        #expect(monitor.city == "Copenhagen")
        #expect(cache.location(for: "203.0.113.10")?.city == "Copenhagen")
        #expect(!cache.needsRefresh(for: "203.0.113.10"))
    }

    @Test func aKnownLocationSurvivesANewCacheInstance() {
        let domain = "IPStateLocationCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let cache = IPLocationCache(defaults: defaults)
        cache.store(IPLocation(countryCode: "NL", city: "Amsterdam"), for: "203.0.113.10")
        let reopened = IPLocationCache(defaults: defaults)
        #expect(reopened.location(for: "203.0.113.10") == IPLocation(countryCode: "NL", city: "Amsterdam"))
        #expect(!reopened.needsRefresh(for: "203.0.113.10"))
    }

    @Test func anOldLocationAppearsImmediatelyButNeedsRevalidation() {
        var now = Date()
        let cache = IPLocationCache(now: { now })
        cache.store(IPLocation(countryCode: "NL", city: "Amsterdam"), for: "203.0.113.10")
        now = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(cache.location(for: "203.0.113.10")?.city == "Amsterdam")
        #expect(cache.needsRefresh(for: "203.0.113.10"))
        now = now.addingTimeInterval(6 * 24 * 60 * 60)
        #expect(cache.location(for: "203.0.113.10") == nil)
    }

    @Test func cacheEvictsOldEntriesAndNormalizesIPv6Keys() {
        var now = Date()
        let cache = IPLocationCache(now: { now })
        cache.store(IPLocation(countryCode: "NL", city: "Amsterdam"), for: "2001:0DB8:0:0:0:0:0:10")
        #expect(cache.location(for: "2001:db8::10")?.city == "Amsterdam")
        for index in 1...100 {
            now = now.addingTimeInterval(1)
            cache.store(IPLocation(countryCode: "DK", city: "Copenhagen"), for: "198.51.100.\(index)")
        }
        #expect(cache.location(for: "2001:db8::10") == nil)
        #expect(cache.location(for: "198.51.100.1")?.city == "Copenhagen")
        #expect(cache.location(for: "198.51.100.100")?.city == "Copenhagen")
    }
}
