import Foundation
import Testing
@testable import IPStateCore

@MainActor
struct HistoryTests {
    private func withHistory(_ body: (IPHistory, UserDefaults) -> Void) {
        let domain = "IPStateHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        body(IPHistory(defaults: defaults), defaults)
    }

    @Test func historyIsOptIn() {
        withHistory { history, _ in
            history.record(IPChange(oldIP: "203.0.113.1", newIP: "203.0.113.2"))
            #expect(!history.isEnabled)
            #expect(history.entries.isEmpty)
        }
    }

    @Test func historyKeepsOnlyTwentyNewestChanges() {
        withHistory { history, defaults in
            history.isEnabled = true
            for index in 1...25 {
                history.record(IPChange(oldIP: "203.0.113.\(index)", newIP: "203.0.113.\(index + 1)"), at: Date(timeIntervalSince1970: Double(index)))
            }
            #expect(history.entries.count == 20)
            #expect(history.entries.first?.change.newIP == "203.0.113.26")
            #expect(history.entries.last?.change.newIP == "203.0.113.7")
            let restored = IPHistory(defaults: defaults)
            #expect(restored.isEnabled)
            #expect(restored.entries == history.entries)
        }
    }

    @Test func historyPreservesAddressFamilyAndClearsOnOptOut() {
        withHistory { history, defaults in
            history.isEnabled = true
            history.record(IPChange(oldIP: "2001:db8::1", newIP: "2001:db8::2", family: .ipv6))
            #expect(IPHistory(defaults: defaults).entries.first?.change.family == .ipv6)
            history.isEnabled = false
            #expect(history.entries.isEmpty)
            let restored = IPHistory(defaults: defaults)
            #expect(restored.entries.isEmpty)
            #expect(!restored.isEnabled)
        }
    }

    @Test func clearDoesNotDisableFutureHistory() {
        withHistory { history, defaults in
            history.isEnabled = true
            history.record(IPChange(oldIP: "203.0.113.1", newIP: "203.0.113.2"))
            history.clear()
            #expect(IPHistory(defaults: defaults).entries.isEmpty)
            #expect(history.isEnabled)
            history.record(IPChange(oldIP: "203.0.113.2", newIP: "203.0.113.3"))
            #expect(history.entries.count == 1)
        }
    }

    @Test func configuredLimitSurvivesRestartAndTrimsOldEntriesImmediately() {
        withHistory { history, defaults in
            history.isEnabled = true
            history.retentionLimit = 30
            for index in 1...25 {
                history.record(IPChange(oldIP: "203.0.113.\(index)", newIP: "203.0.113.\(index + 1)"))
            }
            #expect(history.entries.count == 25)
            history.retentionLimit = 3
            #expect(history.entries.map(\.change.newIP) == ["203.0.113.26", "203.0.113.25", "203.0.113.24"])
            let restored = IPHistory(defaults: defaults)
            #expect(restored.retentionLimit == 3)
            #expect(restored.entries == history.entries)
        }
    }

    @Test func historyLimitIsBoundedAndDoesNotResetOnOptOut() {
        withHistory { history, defaults in
            history.retentionLimit = 0
            #expect(history.retentionLimit == 1)
            history.retentionLimit = 500
            #expect(history.retentionLimit == 200)
            history.isEnabled = true
            history.isEnabled = false
            #expect(IPHistory(defaults: defaults).retentionLimit == 200)
        }
    }
}
