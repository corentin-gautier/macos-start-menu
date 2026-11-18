import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: StartPanelController!
    private var commandMonitor: CommandKeyMonitor!
    private var appleMenuMonitor: AppleMenuClickMonitor!

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
        appleMenuMonitor = AppleMenuClickMonitor { [weak self] in
            self?.panelController.toggle()
        }
        commandMonitor.onPermissionGranted = { [weak self] in
            self?.appleMenuMonitor.update()
            self?.panelController.showOnboarding(.ready)
        }
        commandMonitor.start()
        appleMenuMonitor.update()
        panelController.model.onTriggerKeyChange = { [weak self] in self?.commandMonitor.trigger = $0 }
        panelController.model.onAppleMenuClickChange = { [weak self] in self?.appleMenuMonitor.update() }
        UpdateChecker.shared.start()

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
