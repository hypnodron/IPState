import Foundation
import Testing
import IPStateCore
import IPStateTestSupport
@testable import IPState

@MainActor
struct ShutdownTests {
    enum PendingResponse: CaseIterable { case address, location }

    @Test(arguments: PendingResponse.allCases)
    func stoppingRejectsLateResponsesAndCancelsArmedTimers(response: PendingResponse) async throws {
        try await withAppScenario { scenario in
            let app = scenario.app
            await scenario.client.setIP("203.0.113.20", blockLocation: response == .location,
                                        blockAddress: response == .address,
                                        location: IPLocation(countryCode: "DK", city: "Copenhagen"))
            // Keep a handle that finishes only after the real monitor processes the released response.
            let pending = Task { await app.ipv4.refresh() }
            defer { pending.cancel() }
            if response == .address {
                try #require(await eventually { await scenario.client.isResolvingAddress })
            } else {
                try #require(await eventually { await scenario.client.isLocating("203.0.113.20") })
                try #require(await eventually { await scenario.sleeper.pendingCount == 2 })
            }
            let ip = app.ipv4.ip
            let city = app.ipv4.city
            let history = scenario.history.entries
            let calls = await scenario.client.calls
            app.stop()
            try #require(await eventually { await scenario.sleeper.pendingCount == 0 })
            await scenario.client.releasePending()
            try #require(await taskCompletes(pending))
            await scenario.sleeper.advance(by: .seconds(1000))
            scenario.lifecycle.networkChanged(true)
            scenario.lifecycle.wake(online: true)

            #expect(app.ipv4.ip == ip)
            #expect(app.ipv4.city == city)
            #expect(scenario.cache.location(for: "203.0.113.20") == nil)
            #expect(scenario.history.entries == history)
            #expect(scenario.center.requests.isEmpty)
            #expect(await scenario.client.calls == calls)
        }
    }
}
