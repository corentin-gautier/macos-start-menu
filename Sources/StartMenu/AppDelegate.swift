import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: StartPanelController!
    private var commandMonitor: CommandKeyMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = StartPanelController()
        commandMonitor = CommandKeyMonitor { [weak self] in
            self?.panelController.toggle()
        }
        commandMonitor.start()
    }

    /// Opening the app again (Finder, `open`, Dock) shows the menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return false
    }
}
