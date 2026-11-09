import AppKit
import SwiftUI
import Testing
import IPStateCore
@testable import IPState

@MainActor
struct MenuBarStatusLabelTests {
    @Test func networkConditionsNeverChangeTheLabelsWidth() {
        for title in ["NL", "🇳🇱 NL AMS", "203.0.113.123", "🌐"] {
            let online = size(title: title, condition: .online)
            #expect(online.width > 0)
            for condition in NetworkCondition.allCases {
                let actual = size(title: title, condition: condition)
                #expect(abs(actual.width - online.width) < 0.1)
                #expect(abs(actual.height - online.height) < 0.1)
            }
        }
    }

    @Test func staleMarkerDoesNotExpandTheLabel() {
        #expect(abs(size(title: "NL", condition: .online, stale: true).width - size(title: "NL", condition: .online).width) < 0.1)
    }

    private func size(title: String, condition: NetworkCondition, stale: Bool = false) -> CGSize {
        let view = NSHostingView(rootView: MenuBarStatusLabel(title: title, condition: condition, isStale: stale))
        return view.fittingSize
    }
}
