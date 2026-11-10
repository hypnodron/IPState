import Foundation
import Testing
import UserNotifications
import IPStateCore
@testable import IPState

@MainActor
struct NotificationServiceTests {
    private let change = IPChange(oldIP: "203.0.113.10", newIP: "203.0.113.20")

    @Test func anAuthorizationFailureIsVisibleWithoutSendingAnAlert() async {
        let center = TestNotificationCenter()
        center.status = .notDetermined
        center.authorizationFails = true
        let service = NotificationService(center: center)
        await service.sendTest(IPNotificationInfo(ip: nil, family: .ipv4, location: nil))
        #expect(center.requests.isEmpty)
        #expect(service.errorMessage != nil)
        #expect(service.testResult != nil)
        #expect(!service.isSendingTest)
    }

    @Test func automaticAlertsRespectDeniedPermissionWithoutRequestingItAgain() async {
        let center = TestNotificationCenter()
        center.status = .denied
        let service = NotificationService(center: center)
        await service.send(change, location: nil)
        #expect(service.authorization == .denied)
        #expect(center.requests.isEmpty)
        #expect(center.authorizationRequests == 0)
    }

    @Test func aTestAlertRequestsPermissionAndUsesTheCurrentSnapshot() async {
        let center = TestNotificationCenter()
        center.status = .notDetermined
        let service = NotificationService(center: center)
        let info = IPNotificationInfo(ip: "203.0.113.20", family: .ipv4,
                                      location: IPLocation(countryCode: "NL", city: "Amsterdam"))
        await service.sendTest(info)
        #expect(center.authorizationRequests == 1)
        #expect(center.requests.count == 1)
        #expect(center.requests.first?.content.body == "203.0.113.20")
        #expect(center.requests.first?.content.subtitle.contains("Amsterdam") == true)
        #expect(!service.isSendingTest)
    }

    @Test func aDeliveryFailureIsVisibleAndASuccessfulRetryClearsIt() async {
        let center = TestNotificationCenter()
        center.deliveryFails = true
        let service = NotificationService(center: center)
        await service.send(change, location: nil)
        #expect(service.errorMessage != nil)
        #expect(center.requests.isEmpty)
        center.deliveryFails = false
        await service.send(change, location: nil)
        #expect(service.errorMessage == nil)
        #expect(center.requests.count == 1)
        #expect(center.requests.first?.content.body == "203.0.113.20\nPrevious: 203.0.113.10")
    }

    @Test func cancellingATestAlertDoesNotReportAnUnsentNotificationAsSent() async {
        let center = TestNotificationCenter()
        center.status = .notDetermined
        center.pauseStatus = true
        let service = NotificationService(center: center)
        let pending = Task { await service.sendTest(IPNotificationInfo(ip: nil, family: .ipv4, location: nil)) }
        #expect(await eventually { center.statusWaiting })
        pending.cancel()
        center.resumeStatus()
        await pending.value
        #expect(center.requests.isEmpty)
        #expect(center.authorizationRequests == 0)
        #expect(service.testResult == nil)
        #expect(!service.isSendingTest)
    }
}
