import Foundation
import Testing
@testable import IPState

@MainActor
struct AppUpdaterTests {
    @Test func previewUpdatesRequireAnOptInThatSurvivesRelaunch() {
        let domain = "IPStateUpdaterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let first = AppUpdater(defaults: defaults)
        #expect(!first.includesPreviewReleases)
        first.includesPreviewReleases = true
        let relaunched = AppUpdater(defaults: defaults)
        #expect(relaunched.includesPreviewReleases)
        relaunched.includesPreviewReleases = false
        #expect(!AppUpdater(defaults: defaults).includesPreviewReleases)
    }

    @Test func invalidUpdateConfigurationReportsAnErrorAndDisablesChecks() {
        let updater = AppUpdater()
        updater.start()
        #expect(updater.errorMessage?.isEmpty == false)
        #expect(!updater.canCheckForUpdates)
    }
}
