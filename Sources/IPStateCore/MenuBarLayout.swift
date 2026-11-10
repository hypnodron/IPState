import Foundation

public enum MenuBarComponent: String, CaseIterable, Identifiable, Sendable {
    case flag, countryCode, country, city, cityCode, ip
    public var id: Self { self }
    public var label: String {
        switch self {
        case .flag: "Country flag"
        case .countryCode: "Country code"
        case .country: "Country name"
        case .city: "City name"
        case .cityCode: "City code"
        case .ip: "IP address"
        }
    }
}

public struct MenuBarLayout: Equatable, Sendable {
    public private(set) var order: [MenuBarComponent]
    public private(set) var enabled: Set<MenuBarComponent>

    public init(order: [MenuBarComponent] = MenuBarComponent.allCases, enabled: Set<MenuBarComponent> = [.flag, .countryCode]) {
        var seen: Set<MenuBarComponent> = []
        self.order = (order + MenuBarComponent.allCases).filter { seen.insert($0).inserted }
        self.enabled = enabled
    }

    public mutating func setEnabled(_ item: MenuBarComponent, _ value: Bool) {
        if value { enabled.insert(item) } else { enabled.remove(item) }
    }
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, (0...order.count).contains(destination), source.allSatisfy({ order.indices.contains($0) }) else { return }
        let moving = source.map { order[$0] }
        var remaining = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        order = remaining
    }
    public func title(ip: String?, countryCode: String?, stale: Bool, country: String? = nil, city: String? = nil,
                      cityCode: String? = nil, cityLimit: Int = 0, countryLimit: Int = 0) -> String {
        guard !enabled.isEmpty else { return "🌐" }
        guard let ip else { return "—" }
        let code = normalizedCountryCode(countryCode)
        let values = order.filter { enabled.contains($0) }.map { item -> String in
            switch item {
            case .flag:
                return code.map { String(String.UnicodeScalarView($0.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) })) } ?? "🌐"
            case .countryCode: return code ?? "??"
            case .country: return limited(country ?? code ?? "Country unavailable", to: countryLimit)
            case .city: return limited(city ?? "City unavailable", to: cityLimit)
            case .cityCode: return cityCode ?? suggestedCityCode(city)
            case .ip: return ip
            }
        }
        let title = values.joined(separator: " ")
        return stale ? "\(title) ·" : title
    }

    var storedValue: [String: Any] {
        ["order": order.map(\.rawValue), "enabled": enabled.map(\.rawValue).sorted()]
    }

    init?(storedValue: [String: Any]) {
        guard let order = storedValue["order"] as? [String], let enabled = storedValue["enabled"] as? [String] else { return nil }
        self.init(order: order.compactMap(MenuBarComponent.init(rawValue:)), enabled: Set(enabled.compactMap(MenuBarComponent.init(rawValue:))))
    }

    static func migrated(from legacy: String?) -> Self {
        let enabled: Set<MenuBarComponent>
        switch legacy {
        case nil: return Self()
        case "ip": enabled = [.ip]
        case "flag": enabled = [.flag]
        case "flagAndIP": enabled = [.flag, .ip]
        case "codeAndIP": enabled = [.countryCode, .ip]
        case "flagAndCountryCode": enabled = [.flag, .countryCode]
        case "city": enabled = [.city]
        case "cityCode": enabled = [.cityCode]
        case "flagAndCityCode": enabled = [.flag, .cityCode]
        default: enabled = [.countryCode]
        }
        return Self(enabled: enabled)
    }

    private func limited(_ text: String, to limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}
