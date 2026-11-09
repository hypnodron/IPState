import Foundation
import Testing
import UserNotifications
import IPStateCore
@testable import IPState

@MainActor
struct NotificationContentTests {
    @Test func changedNotificationPutsTheNewIPFirstAndKeepsFullLocation() {
        let info = IPNotificationInfo(ip: "203.0.113.20", family: .ipv4, location: IPLocation(countryCode: "NL", city: "Amsterdam"))
        let content = NotificationService.makeContent(title: "Public IPv4 changed", info: info, thread: "ip-changes",
                                                      previousIP: "203.0.113.10", locale: Locale(identifier: "en_US"))
        #expect(content.subtitle == "🇳🇱 Netherlands · Amsterdam")
        #expect(content.body == "203.0.113.20\nPrevious: 203.0.113.10")
        #expect(content.threadIdentifier == "ip-changes")
    }

    @Test func testNotificationContainsTheCurrentFullIPv6Info() {
        let info = IPNotificationInfo(ip: "2001:db8::1234", family: .ipv6,
                                      location: IPLocation(countryCode: "US", city: "Rancho Santa Margarita"))
        let content = NotificationService.makeContent(title: "IP State test notification", info: info, thread: "test-notifications",
                                                      locale: Locale(identifier: "en_US"))
        #expect(content.subtitle == "🇺🇸 United States · Rancho Santa Margarita")
        #expect(content.body == "2001:db8::1234")
        #expect(content.sound != nil)
    }

    @Test func offlineInfoIsMarkedAsLastKnown() {
        let info = IPNotificationInfo(ip: "203.0.113.20", family: .ipv4,
                                      location: IPLocation(countryCode: "NL", city: "Amsterdam"), isStale: true)
        let content = NotificationService.makeContent(title: "Internet connection lost", info: info, thread: "connection-changes",
                                                      locale: Locale(identifier: "en_US"))
        #expect(content.subtitle == "🇳🇱 Netherlands · Amsterdam")
        #expect(content.body == "Last known IPv4: 203.0.113.20")
    }
}
