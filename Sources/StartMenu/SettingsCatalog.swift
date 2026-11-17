import SwiftUI

struct SettingEntry: Identifiable, Hashable {
    let id: String          // System Settings extension bundle identifier
    let name: String
    let symbol: String
    let color: Color
    let keywords: [String]  // English and French search terms
    let key: SearchKey
    let keywordKeys: [SearchKey]

    var url: URL { URL(string: "x-apple.systempreferences:\(id)")! }

    init(_ id: String, _ name: String, _ symbol: String, _ color: Color, _ keywords: [String] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.keywords = keywords
        self.key = SearchKey(name)
        self.keywordKeys = keywords.map(SearchKey.init)
    }

    /// Name matches rank above keyword matches; keywords never match fuzzily.
    func score(_ query: String) -> Int? {
        let nameScore = Search.score(query, key)
        let keywordScore = keywordKeys.compactMap { Search.score(query, $0, fuzzy: false) }.max().map { $0 - 150 }
        return [nameScore, keywordScore].compactMap { $0 }.max()
    }
}

/// System Settings panes. The identifiers are the bundle IDs of the extensions
/// in /System/Library/ExtensionKit/Extensions, opened through the
/// `x-apple.systempreferences:` URL scheme.
enum SettingsCatalog {
    static let all: [SettingEntry] = [
        .init("com.apple.systempreferences.AppleIDSettings", "Apple Account", "person.crop.circle.fill", .blue,
              ["icloud", "apple id", "compte", "account"]),
        .init("com.apple.Family-Settings.extension", "Family", "person.3.fill", .blue, ["famille", "partage familial"]),
        .init("com.apple.wifi-settings-extension", "Wi-Fi", "wifi", .blue,
              ["wifi", "wireless", "sans fil", "internet", "réseau"]),
        .init("com.apple.BluetoothSettings", "Bluetooth", "dot.radiowaves.left.and.right", .blue,
              ["airpods", "casque", "headphones", "souris", "clavier"]),
        .init("com.apple.Network-Settings.extension", "Network", "network", .blue,
              ["réseau", "ethernet", "ip", "dns", "proxy", "firewall", "pare-feu"]),
        .init("com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", "VPN", "network.badge.shield.half.filled", .blue),
        .init("com.apple.Notifications-Settings.extension", "Notifications", "bell.badge.fill", .red,
              ["alertes", "alerts", "badges"]),
        .init("com.apple.Sound-Settings.extension", "Sound", "speaker.wave.2.fill", .pink,
              ["son", "volume", "audio", "micro", "microphone", "sortie", "output", "entrée", "input", "haut-parleur", "speaker"]),
        .init("com.apple.Focus-Settings.extension", "Focus", "moon.fill", .indigo,
              ["concentration", "ne pas déranger", "do not disturb"]),
        .init("com.apple.Screen-Time-Settings.extension", "Screen Time", "hourglass", .indigo,
              ["temps d'écran", "contrôle parental", "parental"]),
        .init("com.apple.systempreferences.GeneralSettings", "General", "gearshape.fill", .gray, ["général"]),
        .init("com.apple.SystemProfiler.AboutExtension", "About", "info.circle.fill", .gray,
              ["à propos", "about this mac", "numéro de série", "serial", "modèle", "version"]),
        .init("com.apple.Software-Update-Settings.extension", "Software Update", "arrow.down.circle.fill", .gray,
              ["mise à jour", "update", "upgrade", "macos"]),
        .init("com.apple.settings.Storage", "Storage", "internaldrive.fill", .gray,
              ["stockage", "disque", "disk", "espace", "space"]),
        .init("com.apple.AirDrop-Handoff-Settings.extension", "AirDrop & Handoff", "airplayaudio", .gray,
              ["airdrop", "handoff", "continuité", "continuity"]),
        .init("com.apple.LoginItems-Settings.extension", "Login Items & Extensions", "list.bullet.rectangle.fill", .gray,
              ["ouverture", "démarrage", "startup", "login", "extensions"]),
        .init("com.apple.Localization-Settings.extension", "Language & Region", "globe", .gray,
              ["langue", "région", "language", "format"]),
        .init("com.apple.Date-Time-Settings.extension", "Date & Time", "clock.fill", .gray,
              ["date", "heure", "time", "horloge", "clock", "fuseau", "timezone"]),
        .init("com.apple.Sharing-Settings.extension", "Sharing", "square.and.arrow.up.fill", .gray,
              ["partage", "ssh", "remote", "à distance", "screen sharing", "partage d'écran", "file sharing", "nom de l'ordinateur", "computer name"]),
        .init("com.apple.Time-Machine-Settings.extension", "Time Machine", "clock.arrow.circlepath", .gray,
              ["sauvegarde", "backup"]),
        .init("com.apple.Transfer-Reset-Settings.extension", "Transfer or Reset", "arrow.counterclockwise.circle.fill", .gray,
              ["réinitialiser", "reset", "effacer", "erase", "transfert"]),
        .init("com.apple.Startup-Disk-Settings.extension", "Startup Disk", "externaldrive.fill", .gray,
              ["disque de démarrage", "boot"]),
        .init("com.apple.Profiles-Settings.extension", "Device Management", "checkmark.shield.fill", .gray,
              ["profils", "profiles", "mdm"]),
        .init("com.apple.Accessibility-Settings.extension", "Accessibility", "accessibility", .blue,
              ["accessibilité", "zoom", "voiceover", "contraste", "contrast"]),
        .init("com.apple.Appearance-Settings.extension", "Appearance", "circle.lefthalf.filled", .black,
              ["apparence", "dark mode", "mode sombre", "clair", "light", "thème", "theme", "accent", "couleur"]),
        .init("com.apple.ControlCenter-Settings.extension", "Control Center", "switch.2", .gray,
              ["centre de contrôle", "barre des menus", "menu bar"]),
        .init("com.apple.Desktop-Settings.extension", "Desktop & Dock", "dock.rectangle", .black,
              ["bureau", "dock", "mission control", "stage manager", "coins actifs", "hot corners", "fenêtres", "windows", "widgets"]),
        .init("com.apple.Displays-Settings.extension", "Displays", "sun.max.fill", .blue,
              ["écran", "moniteur", "monitor", "luminosité", "brightness", "résolution", "resolution", "night shift"]),
        .init("com.apple.Spotlight-Settings.extension", "Spotlight", "magnifyingglass", .gray, ["recherche", "search"]),
        .init("com.apple.Wallpaper-Settings.extension", "Wallpaper", "photo.fill", .cyan,
              ["fond d'écran", "background", "économiseur", "screen saver"]),
        .init("com.apple.Battery-Settings.extension", "Battery", "battery.100percent", .green,
              ["batterie", "énergie", "energy", "power", "veille", "sleep"]),
        .init("com.apple.Lock-Screen-Settings.extension", "Lock Screen", "lock.fill", .black,
              ["écran de verrouillage", "verrouillage", "économiseur", "screen saver"]),
        .init("com.apple.settings.PrivacySecurity.extension", "Privacy & Security", "hand.raised.fill", .blue,
              ["confidentialité", "sécurité", "security", "privacy", "permissions", "autorisations", "caméra", "camera", "filevault", "gatekeeper", "accès complet au disque", "full disk access"]),
        .init("com.apple.Touch-ID-Settings.extension", "Touch ID & Password", "touchid", .red,
              ["mot de passe", "password", "empreinte", "fingerprint"]),
        .init("com.apple.Users-Groups-Settings.extension", "Users & Groups", "person.2.fill", .blue,
              ["utilisateurs", "groupes", "users", "compte", "account", "avatar"]),
        .init("com.apple.Internet-Accounts-Settings.extension", "Internet Accounts", "at", .blue,
              ["comptes internet", "mail", "google", "exchange"]),
        .init("com.apple.Game-Center-Settings.extension", "Game Center", "gamecontroller.fill", .gray, ["jeux"]),
        .init("com.apple.Game-Controller-Settings.extension", "Game Controllers", "gamecontroller", .gray,
              ["manette", "controller", "jeux"]),
        .init("com.apple.WalletSettingsExtension", "Wallet & Apple Pay", "wallet.pass.fill", .black,
              ["cartes", "cards", "paiement", "payment"]),
        .init("com.apple.Keyboard-Settings.extension", "Keyboard", "keyboard.fill", .gray,
              ["clavier", "raccourcis", "shortcuts", "dictée", "dictation", "sources de saisie", "input sources"]),
        .init("com.apple.Mouse-Settings.extension", "Mouse", "computermouse.fill", .gray,
              ["souris", "défilement", "scroll"]),
        .init("com.apple.Trackpad-Settings.extension", "Trackpad", "rectangle.and.hand.point.up.left.fill", .gray,
              ["gestes", "gestures", "clic", "click", "défilement", "scroll"]),
        .init("com.apple.Print-Scan-Settings.extension", "Printers & Scanners", "printer.fill", .gray,
              ["imprimante", "printer", "scanner"]),
        .init("com.apple.Siri-Settings.extension", "Apple Intelligence & Siri", "sparkles", .purple,
              ["siri", "apple intelligence", "assistant"]),
    ]
}
