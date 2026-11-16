import AppKit
import Combine
import Observation
import Sparkle

@MainActor @Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var errorMessage: String?
    var includesPreviewReleases: Bool {
        didSet {
            defaults.set(includesPreviewReleases, forKey: "includesPreviewReleases")
            if hasStarted { updater.resetUpdateCycleAfterShortDelay() }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updater: SPUUpdater!
    @ObservationIgnored private var observations: [AnyCancellable] = []
    @ObservationIgnored private var hasStarted = false

    init(hostBundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        includesPreviewReleases = defaults.bool(forKey: "includesPreviewReleases")
        super.init()
        let driver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: driver, delegate: self)
        observations = [
            updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheckForUpdates = $0 },
            updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
        ]
    }

    func start() {
        guard !hasStarted else { return }
        do {
            try updater.start()
            hasStarted = true
            errorMessage = nil
        } catch {
            canCheckForUpdates = false
            errorMessage = "App updates are unavailable: \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        includesPreviewReleases ? ["preview"] : []
    }
}
