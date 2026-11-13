import Foundation
import Observation

@MainActor @Observable
public final class Preferences {
    public var menuBarLayout: MenuBarLayout {
        didSet { defaults.set(menuBarLayout.storedValue, forKey: "menuBarLayout") }
    }
    public var cityCharacterLimit: Int {
        get { cityLimit }
        set { cityLimit = min(max(newValue, 0), 80); defaults.set(cityLimit, forKey: "cityCharacterLimit") }
    }
    public var countryCharacterLimit: Int {
        get { countryLimit }
        set { countryLimit = min(max(newValue, 0), 80); defaults.set(countryLimit, forKey: "countryCharacterLimit") }
    }
    private var cityLimit: Int
    private var countryLimit: Int
    public var interval: RefreshInterval {
        didSet {
            defaults.set(interval.rawValue, forKey: "refreshInterval")
            onIntervalChange?()
        }
    }
    public var notifyChanges: Bool {
        didSet { defaults.set(notifyChanges, forKey: "notifyChanges") }
    }
    public var notifyConnectionChanges: Bool {
        didSet { defaults.set(notifyConnectionChanges, forKey: "notifyConnectionChanges") }
    }
    @ObservationIgnored public var onIntervalChange: (@MainActor () -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private var cityCodes: [String: String] {
        didSet { defaults.set(cityCodes, forKey: "cityCodes") }
    }

    public subscript(shows component: MenuBarComponent) -> Bool {
        get { menuBarLayout.enabled.contains(component) }
        set { menuBarLayout.setEnabled(component, newValue) }
    }

    public func moveMenuBarItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        menuBarLayout.move(fromOffsets: source, toOffset: destination)
    }

    public static func cityKey(city: String, countryCode: String?) -> String {
        let name = city.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return "\(countryCode?.uppercased() ?? "??")|\(name)"
    }
    public subscript(cityCodeFor key: String) -> String {
        get { cityCodes[key] ?? "" }
        set { cityCodes[key] = String(newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(8)) }
    }
    public func cityCode(city: String?, countryCode: String?) -> String {
        guard let city else { return "???" }
        let custom = self[cityCodeFor: Self.cityKey(city: city, countryCode: countryCode)]
        return custom.isEmpty ? suggestedCityCode(city) : custom
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cityCodes = defaults.dictionary(forKey: "cityCodes") as? [String: String] ?? [:]
        interval = (defaults.object(forKey: "refreshInterval") as? Int).flatMap(RefreshInterval.init(rawValue:)) ?? .fiveSeconds
        menuBarLayout = defaults.dictionary(forKey: "menuBarLayout").flatMap(MenuBarLayout.init(storedValue:))
            ?? MenuBarLayout()
        cityLimit = min(max(defaults.object(forKey: "cityCharacterLimit") as? Int ?? 16, 0), 80)
        countryLimit = min(max(defaults.object(forKey: "countryCharacterLimit") as? Int ?? 20, 0), 80)
        notifyChanges = defaults.object(forKey: "notifyChanges") as? Bool ?? true
        notifyConnectionChanges = defaults.bool(forKey: "notifyConnectionChanges")
        // Save the initial limits before the layout marks this profile as existing.
        if defaults.object(forKey: "cityCharacterLimit") == nil { defaults.set(cityLimit, forKey: "cityCharacterLimit") }
        if defaults.object(forKey: "countryCharacterLimit") == nil { defaults.set(countryLimit, forKey: "countryCharacterLimit") }
        defaults.set(menuBarLayout.storedValue, forKey: "menuBarLayout")
    }
}

public func suggestedCityCode(_ city: String?) -> String {
    guard let city else { return "???" }
    let latin = city.applyingTransform(.toLatin, reverse: false) ?? city
    let letters = latin.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        .uppercased().filter(\.isLetter)
    return letters.isEmpty ? "???" : String(letters.prefix(3))
}
