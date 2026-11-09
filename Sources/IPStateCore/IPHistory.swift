import Foundation
import Observation

public struct IPHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let change: IPChange
    public let date: Date
}

@MainActor @Observable
public final class IPHistory {
    public var retentionLimit: Int {
        get { limit }
        set {
            let next = min(max(newValue, 1), 200)
            guard next != limit else { return }
            limit = next
            defaults.set(next, forKey: "ipHistoryLimit")
            if entries.count > next {
                entries = Array(entries.prefix(next))
                save()
            }
        }
    }
    private var limit: Int
    public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "keepIPHistory")
            if !isEnabled { clear() }
        }
    }
    public private(set) var entries: [IPHistoryEntry] = []
    public private(set) var errorMessage: String?
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        limit = min(max(defaults.object(forKey: "ipHistoryLimit") as? Int ?? 20, 1), 200)
        isEnabled = defaults.bool(forKey: "keepIPHistory")
        guard isEnabled, let data = defaults.data(forKey: "ipHistory") else { return }
        do {
            entries = Array(try JSONDecoder().decode([IPHistoryEntry].self, from: data).prefix(limit))
        } catch {
            errorMessage = "Saved IP history could not be read. Clear the history to reset it."
        }
    }

    public func record(_ change: IPChange, at date: Date = .now) {
        guard isEnabled else { return }
        entries.insert(IPHistoryEntry(id: UUID(), change: change, date: date), at: 0)
        entries = Array(entries.prefix(limit))
        save()
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: "ipHistory")
            errorMessage = nil
        } catch {
            errorMessage = "The latest IP history could not be saved."
        }
    }

    public func clear() {
        entries.removeAll()
        defaults.removeObject(forKey: "ipHistory")
        errorMessage = nil
    }
}
