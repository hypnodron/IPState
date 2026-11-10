import Foundation

@MainActor
public final class IPLocationCache {
    private struct Entry: Codable {
        let countryCode: String
        let city: String?
        let storedAt: Date
    }
    private static let key = "ipLocationCache.v1"
    private static let refreshAge: TimeInterval = 24 * 60 * 60
    private static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    private var entries: [String: Entry] = [:]
    private let defaults: UserDefaults?
    private let now: () -> Date

    public init(defaults: UserDefaults? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults?.data(forKey: Self.key), data.count <= 65_536,
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
        prune()
        persist()
    }

    public func location(for ip: String) -> IPLocation? {
        guard let address = normalizedIPAddress(ip), let entry = entries[address] else { return nil }
        guard isRetained(entry) else {
            entries.removeValue(forKey: address)
            persist()
            return nil
        }
        return IPLocation(countryCode: entry.countryCode, city: entry.city)
    }

    public func needsRefresh(for ip: String) -> Bool {
        guard let address = normalizedIPAddress(ip), location(for: address) != nil,
              let entry = entries[address] else { return true }
        return now().timeIntervalSince(entry.storedAt) >= Self.refreshAge
    }

    public func store(_ location: IPLocation, for ip: String) {
        guard let address = normalizedIPAddress(ip), let code = normalizedCountryCode(location.countryCode) else { return }
        entries[address] = Entry(countryCode: code, city: location.city, storedAt: now())
        prune()
        persist()
    }

    private func isRetained(_ entry: Entry) -> Bool {
        let age = now().timeIntervalSince(entry.storedAt)
        return age >= -1 && age < Self.maximumAge && normalizedCountryCode(entry.countryCode) == entry.countryCode
    }

    private func prune() {
        entries = entries.filter { normalizedIPAddress($0.key) == $0.key && isRetained($0.value) }
        if entries.count > 100 {
            let oldest = entries.sorted { $0.value.storedAt < $1.value.storedAt }.prefix(entries.count - 100)
            for entry in oldest { entries.removeValue(forKey: entry.key) }
        }
    }

    private func persist() {
        guard let defaults else { return }
        if entries.isEmpty { defaults.removeObject(forKey: Self.key) }
        else if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}
