import AppKit
import Network

/// 잠자기 복귀와 네트워크 복구를 감지한다.
@MainActor
final class SystemEventMonitor {
    private var wakeObserver: NSObjectProtocol?
    private let pathMonitor = NWPathMonitor()
    private var isOffline = false

    func start(onWake: @escaping @MainActor () -> Void, onNetworkRestored: @escaping @MainActor () -> Void) {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onWake() }
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if satisfied && self.isOffline { onNetworkRestored() }
                self.isOffline = !satisfied
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "QuotaBar.NetworkMonitor"))
    }

    deinit {
        pathMonitor.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}
