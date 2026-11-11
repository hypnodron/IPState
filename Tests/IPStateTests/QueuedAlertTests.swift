import Foundation
import Testing
import IPStateCore
import IPStateTestSupport
@testable import IPState

@MainActor
struct QueuedAlertTests {
    enum Completion: CaseIterable { case deliver, disable, stop }

    @Test(arguments: Completion.allCases)
    func queuedIPAlertsKeepTheirOrderAndHonorCancellation(completion: Completion) async throws {
        try await withAppScenario { scenario in
            let app = scenario.app
            let center = scenario.center
            center.pauseStatus = true
            await scenario.client.setIP("203.0.113.20")
            app.refresh()
            try #require(await eventually { center.statusWaiting })

            await scenario.client.setIP("203.0.113.30", location: IPLocation(countryCode: "DK", city: "Copenhagen"))
            app.refresh()
            try #require(await eventually { app.ipv4.ip == "203.0.113.30" && app.ipv4.city == "Copenhagen" })
            #expect(scenario.history.entries.count == 2)
            #expect(center.requests.isEmpty)

            switch completion {
            case .deliver: break
            case .disable:
                app.notificationsEnabled = false
                app.notificationsEnabled = true
            case .stop: app.stop()
            }
            let completedChecks = center.completedStatusChecks
            center.resumeStatus()
            try #require(await eventually { center.completedStatusChecks > completedChecks })

            if completion == .deliver {
                try #require(await eventually { center.requests.count == 2 })
                #expect(center.requests.map { $0.content.body } == [
                    "203.0.113.20\nPrevious: 203.0.113.10",
                    "203.0.113.30\nPrevious: 203.0.113.20"
                ])
                #expect(center.requests[0].content.subtitle.contains("Amsterdam"))
                #expect(center.requests[1].content.subtitle.contains("Copenhagen"))
            } else {
                #expect(center.requests.isEmpty)
                if completion == .disable {
                    await scenario.client.setIP("203.0.113.40")
                    app.refresh()
                    try #require(await eventually { center.requests.count == 1 })
                    #expect(center.requests.first?.content.body == "203.0.113.40\nPrevious: 203.0.113.30")
                } else {
                    try #require(await eventually { await scenario.sleeper.pendingCount == 0 })
                    let calls = await scenario.client.calls
                    await scenario.sleeper.advance(by: .seconds(1000))
                    scenario.lifecycle.networkChanged(true)
                    scenario.lifecycle.wake(online: true)
                    #expect(await scenario.client.calls == calls)
                    #expect(scenario.history.entries.count == 2)
                    #expect(center.requests.isEmpty)
                }
            }
        }
    }
}
