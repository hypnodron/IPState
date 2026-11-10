import Foundation
import Testing
import UserNotifications
import IPStateCore
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
    private(set) var requests: [UNNotificationRequest] = []
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {}
    func authorizationStatus() async -> UNAuthorizationStatus {
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
    private(set) var calls = 0
    private var ipv6Enabled = false
    func enableIPv6() { ipv6Enabled = true }
    func setIP(_ ip: String, blockLocation: Bool = false) {
        self.ip = ip
        blockedIP = blockLocation ? ip : nil
    }
    func publicIPv4() async throws -> String { calls += 1; return ip }
    func publicIPv6() async throws -> String {
        guard ipv6Enabled else { throw URLError(.notConnectedToInternet) }
        return "2001:db8::10"
    }
    func location(for ip: String) async throws -> IPLocation {
        if blockedIP == ip { return await withCheckedContinuation { pending[ip] = $0 } }
        return IPLocation(countryCode: "NL", city: "Amsterdam")
    }
    func completeLocation(for ip: String) {
        pending.removeValue(forKey: ip)?.resume(returning: IPLocation(countryCode: "NL", city: "Amsterdam"))
    }
    func isLocating(_ ip: String) -> Bool { pending[ip] != nil }
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
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
