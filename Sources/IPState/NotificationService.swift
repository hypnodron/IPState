import Foundation
import Observation
import UserNotifications
import IPStateCore

@MainActor @Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static func makeContent(title: String, info: IPNotificationInfo, thread: String,
                            previousIP: String? = nil, locale: Locale = .current) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = info.locationText(locale: locale)
        content.body = info.addressText
        if let previousIP { content.body += "\nPrevious: \(previousIP)" }
        content.threadIdentifier = thread
        content.sound = .default
        return content
    }
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var errorMessage: String?
    private(set) var testResult: String?
    private(set) var isSendingTest = false
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func updateAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        await updateAuthorization()
        guard authorization == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            errorMessage = nil
        } catch {
            errorMessage = "Could not request notification permission: \(error.localizedDescription)"
        }
        await updateAuthorization()
    }

    func send(_ change: IPChange, location: IPLocation?) async {
        let info = IPNotificationInfo(ip: change.newIP, family: change.family, location: location)
        await send(Self.makeContent(title: "Public \(change.family.label) changed", info: info,
                                    thread: "ip-changes", previousIP: change.oldIP))
    }

    func send(_ change: ConnectionChange, info: IPNotificationInfo) async {
        let title = change == .lost ? "Internet connection lost" : "Internet connection restored"
        await send(Self.makeContent(title: title, info: info, thread: "connection-changes"))
    }

    private func send(_ content: UNMutableNotificationContent) async {
        await updateAuthorization()
        guard !Task.isCancelled, authorization == .authorized || authorization == .provisional else { return }
        do {
            try await deliver(content)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Could not send the notification: \(error.localizedDescription)"
        }
    }

    func sendTest(_ info: IPNotificationInfo) async {
        guard !isSendingTest else { return }
        isSendingTest = true
        testResult = nil
        defer { isSendingTest = false }
        await requestAuthorizationIfNeeded()
        guard authorization == .authorized || authorization == .provisional else {
            testResult = "Allow IP State in System Settings → Notifications, then try again."
            return
        }
        do {
            try await deliver(Self.makeContent(title: "IP State test notification", info: info, thread: "test-notifications"))
            errorMessage = nil
            testResult = "Test notification sent. If no banner appears, check notification settings or Focus."
        } catch {
            testResult = "Could not send the test notification: \(error.localizedDescription)"
        }
    }

    private func deliver(_ content: UNMutableNotificationContent) async throws {
        guard !Task.isCancelled else { return }
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
