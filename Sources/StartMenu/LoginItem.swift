import ServiceManagement

/// Start Menu opens at login through the system's Login Items
/// (System Settings › General › Login Items & Extensions).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turned on once, on the first launch; the user can turn it off from the
    /// sort menu or System Settings without it coming back.
    static func registerOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("StartMenu: login item \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}
