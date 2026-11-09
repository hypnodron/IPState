import Foundation
import Testing
@testable import IPStateCore

struct NotificationInfoTests {
    @Test func fullLocationAndIPv6AddressStayUnshortened() {
        let info = IPNotificationInfo(ip: "2001:db8:1234:5678:abcd:ef01:2345:6789", family: .ipv6,
                                      location: IPLocation(countryCode: "us", city: "Rancho Santa Margarita"))
        #expect(info.locationText(locale: Locale(identifier: "en_US")) == "🇺🇸 United States · Rancho Santa Margarita")
        #expect(info.addressText == "2001:db8:1234:5678:abcd:ef01:2345:6789")
    }

    @Test func missingCityAndLocationAreExplicit() {
        let country = IPNotificationInfo(ip: "203.0.113.1", family: .ipv4, location: IPLocation(countryCode: "NL", city: nil))
        #expect(country.locationText(locale: Locale(identifier: "en_US")) == "🇳🇱 Netherlands · City unavailable")
        let unknown = IPNotificationInfo(ip: "203.0.113.1", family: .ipv4, location: nil)
        #expect(unknown.locationText() == "🌐 Location unavailable")
        #expect(unknown.addressText == "203.0.113.1")
    }

    @Test func anInvalidCountryDoesNotCreateAFlag() {
        let info = IPNotificationInfo(ip: "203.0.113.1", family: .ipv4, location: IPLocation(countryCode: "???", city: "Amsterdam"))
        #expect(info.locationText() == "🌐 Country unavailable · Amsterdam")
    }

    @Test func noIPDoesNotInventAnAddressOrDisplayDetachedLocationData() {
        let info = IPNotificationInfo(ip: nil, family: .ipv4, location: IPLocation(countryCode: "NL", city: "Amsterdam"), isStale: true)
        #expect(info.locationText().isEmpty)
        #expect(info.addressText == "No IP address available yet.")
    }
}
