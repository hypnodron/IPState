import Foundation
import Testing
@testable import IPStateCore

private actor LookupFixture: IPLookingUp {
    enum Failure: Error { case unavailable }
    var ip = "203.0.113.10"
    var country: String? = "NL"
    var city: String? = "Amsterdam"
    var failsIP = false
    var failsCountry = false
    var blockCountry = false
    private var countryContinuation: CheckedContinuation<String?, Never>?
    private var countryWaiter: CheckedContinuation<Void, Never>?

    func configure(ip: String? = nil, failsIP: Bool = false, failsCountry: Bool = false) {
        if let ip { self.ip = ip }
        self.failsIP = failsIP
        self.failsCountry = failsCountry
    }

    func location(for ip: String) async throws -> IPLocation {
        let code = try await countryCode(for: ip)
        return IPLocation(countryCode: code ?? "NL", city: city)
    }

    func setCity(_ city: String?) { self.city = city }
    func setCountry(_ country: String) { self.country = country }
    func allowCountryRequests() { blockCountry = false }

    func publicIPv4() async throws -> String {
        if failsIP { throw Failure.unavailable }
        return ip
    }

    func countryCode(for ip: String) async throws -> String? {
        if failsCountry { throw Failure.unavailable }
        if blockCountry {
            return await withCheckedContinuation {
                countryContinuation = $0
                countryWaiter?.resume()
                countryWaiter = nil
            }
        }
        return country
    }

    func blockNextCountry() { blockCountry = true }
    func waitForCountryRequest() async {
        if countryContinuation != nil { return }
        await withCheckedContinuation { countryWaiter = $0 }
    }
    func releaseCountry() {
        blockCountry = false
        countryContinuation?.resume(returning: country)
        countryContinuation = nil
    }
}

private actor GatedLookup: IPLookingUp {
    private var requests: [CheckedContinuation<String, any Error>] = []
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func publicIPv4() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let index = requests.count
            requests.append(continuation)
            waiters.removeValue(forKey: index)?.resume()
        }
    }

    func location(for ip: String) async throws -> IPLocation { IPLocation(countryCode: "NL", city: nil) }

    func waitForRequest(_ index: Int) async {
        if requests.count > index { return }
        await withCheckedContinuation { waiters[index] = $0 }
    }

    func complete(_ index: Int, with ip: String) { requests[index].resume(returning: ip) }
}

private actor SupersedingLookup: IPLookingUp {
    private var addresses: [CheckedContinuation<String, Never>] = []
    private var location: CheckedContinuation<IPLocation, Never>?
    private(set) var addressCount = 0
    var isLocating: Bool { location != nil }
    func publicIPv4() async throws -> String {
        addressCount += 1
        return await withCheckedContinuation { addresses.append($0) }
    }
    func location(for ip: String) async throws -> IPLocation {
        await withCheckedContinuation { location = $0 }
    }
    func completeAddress(_ index: Int, ip: String) { addresses[index].resume(returning: ip) }
    func completeLocation() { location?.resume(returning: IPLocation(countryCode: "NL", city: "Amsterdam")); location = nil }
}

@MainActor
struct MonitorTests {
    @Test func anObsoleteCancelledRefreshCannotCancelTheNewIPsLocation() async throws {
        let client = SupersedingLookup()
        let monitor = IPMonitor(client: client)
        var firstFinished = false
        let first = Task { await monitor.refresh(); firstFinished = true }
        try #require(await waitUntil { await client.addressCount >= 1 })
        first.cancel()
        let second = Task { await monitor.refresh() }
        try #require(await waitUntil { await client.addressCount >= 2 })
        await client.completeAddress(1, ip: "203.0.113.20")
        try #require(await waitUntil { await client.isLocating })
        await client.completeAddress(0, ip: "203.0.113.10")
        #expect(await waitUntil { firstFinished })
        await client.completeLocation()
        await first.value
        await second.value
        #expect(monitor.ip == "203.0.113.20")
        #expect(monitor.city == "Amsterdam")
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    @Test(arguments: [false, true])
    func aNewNetworkPathResetsFailureBackoff(disconnectedFirst: Bool) async {
        let client = LookupFixture()
        await client.configure(failsIP: true)
        let monitor = IPMonitor(client: client)
        for _ in 0..<8 { await monitor.refresh() }
        #expect(RefreshInterval.fiveSeconds.delay(afterFailures: monitor.failureCount) == 300)
        if disconnectedFirst { monitor.setOffline(true) }
        monitor.setOffline(false)
        await monitor.refresh()
        #expect(RefreshInterval.fiveSeconds.delay(afterFailures: monitor.failureCount) == 5)
    }

    @Test func firstResultEstablishesBaselineWithoutNotification() async {
        let monitor = IPMonitor(client: LookupFixture())
        var changes: [IPChange] = []
        monitor.onChange = { changes.append($0) }
        await monitor.refresh()
        #expect(monitor.ip == "203.0.113.10")
        #expect(monitor.countryCode == "NL")
        #expect(!monitor.isStale)
        #expect(monitor.lastSuccess != nil)
        #expect(changes.isEmpty)
    }

    @Test func sameCountryIPChangeNotifiesOnce() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        var changes: [IPChange] = []
        monitor.onChange = { changes.append($0) }
        await monitor.refresh()
        await client.configure(ip: "203.0.113.11")
        await monitor.refresh()
        await monitor.refresh()
        #expect(monitor.ip == "203.0.113.11")
        #expect(changes == [IPChange(oldIP: "203.0.113.10", newIP: "203.0.113.11")])
    }

    @Test func failurePreservesLastSuccessAndRecoveryComparesWithIt() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        var changes: [IPChange] = []
        monitor.onChange = { changes.append($0) }
        await monitor.refresh()
        let timestamp = monitor.lastSuccess
        await client.configure(failsIP: true)
        await monitor.refresh()
        #expect(monitor.ip == "203.0.113.10")
        #expect(monitor.lastSuccess == timestamp)
        #expect(monitor.isStale)
        #expect(monitor.failureCount == 1)
        #expect(monitor.lastError != nil)
        #expect(changes.isEmpty)
        await client.configure(ip: "203.0.113.12")
        await monitor.refresh()
        #expect(!monitor.isStale)
        #expect(monitor.failureCount == 0)
        #expect(changes.count == 1)
    }

    @Test func invalidAddressCannotReplaceValidResult() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        await monitor.refresh()
        await client.configure(ip: "<html>service unavailable</html>")
        await monitor.refresh()
        #expect(monitor.ip == "203.0.113.10")
        #expect(monitor.isStale)
    }

    @Test func countryFailureDoesNotSuppressIPChangeOrReuseOldCountry() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        var changes: [IPChange] = []
        monitor.onChange = { changes.append($0) }
        var located: [IPLocation?] = []
        monitor.onChangeWithLocation = { _, location in located.append(location) }
        await monitor.refresh()
        await client.configure(ip: "203.0.113.13", failsCountry: true)
        await monitor.refresh()
        #expect(monitor.ip == "203.0.113.13")
        #expect(monitor.countryCode == nil)
        #expect(monitor.lastLocationError != nil)
        #expect(!monitor.isStale)
        #expect(changes.count == 1)
        #expect(located == [nil])
    }

    @Test func offlineMarksExistingResultStale() async {
        let monitor = IPMonitor(client: LookupFixture())
        await monitor.refresh()
        monitor.setOffline(true)
        #expect(monitor.isOffline)
        #expect(monitor.isStale)
        #expect(monitor.ip == "203.0.113.10")
        monitor.setOffline(false)
        #expect(monitor.isStale)
        await monitor.refresh()
        #expect(!monitor.isStale)
    }

    @Test func intervalOffDisablesRetriesAndConfiguredIntervalsRemainLowerBounds() {
        #expect(RefreshInterval.off.delay(afterFailures: 0) == nil)
        #expect(RefreshInterval.off.delay(afterFailures: 3) == nil)
        #expect(RefreshInterval.fiveSeconds.delay(afterFailures: 0) == 5)
        #expect(RefreshInterval.fiveSeconds.delay(afterFailures: 4) == 40)
        #expect(RefreshInterval.fiveSeconds.delay(afterFailures: 20) == 300)
        #expect(RefreshInterval.fifteenMinutes.delay(afterFailures: 3) == 900)
        #expect(RefreshInterval.thirtySeconds.delay(afterFailures: 0) == 30)
    }

    @Test func settingsPersistAndUnknownValuesUseSafeDefaults() {
        let domain = "IPStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        preferences.interval = .off
        preferences.menuBarLayout = MenuBarLayout(enabled: [.flag, .ip])
        preferences.notifyChanges = false
        let restored = Preferences(defaults: defaults)
        #expect(restored.interval == .off)
        #expect(restored.menuBarLayout.enabled == [.flag, .ip])
        #expect(!restored.notifyChanges)
        defaults.set(-42, forKey: "refreshInterval")
        #expect(Preferences(defaults: defaults).interval == .fiveSeconds)
    }

    @Test func displayCannotPresentMissingOrStaleDataAsCurrent() {
        #expect(MenuBarLayout(enabled: [.flag, .ip]).title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "🇳🇱 203.0.113.10")
        #expect(MenuBarLayout(enabled: [.countryCode]).title(ip: "203.0.113.10", countryCode: "NL", stale: true) == "NL ·")
        #expect(MenuBarLayout(enabled: [.flag]).title(ip: "203.0.113.10", countryCode: nil, stale: false) == "🌐")
        #expect(MenuBarLayout(enabled: [.countryCode]).title(ip: nil, countryCode: nil, stale: true) == "—")
    }

    @Test func lateResponseCannotReplaceANewerResult() async {
        let client = GatedLookup()
        let monitor = IPMonitor(client: client)
        var changes: [IPChange] = []
        monitor.onChange = { changes.append($0) }
        let old = Task { await monitor.refresh() }
        await client.waitForRequest(0)
        monitor.cancelRefresh()
        let current = Task { await monitor.refresh() }
        await client.waitForRequest(1)
        await client.complete(1, with: "203.0.113.22")
        await current.value
        await client.complete(0, with: "203.0.113.21")
        await old.value
        #expect(monitor.ip == "203.0.113.22")
        #expect(!monitor.isStale)
        #expect(changes.isEmpty)
    }

    @Test func offlineInvalidatesAnInFlightRequest() async {
        let client = GatedLookup()
        let monitor = IPMonitor(client: client)
        let pending = Task { await monitor.refresh() }
        await client.waitForRequest(0)
        monitor.setOffline(true)
        await client.complete(0, with: "203.0.113.23")
        await pending.value
        #expect(monitor.ip == nil)
        #expect(monitor.isOffline)
        #expect(monitor.isStale)
        #expect(!monitor.isRefreshing)
    }

    @Test func IPUpdateAndChangeDetectionAreImmediateWhileNotificationWaitsForLocation() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        var changes: [IPChange] = []
        monitor.onChange = { changes.append($0) }
        var located: [IPLocation?] = []
        monitor.onChangeWithLocation = { _, location in located.append(location) }
        await monitor.refresh()
        await client.configure(ip: "203.0.113.24")
        await client.setCountry("DK")
        await client.setCity("Copenhagen")
        await client.blockNextCountry()
        let pending = Task { await monitor.refresh() }
        await client.waitForCountryRequest()
        #expect(monitor.ip == "203.0.113.24")
        #expect(changes.count == 1)
        #expect(monitor.countryCode == nil)
        #expect(!monitor.isStale)
        #expect(located.isEmpty)
        await client.releaseCountry()
        await pending.value
        #expect(monitor.countryCode == "DK")
        #expect(located == [IPLocation(countryCode: "DK", city: "Copenhagen")])
    }

    @Test func returningToAnEarlierIPUsesItsCachedLocationForTheNotification() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        var locations: [IPLocation?] = []
        monitor.onChangeWithLocation = { _, location in locations.append(location) }
        await monitor.refresh()
        await client.configure(ip: "203.0.113.31")
        await client.setCountry("DK")
        await client.setCity("Copenhagen")
        await monitor.refresh()
        await client.configure(ip: "203.0.113.10", failsCountry: true)
        await monitor.refresh()
        #expect(locations == [IPLocation(countryCode: "DK", city: "Copenhagen"), IPLocation(countryCode: "NL", city: "Amsterdam")])
    }

    @Test func cancellingLocationLookupSendsOneFallbackWithoutAnOldLocation() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        var addresses: [String] = []
        var locations: [IPLocation?] = []
        monitor.onChangeWithLocation = { change, location in addresses.append(change.newIP); locations.append(location) }
        await monitor.refresh()
        await client.configure(ip: "203.0.113.32")
        await client.blockNextCountry()
        let pending = Task { await monitor.refresh() }
        await client.waitForCountryRequest()
        pending.cancel()
        monitor.cancelRefresh(markStale: true)
        #expect(addresses == ["203.0.113.32"])
        #expect(locations == [nil])
        await client.releaseCountry()
        await pending.value
        await monitor.refresh()
        #expect(addresses == ["203.0.113.32"])
    }

    @Test func supersedingAnIPCannotAttachItsLateLocationToAnotherNotification() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        var addresses: [String] = []
        var locations: [IPLocation?] = []
        monitor.onChangeWithLocation = { change, location in addresses.append(change.newIP); locations.append(location) }
        await monitor.refresh()
        await client.configure(ip: "203.0.113.33")
        await client.blockNextCountry()
        let pending = Task { await monitor.refresh() }
        await client.waitForCountryRequest()
        await client.allowCountryRequests()
        await client.configure(ip: "203.0.113.34")
        await client.setCountry("DK")
        await client.setCity("Copenhagen")
        await monitor.refresh()
        #expect(addresses == ["203.0.113.33", "203.0.113.34"])
        #expect(locations == [nil, IPLocation(countryCode: "DK", city: "Copenhagen")])
        await client.releaseCountry()
        await pending.value
        #expect(addresses == ["203.0.113.33", "203.0.113.34"])
        #expect(monitor.ip == "203.0.113.34")
        #expect(monitor.city == "Copenhagen")
    }

    @Test func notificationSnapshotUsesCurrentDataAndRetainsItsValuesAfterLaterUpdates() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        await monitor.refresh()
        let old = IPNotificationInfo(monitor: monitor)
        await client.configure(ip: "203.0.113.35")
        await client.setCountry("BR")
        await client.setCity("São Paulo")
        await monitor.refresh()
        let current = IPNotificationInfo(monitor: monitor)
        #expect(current.addressText == "203.0.113.35")
        #expect(current.locationText(locale: Locale(identifier: "en_US")) == "🇧🇷 Brazil · São Paulo")
        #expect(old.addressText == "203.0.113.10")
        #expect(old.location?.city == "Amsterdam")
        monitor.setOffline(true)
        #expect(IPNotificationInfo(monitor: monitor).addressText == "Last known IPv4: 203.0.113.35")
        #expect(!old.isStale)
    }

    @Test func newAddressClearsThePreviousCity() async {
        let client = LookupFixture()
        let monitor = IPMonitor(client: client)
        await monitor.refresh()
        #expect(monitor.city == "Amsterdam")
        await client.configure(ip: "203.0.113.25")
        await client.setCity(nil)
        await monitor.refresh()
        #expect(monitor.countryCode == "NL")
        #expect(monitor.city == nil)
        #expect(!monitor.isStale)
    }
}
