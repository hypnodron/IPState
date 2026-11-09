import Foundation
import Testing
@testable import IPStateCore

private actor DualLookup: IPLookingUp {
    var v6 = "2001:db8::1"
    var v6Fails = false
    var v4Fails = false
    func setIPv4Unavailable(_ unavailable: Bool) { v4Fails = unavailable }
    func configure(v6: String, fails: Bool = false) { self.v6 = v6; v6Fails = fails }
    func publicIPv4() async throws -> String {
        if v4Fails { throw URLError(.notConnectedToInternet) }
        return "203.0.113.10"
    }
    func publicIPv6() async throws -> String {
        if v6Fails { throw URLError(.notConnectedToInternet) }
        return v6
    }
    func location(for ip: String) async throws -> IPLocation { IPLocation(countryCode: "NL", city: "Amsterdam") }
}

@MainActor
struct DualStackTests {
    @Test func ipv6HasItsOwnAddressAndChangeBaseline() async {
        let client = DualLookup()
        let v4 = IPMonitor(client: client)
        let v6 = IPMonitor(client: client, family: .ipv6)
        var changes: [IPChange] = []
        v4.onChange = { changes.append($0) }
        v6.onChange = { changes.append($0) }
        await v4.refresh()
        await v6.refresh()
        #expect(v4.ip == "203.0.113.10")
        #expect(v6.ip == "2001:db8::1")
        #expect(changes.isEmpty)
        await client.configure(v6: "2001:db8::2")
        await v6.refresh()
        await v4.refresh()
        #expect(changes == [IPChange(oldIP: "2001:db8::1", newIP: "2001:db8::2", family: .ipv6)])
        #expect(v4.ip == "203.0.113.10")
    }

    @Test func equivalentIPv6SpellingsDoNotCauseChangeAlerts() async {
        let client = DualLookup()
        let monitor = IPMonitor(client: client, family: .ipv6)
        var changes: [IPChange] = []
        monitor.onChange = { changes.append($0) }
        await monitor.refresh()
        await client.configure(v6: "2001:0DB8:0000:0000:0000:0000:0000:0001")
        await monitor.refresh()
        #expect(monitor.ip == "2001:db8::1")
        #expect(!monitor.isStale)
        #expect(changes.isEmpty)
    }

    @Test func unavailableIPv6DoesNotInvalidateIPv4() async {
        let client = DualLookup()
        let v4 = IPMonitor(client: client)
        let v6 = IPMonitor(client: client, family: .ipv6)
        await v4.refresh()
        await v6.refresh()
        await client.configure(v6: "2001:db8::2", fails: true)
        await v6.refresh()
        #expect(v6.ip == "2001:db8::1")
        #expect(v6.isStale)
        #expect(v6.failureCount == 1)
        #expect(v4.ip == "203.0.113.10")
        #expect(!v4.isStale)
    }

    @Test func IPv4CannotBecomeAnIPv6Result() async {
        let client = DualLookup()
        await client.configure(v6: "203.0.113.10")
        let monitor = IPMonitor(client: client, family: .ipv6)
        await monitor.refresh()
        #expect(monitor.ip == nil)
        #expect(monitor.isStale)
    }

    @Test func automaticSelectionUsesIPv6WhenIPv4IsUnavailableAndRecoversToIPv4() async {
        let client = DualLookup()
        await client.setIPv4Unavailable(true)
        let v4 = IPMonitor(client: client)
        let v6 = IPMonitor(client: client, family: .ipv6)
        await v4.refresh()
        await v6.refresh()
        #expect(IPFamily.automatic(ipv4: v4, ipv6: v6, previous: .ipv4) == .ipv6)
        await client.setIPv4Unavailable(false)
        await v4.refresh()
        #expect(IPFamily.automatic(ipv4: v4, ipv6: v6, previous: .ipv6) == .ipv4)
    }

    @Test func automaticSelectionKeepsTheLastFamilyDuringAnOutage() async {
        let client = DualLookup()
        await client.setIPv4Unavailable(true)
        let v4 = IPMonitor(client: client)
        let v6 = IPMonitor(client: client, family: .ipv6)
        await v4.refresh()
        await v6.refresh()
        await client.configure(v6: "2001:db8::2", fails: true)
        await v6.refresh()
        #expect(IPFamily.automatic(ipv4: v4, ipv6: v6, previous: .ipv6) == .ipv6)
    }
}
