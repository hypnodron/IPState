import Foundation
import Testing
@testable import IPStateCore

@MainActor
struct DisplayModeTests {
    @Test func combinedFlagAndCountryCodeHasAStaleMarker() {
        #expect(MenuBarLayout(enabled: [.flag, .countryCode]).title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "🇳🇱 NL")
        #expect(MenuBarLayout(enabled: [.flag, .countryCode]).title(ip: "203.0.113.10", countryCode: "NL", stale: true) == "🇳🇱 NL ·")
    }

    @Test func cityModesUseTheEditedAbbreviationAndHandleMissingCity() {
        #expect(MenuBarLayout(enabled: [.cityCode]).title(ip: "203.0.113.10", countryCode: "NL", stale: false, city: "Amsterdam", cityCode: "AMS") == "AMS")
        #expect(MenuBarLayout(enabled: [.flag, .cityCode]).title(ip: "203.0.113.10", countryCode: "NL", stale: false, city: "Amsterdam", cityCode: "AMS") == "🇳🇱 AMS")
        #expect(MenuBarLayout(enabled: [.city]).title(ip: "203.0.113.10", countryCode: "NL", stale: false, city: "Amsterdam") == "Amsterdam")
        #expect(MenuBarLayout(enabled: [.cityCode]).title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "???")
    }

    @Test func cityCodesPersistWithoutLeakingToOtherCities() {
        let domain = "IPStateDisplayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        let key = Preferences.cityKey(city: "São Paulo", countryCode: "BR")
        preferences[cityCodeFor: key] = " gru "
        preferences.menuBarLayout = MenuBarLayout(enabled: [.flag, .countryCode])
        let restored = Preferences(defaults: defaults)
        #expect(restored.menuBarLayout.enabled == [.flag, .countryCode])
        #expect(restored.cityCode(city: "Sao Paulo", countryCode: "BR") == "GRU")
        #expect(restored.cityCode(city: "Amsterdam", countryCode: "NL") == "AMS")
        #expect(restored.cityCode(city: "Москва", countryCode: "RU") == "MOS")
        #expect(restored.cityCode(city: nil, countryCode: "NL") == "???")
        #expect(restored.cityCode(city: "Sao Paulo", countryCode: "PT") == "SAO")
    }
}
