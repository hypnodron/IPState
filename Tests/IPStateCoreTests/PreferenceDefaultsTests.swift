import Foundation
import Testing
@testable import IPStateCore

@MainActor
struct PreferenceDefaultsTests {
    @Test func aFreshProfileKeepsItsCompactLayoutAndNameLimitsAcrossLaunches() {
        withDefaults { defaults in
            let first = Preferences(defaults: defaults)
            #expect(first.menuBarLayout.title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "🇳🇱 NL")
            first.menuBarLayout = MenuBarLayout(enabled: [.country, .city])
            let reopened = Preferences(defaults: defaults)
            #expect(title(reopened) == "United States of Am… Frankfurt am Ma…")
        }
    }

    @Test func anExistingLayoutKeepsItsPreviouslyUnlimitedNames() {
        withDefaults { defaults in
            defaults.set(MenuBarLayout(enabled: [.country, .city]).storedValue, forKey: "menuBarLayout")
            let migrated = Preferences(defaults: defaults)
            #expect(title(migrated) == "United States of America Frankfurt am Main")
            #expect(title(Preferences(defaults: defaults)) == "United States of America Frankfurt am Main")
        }
    }

    @Test func explicitUnlimitedNamesAndDisabledOptionsSurviveMigration() {
        withDefaults { defaults in
            defaults.set("countryCode", forKey: "displayMode")
            defaults.set(0, forKey: "cityCharacterLimit")
            defaults.set(0, forKey: "countryCharacterLimit")
            defaults.set(false, forKey: "notifyChanges")
            defaults.set(0, forKey: "refreshInterval")
            let migrated = Preferences(defaults: defaults)
            #expect(migrated.menuBarLayout.title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "NL")
            #expect(!migrated.notifyChanges)
            #expect(migrated.interval == .off)
            migrated.menuBarLayout = MenuBarLayout(enabled: [.country, .city])
            #expect(title(Preferences(defaults: defaults)) == "United States of America Frankfurt am Main")
        }
    }

    private func title(_ preferences: Preferences) -> String {
        preferences.menuBarLayout.title(ip: "203.0.113.10", countryCode: "US", stale: false,
                                       country: "United States of America", city: "Frankfurt am Main",
                                       cityLimit: preferences.cityCharacterLimit,
                                       countryLimit: preferences.countryCharacterLimit)
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let domain = "IPStatePreferenceDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        body(defaults)
    }
}
