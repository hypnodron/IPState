import Foundation
import Observation

public enum NetworkCondition: CaseIterable, Equatable, Sendable {
    case checking, online, offline, unreachable, lookupUnavailable
    public var description: String {
        switch self {
        case .checking: "Checking connection"
        case .online: "Internet connected"
        case .offline: "No network connection"
        case .unreachable: "Internet unreachable"
        case .lookupUnavailable: "IP lookup unavailable"
        }
    }
    public var symbol: String? {
        switch self {
        case .online: nil
        case .checking: "arrow.triangle.2.circlepath"
        case .offline: "wifi.slash"
        case .unreachable: "wifi.exclamationmark"
        case .lookupUnavailable: "questionmark.circle"
        }
    }
}

public protocol ConnectivityChecking: Sendable {
    func isInternetReachable() async -> Bool
}

public enum ConnectionChange: Equatable, Sendable {
    case lost, restored
}

public struct ConnectivityClient: ConnectivityChecking {
    public init() {}
    public func isInternetReachable() async -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let url = URL(string: "https://www.apple.com/library/test/success.html")!
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 3)
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.host == url.host, data.count <= 4096 else { return false }
            return String(decoding: data, as: UTF8.self).contains("Success")
        } catch {
            return false
        }
    }
}

@MainActor @Observable
public final class NetworkHealth {
    public private(set) var condition: NetworkCondition = .checking {
        didSet {
            let reachable: Bool
            switch condition {
            case .checking: return
            case .online, .lookupUnavailable: reachable = true
            case .offline, .unreachable: reachable = false
            }
            let previous = connectionWasReachable
            connectionWasReachable = reachable
            if let previous, previous != reachable {
                onConnectionChange?(reachable ? .restored : .lost)
            }
        }
    }
    @ObservationIgnored public var onConnectionChange: (@MainActor (ConnectionChange) -> Void)?
    @ObservationIgnored private var connectionWasReachable: Bool?
    @ObservationIgnored private let client: any ConnectivityChecking
    @ObservationIgnored private var pathAvailable: Bool?
    @ObservationIgnored private var epoch = Date()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var probeTask: Task<Bool, Never>?
    @ObservationIgnored private var lastProbe: Date?

    public init(client: any ConnectivityChecking = ConnectivityClient()) { self.client = client }

    public func resetConnectionBaseline() { connectionWasReachable = nil }

    public func cancelPendingCheck() {
        generation += 1
        probeTask?.cancel()
        probeTask = nil
        lastProbe = nil
    }

    public func lookupSucceeded() {
        guard pathAvailable != false else { return }
        cancelPendingCheck()
        condition = .online
    }

    public func pathChanged(available: Bool) {
        cancelPendingCheck()
        pathAvailable = available
        epoch = Date()
        condition = available ? .checking : .offline
    }

    public func update(monitors: [IPMonitor]) async {
        guard pathAvailable != false, !Task.isCancelled, !monitors.isEmpty else { return }
        if monitors.contains(where: { !$0.isStale && ($0.lastSuccess ?? .distantPast) >= epoch }) {
            lookupSucceeded()
            return
        }
        guard !monitors.contains(where: \.isRefreshing) else { return }
        if let probeTask { _ = await probeTask.value; return }
        if let lastProbe, Date().timeIntervalSince(lastProbe) < 30 { return }
        _ = await probe()
    }

    public func checkRecovery() async -> Bool {
        guard condition == .unreachable, pathAvailable != false, !Task.isCancelled else { return false }
        return await probe()
    }

    private func probe() async -> Bool {
        if let probeTask { return await probeTask.value }
        let request = generation
        lastProbe = Date()
        // The health check outlives any one refresh waiter; replacements share its result.
        let task = Task { [weak self, client] in
            let reachable = await client.isInternetReachable()
            guard let self else { return false }
            defer { if request == generation { probeTask = nil } }
            guard request == generation, !Task.isCancelled, pathAvailable != false else { return false }
            condition = reachable ? .lookupUnavailable : .unreachable
            return reachable
        }
        probeTask = task
        return await task.value
    }
}
