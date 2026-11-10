import AppKit
import Network

@MainActor
protocol AppLifecycleMonitoring: AnyObject {
    func start(networkChanged: @escaping @MainActor (Bool) -> Void,
               willSleep: @escaping @MainActor () -> Void,
               didWake: @escaping @MainActor (Bool) -> Void)
    func stop()
}

@MainActor
final class SystemAppLifecycleMonitor: AppLifecycleMonitoring {
    private let pathMonitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []

    func start(networkChanged: @escaping @MainActor (Bool) -> Void,
               willSleep: @escaping @MainActor () -> Void,
               didWake: @escaping @MainActor (Bool) -> Void) {
        pathMonitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in networkChanged(online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.hypnodron.IPState.network"))
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in willSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                didWake(pathMonitor.currentPath.status == .satisfied)
            }
        })
    }

    func stop() {
        pathMonitor.cancel()
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
}
