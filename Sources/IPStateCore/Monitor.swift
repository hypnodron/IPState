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
    public var onAddressResolved: (@MainActor () -> Void)?
    /// Resolves each change with its own fresh or cached location, or nil when neither is available.
    public var onChangeWithLocation: (@MainActor (IPChange, IPLocation?) -> Void)?

    @ObservationIgnored private let client: any IPLookingUp
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let locationCache: IPLocationCache
    @ObservationIgnored private var pendingLocatedChange: IPChange?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var locationAddress: String?
    @ObservationIgnored private var locationGeneration = 0

    public init(client: any IPLookingUp, family: IPFamily = .ipv4, locationCache: IPLocationCache = IPLocationCache()) {
        self.client = client
        self.family = family
        self.locationCache = locationCache
    }

    public func refresh() async {
        let pending = await fetchAddress()
        await withTaskCancellationHandler {
            await pending?.value
        } onCancel: {
            pending?.cancel()
        }
    }

    public func refreshAddress() async {
        _ = await fetchAddress()
    }

    private func fetchAddress() async -> Task<Void, Never>? {
        guard !isOffline else { return nil }
        generation += 1
        let request = generation
        isRefreshing = true
        defer {
            if request == generation {
                isRefreshing = false
            }
        }

        let address: String
        do {
            let result = try await (family == .ipv4 ? client.publicIPv4() : client.publicIPv6())
            guard request == generation, !Task.isCancelled else { return nil }
            guard let normalized = normalizedIPAddress(result, family: family) else { throw LookupError.invalidAddress }
            address = normalized
        } catch {
            guard request == generation, !Task.isCancelled else { return nil }
            isStale = true
            failureCount += 1
            lastError = error.localizedDescription
            return nil
        }

        let previous = ip
        if previous != address {
            cancelLocation()
            completeLocatedChange()
        }
        ip = address
        let cached = locationCache.location(for: address)
        countryCode = cached?.countryCode
        city = cached?.city
        isStale = false
        lastSuccess = Date()
        failureCount = 0
        lastError = nil
        lastLocationError = nil

        if let previous, previous != address {
            let change = IPChange(oldIP: previous, newIP: address, family: family)
            pendingLocatedChange = change
            onChange?(change)
        }

        guard request == generation, !Task.isCancelled else { return nil }
        onAddressResolved?()
        guard request == generation, !Task.isCancelled else { return nil }
        if locationCache.needsRefresh(for: address) {
            if locationAddress != address { startLocation(for: address) }
        } else {
            completeLocatedChange()
        }
        return locationTask
    }

    private func startLocation(for address: String) {
        locationGeneration += 1
        let request = locationGeneration
        locationAddress = address
        locationTask = Task { [weak self, client] in
            do {
                let location = try await client.location(for: address)
                guard let self, request == locationGeneration else { return }
                if !Task.isCancelled {
                    if let code = normalizedCountryCode(location.countryCode) {
                        let normalized = IPLocation(countryCode: code, city: location.city)
                        locationCache.store(normalized, for: address)
                        countryCode = code
                        city = normalized.city
                    } else {
                        lastLocationError = "Location data is unavailable. Try Refresh Now."
                    }
                }
            } catch {
                guard let self, request == locationGeneration else { return }
                if !Task.isCancelled { lastLocationError = "Location lookup failed. Try Refresh Now." }
            }
            guard let self, request == locationGeneration else { return }
            locationTask = nil
            locationAddress = nil
            completeLocatedChange()
        }
    }

    private func cancelLocation() {
        locationGeneration += 1
        locationTask?.cancel()
        locationTask = nil
        locationAddress = nil
    }

    public func cancelRefresh(markStale: Bool = false) {
        // Finish interrupted changes with their own cached data instead of dropping alerts.
        completeLocatedChange()
        generation += 1
        cancelLocation()
        isRefreshing = false
        if markStale { isStale = true }
    }

    private func completeLocatedChange() {
        guard let change = pendingLocatedChange else { return }
        pendingLocatedChange = nil
        onChangeWithLocation?(change, locationCache.location(for: change.newIP))
    }

    public func setOffline(_ offline: Bool) {
        isOffline = offline
        failureCount = 0
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
