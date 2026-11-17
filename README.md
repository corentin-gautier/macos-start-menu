# Mac Start Menu

A Windows-style start menu for macOS. Tap **⌘ Command** on its own (press and
release, no other key) and a panel opens right below the Apple menu with:

- **All your apps** in a grid, alphabetically — read straight from the app
  folders, so no documents, archives or other Spotlight noise ever shows up.
- A **search field, already focused**: typing filters and ranks the apps and
  also suggests the matching **System Settings** panes (English and French
  keywords: "wifi", "dark mode", "mode sombre", "luminosité"…).
- **Icon buttons**: App Store, Activity Monitor, Force Quit, System Settings,
  About This Mac, then Lock, Log Out, Sleep, Restart, Shut Down.
- **Your account** with its avatar (opens Users & Groups).

| Key | Action |
| --- | --- |
| ⌘ alone | Open / close the menu |
| Type | Search apps and settings |
| ← → ↑ ↓ | Move through the results |
| Return | Open the selected result |
| Escape, or click outside | Close |
| ⌘Q (menu open) | Quit Start Menu |

Right-click an app to show it in the Finder.

## Install

Requirements: macOS 14 or later, Xcode or the Command Line Tools (Swift 5.10+).

```sh
scripts/setup-signing.sh   # once: creates a local code signing certificate
scripts/install.sh         # builds, installs, starts now and at every login
```

On first launch macOS asks for the **Accessibility** permission
(System Settings › Privacy & Security › Accessibility › enable *Start Menu*).
It is needed to notice the Command key presses anywhere and to trigger
Force Quit (⌥⌘⎋). The menu works as soon as the switch is on, no restart
needed.

Restart and Shut Down open the usual macOS confirmation dialog. The first time,
macOS may ask to let Start Menu control "loginwindow": accept.

Uninstall: `scripts/uninstall.sh`.

## How it works

- **Command tap**: a listen-only `CGEventTap` watches modifier changes. A
  Command press counts as a tap only if it is released within 0.45 s with no
  key, click or other modifier in between, so shortcuts like ⌘C are never
  affected.
- **Panel**: a borderless, non-activating `NSPanel` (glass background on
  macOS 26+) hosting a SwiftUI view. It takes the keyboard without making the
  frontmost app lose focus, and hides as soon as it loses focus.
- **Apps**: `/Applications`, `/System/Applications` and `~/Applications`,
  scanned two levels deep (Utilities and vendor folders included), rescanned
  every time the menu opens.
- **Settings**: a curated list of System Settings panes, opened through
  `x-apple.systempreferences:<extension bundle id>`.
- **Signing**: builds are signed with a self-signed certificate so the
  Accessibility permission survives rebuilds (an ad-hoc signature changes with
  every build and macOS would ask again).

## Project layout

```
Package.swift                 SwiftPM executable target
Resources/Info.plist          bundle info (agent app: no Dock icon, no menu bar)
Sources/StartMenu/
  main.swift, AppDelegate.swift
  CommandKeyMonitor.swift     lone ⌘ tap detection
  StartPanelController.swift  panel window, position, keyboard
  StartMenuModel.swift        search state, ranking, navigation, actions
  StartMenuView.swift         SwiftUI interface
  AppCatalog.swift            app discovery and icon cache
  SettingsCatalog.swift       System Settings panes and keywords
  Search.swift                matching and scoring
  SystemActions.swift         power, lock, force quit, avatar
scripts/                      setup-signing, build, install, uninstall
```
