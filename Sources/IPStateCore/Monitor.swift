import Foundation
import Observation
import Darwin

public protocol IPLookingUp: Sendable {
    func publicIPv4() async throws -> String
    func publicIPv6() async throws -> String
    func location(for ip: String) async throws -> IPLocation
}

public extension IPLookingUp {
    func publicIPv6() async throws -> String { throw LookupError.unavailable }
}

public struct IPChange: Equatable, Codable, Sendable {
    public let oldIP: String
    public let newIP: String
    public let family: IPFamily

    public init(oldIP: String, newIP: String, family: IPFamily = .ipv4) {
        self.oldIP = oldIP
        self.newIP = newIP
        self.family = family
    }
}

public enum RefreshInterval: Int, CaseIterable, Sendable {
    case off = 0, fiveSeconds = 5, tenSeconds = 10, thirtySeconds = 30
    case oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900

    public var label: String {
        switch self {
        case .off: "Off"
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }

    public func delay(afterFailures count: Int) -> TimeInterval? {
        guard self != .off else { return nil }
        let retryDelay = count > 0 ? min(5 * pow(2, Double(min(count - 1, 6))), 300) : 0
        return max(Double(rawValue), retryDelay)
    }
}

@MainActor @Observable
public final class IPMonitor {
    public let family: IPFamily
    public private(set) var ip: String?
    public private(set) var countryCode: String?
    public private(set) var city: String?
    public private(set) var isStale = true
    public private(set) var isOffline = false
    public private(set) var isRefreshing = false
    public private(set) var lastSuccess: Date?
    public private(set) var failureCount = 0
    public private(set) var lastError: String?
    public private(set) var lastLocationError: String?
    public var onChange: (@MainActor (IPChange) -> Void)?
    /// Resolves each change with its own location, or nil after a failed or interrupted lookup.
    public var onChangeWithLocation: (@MainActor (IPChange, IPLocation?) -> Void)?

    @ObservationIgnored private let client: any IPLookingUp
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var locations: [String: IPLocation] = [:]
    @ObservationIgnored private var pendingLocatedChange: IPChange?

    public init(client: any IPLookingUp, family: IPFamily = .ipv4) {
        self.client = client
        self.family = family
    }

    public func refresh() async {
        guard !isOffline else { return }
        generation += 1
        let request = generation
        isRefreshing = true
        defer {
            if request == generation {
                isRefreshing = false
                completeLocatedChange()
            }
        }

        let address: String
        do {
            let result = try await (family == .ipv4 ? client.publicIPv4() : client.publicIPv6())
            guard request == generation, !Task.isCancelled else { return }
            guard let normalized = normalizedIPAddress(result, family: family) else { throw LookupError.invalidAddress }
            address = normalized
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            isStale = true
            failureCount += 1
            lastError = error.localizedDescription
            return
        }

        let previous = ip
        ip = address
        countryCode = locations[address]?.countryCode
        city = locations[address]?.city
        isStale = false
        lastSuccess = Date()
        failureCount = 0
        lastError = nil
        lastLocationError = nil

        if let previous, previous != address {
            completeLocatedChange()
            let change = IPChange(oldIP: previous, newIP: address, family: family)
            pendingLocatedChange = change
            onChange?(change)
        }

        guard request == generation, !Task.isCancelled else { return }
        guard locations[address] == nil else { return }
        do {
            let location = try await client.location(for: address)
            guard request == generation, !Task.isCancelled else { return }
            if let code = normalizedCountryCode(location.countryCode) {
                // Bound the cache for long sessions with frequent address changes.
                if locations.count >= 100 { locations.removeAll() }
                let normalized = IPLocation(countryCode: code, city: location.city)
                locations[address] = normalized
                countryCode = code
                city = normalized.city
            } else {
                lastLocationError = "Location data is unavailable. Try Refresh Now."
            }
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            lastLocationError = "Location lookup failed. Try Refresh Now."
        }
    }

    public func cancelRefresh(markStale: Bool = false) {
        // Finish interrupted changes with their own cached data instead of dropping alerts.
        completeLocatedChange()
        generation += 1
        isRefreshing = false
        if markStale { isStale = true }
    }

    private func completeLocatedChange() {
        guard let change = pendingLocatedChange else { return }
        pendingLocatedChange = nil
        onChangeWithLocation?(change, locations[change.newIP])
    }

    public func setOffline(_ offline: Bool) {
        isOffline = offline
        if offline {
            cancelRefresh()
            isStale = true
        }
    }
}

func isValidIPv4(_ value: String) -> Bool {
    var address = in_addr()
    return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
}

func normalizedCountryCode(_ value: String?) -> String? {
    guard let value else { return nil }
    let code = value.uppercased()
    guard code.utf8.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
    return code
}

enum LookupError: LocalizedError {
    case invalidAddress, unavailable, invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "The lookup service returned an invalid IP address."
        case .unavailable: "The lookup services are unavailable."
        case .invalidResponse: "The lookup service returned an invalid response."
        }
    }
}
