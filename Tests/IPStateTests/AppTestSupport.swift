import Foundation
import Testing
import UserNotifications
import IPStateCore
import IPStateTestSupport
@testable import IPState

struct TestConnectivity: ConnectivityChecking {
    func isInternetReachable() async -> Bool { true }
}

@MainActor
final class TestLifecycle: AppLifecycleMonitoring {
    private var network: (@MainActor (Bool) -> Void)?
    private var sleepHandler: (@MainActor () -> Void)?
    private var wakeHandler: (@MainActor (Bool) -> Void)?
    func start(networkChanged: @escaping @MainActor (Bool) -> Void,
               willSleep: @escaping @MainActor () -> Void, didWake: @escaping @MainActor (Bool) -> Void) {
        network = networkChanged
        sleepHandler = willSleep
        wakeHandler = didWake
    }
    func stop() {}
    func networkChanged(_ online: Bool) { network?(online) }
    func sleep() { sleepHandler?() }
    func wake(online: Bool) { wakeHandler?(online) }
}

@MainActor
final class TestNotificationCenter: NotificationCenterAccess {
    var status: UNAuthorizationStatus = .authorized
    var deliveryFails = false
    var authorizationFails = false
    var pauseStatus = false
    private var statusContinuation: CheckedContinuation<UNAuthorizationStatus, Never>?
    var statusWaiting: Bool { statusContinuation != nil }
    private(set) var authorizationRequests = 0
    private(set) var completedStatusChecks = 0
    private(set) var requests: [UNNotificationRequest] = []
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {}
    func authorizationStatus() async -> UNAuthorizationStatus {
        defer { completedStatusChecks += 1 }
        if pauseStatus {
            pauseStatus = false
            return await withCheckedContinuation { statusContinuation = $0 }
        }
        return status
    }
    func resumeStatus() { statusContinuation?.resume(returning: status); statusContinuation = nil }
    func requestAuthorization() async throws {
        authorizationRequests += 1
        if authorizationFails { throw URLError(.unknown) }
        status = .authorized
    }
    func add(_ request: UNNotificationRequest) async throws {
        if deliveryFails { throw URLError(.unknown) }
        requests.append(request)
    }
}

actor AppLookup: IPLookingUp {
    private var ip = "203.0.113.10"
    private var blockedIP: String?
    private var pending: [String: CheckedContinuation<IPLocation, Never>] = [:]
    private var locations: [String: IPLocation] = [:]
    private var blockAddress = false
    private var pendingAddress: CheckedContinuation<String, Never>?
    var isResolvingAddress: Bool { pendingAddress != nil }
    private(set) var calls = 0
    private var ipv6Enabled = false
    func enableIPv6() { ipv6Enabled = true }
    func setIP(_ ip: String, blockLocation: Bool = false, blockAddress: Bool = false,
               location: IPLocation = IPLocation(countryCode: "NL", city: "Amsterdam")) {
        self.ip = ip
        blockedIP = blockLocation ? ip : nil
        self.blockAddress = blockAddress
        locations[ip] = location
    }
    func publicIPv4() async throws -> String {
        calls += 1
        if blockAddress { return await withCheckedContinuation { pendingAddress = $0 } }
        return ip
    }
    func publicIPv6() async throws -> String {
        guard ipv6Enabled else { throw URLError(.notConnectedToInternet) }
        return "2001:db8::10"
    }
    func location(for ip: String) async throws -> IPLocation {
        if blockedIP == ip { return await withCheckedContinuation { pending[ip] = $0 } }
        return locations[ip] ?? IPLocation(countryCode: "NL", city: "Amsterdam")
    }
    func completeLocation(for ip: String) {
        pending.removeValue(forKey: ip)?.resume(returning: locations[ip] ?? IPLocation(countryCode: "NL", city: "Amsterdam"))
    }
    func isLocating(_ ip: String) -> Bool { pending[ip] != nil }
    func completeAddress() { blockAddress = false; pendingAddress?.resume(returning: ip); pendingAddress = nil }
    func releasePending() {
        blockedIP = nil
        completeAddress()
        for address in Array(pending.keys) { completeLocation(for: address) }
    }
}

actor TestSleeper {
    private struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var now: Duration = .zero
    private var waiters: [UUID: Waiter] = [:]

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters[id] = Waiter(deadline: now + duration, continuation: continuation) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func advance(by duration: Duration) {
        now += duration
        let ready = waiters.filter { $0.value.deadline <= now }
        for (id, waiter) in ready {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    var pendingCount: Int { waiters.count }
    var remainingDelays: [Duration] { waiters.values.map { $0.deadline - now } }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}

@MainActor
final class AppScenario {
    let domain = "IPStateScenarioTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let client = AppLookup()
    let center = TestNotificationCenter()
    let lifecycle = TestLifecycle()
    let sleeper = TestSleeper()
    let cache = IPLocationCache()
    let history: IPHistory
    let app: AppModel

    init() {
        defaults = UserDefaults(suiteName: domain)!
        let preferences = Preferences(defaults: defaults)
        history = IPHistory(defaults: defaults)
        history.isEnabled = true
        app = AppModel(client: client, preferences: preferences, networkHealth: NetworkHealth(client: TestConnectivity()),
                       locationCache: cache, history: history, notifications: NotificationService(center: center),
                       lifecycle: lifecycle, sleep: { [sleeper] in try await sleeper.sleep(for: $0) })
    }

    func start() async throws {
        app.start()
        try #require(await eventually { self.app.ipv4.city == "Amsterdam" && self.center.completedStatusChecks > 0 })
        try #require(await eventually { await self.sleeper.pendingCount == 2 })
    }

    func cleanup() async {
        app.stop()
        center.pauseStatus = false
        center.resumeStatus()
        await client.releasePending()
        defaults.removePersistentDomain(forName: domain)
    }
}

@MainActor
func withAppScenario(_ body: @MainActor (AppScenario) async throws -> Void) async throws {
    let scenario = AppScenario()
    do {
        try await scenario.start()
        try await body(scenario)
    } catch {
        await scenario.cleanup()
        throw error
    }
    await scenario.cleanup()
}
