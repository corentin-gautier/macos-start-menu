import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: StartPanelController!
    private var commandMonitor: CommandKeyMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Used by scripts/uninstall.sh before deleting the app.
        if CommandLine.arguments.contains("--unregister-login-item") {
            LoginItem.setEnabled(false)
            exit(0)
        }
        _ = UsageStore.shared // starts recording app usage
        panelController = StartPanelController()
        commandMonitor = CommandKeyMonitor { [weak self] in
            self?.panelController.toggle()
        }
        commandMonitor.onPermissionGranted = { [weak self] in
            self?.panelController.showOnboarding(.ready)
        }
        commandMonitor.start()

        LoginItem.registerOnFirstLaunch()
        if !CommandKeyMonitor.isTrusted {
            panelController.showOnboarding(.permission)
        }
    }

    /// Opening the app again (Finder, `open`, Dock) shows the menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return false
    }
}
