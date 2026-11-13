import Foundation
import Testing
@testable import IPStateCore

@MainActor
struct MenuBarLayoutTests {
    @Test func checkedItemsRenderInTheirChosenOrder() {
        var layout = MenuBarLayout(order: [.cityCode, .countryCode, .flag, .ip, .city, .country], enabled: [.flag, .countryCode, .cityCode])
        #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: false, city: "Amsterdam", cityCode: "AMS") == "AMS NL 🇳🇱")
        layout.setEnabled(.countryCode, false)
        layout.setEnabled(.ip, true)
        #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: true, city: "Amsterdam", cityCode: "AMS") == "AMS 🇳🇱 203.0.113.10 ·")
    }

    @Test func movingItemsWorksInBothDirectionsWithoutChangingCheckboxes() {
        var layout = MenuBarLayout(enabled: [.flag, .countryCode, .ip])
        layout.move(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "203.0.113.10 🇳🇱 NL")
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 6)
        #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "🇳🇱 NL 203.0.113.10")
        #expect(layout.enabled == [.flag, .countryCode, .ip])
    }

    @Test func allUncheckedKeepsTheMenuAccessible() {
        let layout = MenuBarLayout(enabled: [])
        #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "🌐")
        #expect(layout.title(ip: nil, countryCode: nil, stale: true) == "🌐")
    }

    @Test func nameLimitsIncludeTheEllipsisAndRespectGraphemeBoundaries() {
        let layout = MenuBarLayout(enabled: [.country, .city])
        #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: false, country: "Netherlands", city: "Amsterdam", cityLimit: 4, countryLimit: 5) == "Neth… Ams…")
        #expect(layout.title(ip: "203.0.113.10", countryCode: "BR", stale: false, country: "Brazil", city: "São Paulo", cityLimit: 3, countryLimit: 0) == "Brazil Sã…")
        #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: false, country: "Netherlands", city: "Amsterdam") == "Netherlands Amsterdam")
    }

    @Test func orderCheckboxesAndNameLimitsPersistIncludingAnEmptySelection() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.menuBarLayout = MenuBarLayout(order: [.ip, .countryCode, .flag], enabled: [.countryCode, .ip])
            preferences.cityCharacterLimit = 8
            preferences.countryCharacterLimit = 12
            let restored = Preferences(defaults: defaults)
            #expect(restored.menuBarLayout.title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "203.0.113.10 NL")
            #expect(restored.cityCharacterLimit == 8)
            #expect(restored.countryCharacterLimit == 12)
            restored.menuBarLayout = MenuBarLayout(enabled: [])
            #expect(Preferences(defaults: defaults).menuBarLayout.enabled.isEmpty)
        }
    }

    @Test func invalidStoredItemsDoNotDuplicateOrRemoveCheckboxRows() {
        withDefaults { defaults in
            defaults.set(["order": ["countryCode", "flag", "flag", "futureItem"], "enabled": ["flag", "countryCode"]], forKey: "menuBarLayout")
            let layout = Preferences(defaults: defaults).menuBarLayout
            #expect(layout.order.count == 6)
            #expect(Set(layout.order).count == 6)
            #expect(layout.title(ip: "203.0.113.10", countryCode: "NL", stale: false) == "NL 🇳🇱")
        }
    }

    @Test func checkboxBindingsAndMoveActionsSaveTheirChanges() {
        withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences[shows: .flag] = true
            preferences[shows: .countryCode] = false
            preferences[shows: .cityCode] = true
            preferences.moveMenuBarItems(fromOffsets: IndexSet(integer: 4), toOffset: 0)
            let restored = Preferences(defaults: defaults)
            #expect(restored.menuBarLayout.title(ip: "203.0.113.10", countryCode: "NL", stale: false, city: "Amsterdam", cityCode: "AMS") == "AMS 🇳🇱")
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let domain = "IPStateLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        body(defaults)
    }
}
