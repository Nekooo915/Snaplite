import AppKit

/// Zero-thread single-instance coordinator using `NSRunningApplication` and `DistributedNotificationCenter`.
public enum SingleInstance {
    public static let showNotificationName = Notification.Name("com.nekooo915.snaplite.show")

    /// If another instance with the same bundle identifier is already running, asks it to
    /// surface its settings window and returns `true` so the caller can exit immediately.
    public static func tryForwardToExisting() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let hasPeer = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != currentPID && !$0.isTerminated }
        guard hasPeer else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            showNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    /// Registers an observer on the main queue for show requests from secondary launches.
    @MainActor
    @discardableResult
    public static func observeShowRequests(
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: showNotificationName,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }
}
