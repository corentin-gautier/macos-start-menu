import AppKit

/// The apps currently running (with a Dock icon), for the dot under their
/// tile and the Quit / Force Quit context menu items.
final class RunningApps {
    static let shared = RunningApps()

    /// Symlink-resolved bundle paths, as `AppEntry.path`.
    private(set) var paths: Set<String> = []
    /// Called on the main thread when `paths` changes.
    var onChange: () -> Void = {}

    private init() {
        reload()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        }
    }

    private func reload() {
        let paths = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { $0.bundleURL?.resolvingSymlinksInPath().path })
        guard paths != self.paths else { return }
        self.paths = paths
        onChange()
    }

    func isRunning(_ app: AppEntry) -> Bool { paths.contains(app.path) }

    private func instances(of app: AppEntry) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.resolvingSymlinksInPath().path == app.path }
    }

    func quit(_ app: AppEntry) {
        instances(of: app).forEach { $0.terminate() }
    }

    func forceQuit(_ app: AppEntry) {
        instances(of: app).forEach { $0.forceTerminate() }
    }
}
