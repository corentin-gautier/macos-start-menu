import SwiftUI

/// Liquid Glass layout: the results scroll under the floating glass search
/// and sort controls, with the system's soft scroll edge effect; the glass
/// account and action capsules sit below the list. Corner radii are concentric with the
/// panel's (`Layout.cornerRadius`).
struct StartMenuView: View {
    @ObservedObject var model: StartMenuModel
    @FocusState private var searchFocused: Bool
    private static let topID = "top"

    /// Height of the search field and sort button.
    static let controlHeight: CGFloat = 44
    /// Gap between the panel edge and the floating controls.
    static let inset: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
        ScrollViewReader { proxy in
            ScrollView {
                results
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .safeAreaInset(edge: .top, spacing: 6) { topBar }
            .onChange(of: model.selection) { _, index in
                guard model.showsSelection, let id = model.resultID(at: index) else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
            }
            .onChange(of: model.showToken) { _, _ in
                proxy.scrollTo(Self.topID, anchor: .top)
            }
        }
            // The bottom bar sits below the list: content scrolling under it
            // showed between the capsules and the panel edge.
            BottomBar(model: model)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NSGlassEffectView doesn't clip its content to its rounded shape.
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .coordinateSpace(name: HoverSpace.name)
        .onPreferenceChange(HoverFramesKey.self) { model.updateHoverFrames($0) }
        .overlay {
            if let request = model.pendingUninstall {
                UninstallConfirmation(request: request, model: model)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: model.showToken) { _, _ in searchFocused = true }
    }

    // MARK: - Top bar

    private var topBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                searchField
                sortButton
            }
        }
        .padding([.horizontal, .top], Self.inset)
        .hoverFrame(HoverSpace.blockerID("top"))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search apps and settings", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.controlHeight)
        .glassEffect(.regular, in: .capsule)
    }

    private var sortButton: some View {
        // A plain button over the whole capsule (a SwiftUI Menu only reacts
        // on its label), opening a native menu below itself.
        Button { SortMenu.show(model: model) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text(model.sortMode.title)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: Self.controlHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize()
        .opacity(model.isSearching ? 0.5 : 1)
        .help("Sort apps")
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if model.isSearching && model.resultCount == 0 {
            Text("No Results")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else {
            LazyVStack(alignment: .leading, spacing: 4) {
                Color.clear.frame(height: 0).id(Self.topID)
                ForEach(model.sections) { section in
                    SectionHeader(title: section.title)
                    if section.isGrid {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: Layout.gridColumns),
                            spacing: 4
                        ) {
                            items(of: section)
                        }
                        .padding(.bottom, 10)
                    } else {
                        items(of: section)
                    }
                }
            }
        }
    }

    private func items(of section: ResultSection) -> some View {
        ForEach(Array(section.items.enumerated()), id: \.element.id) { offset, result in
            let index = section.startIndex + offset
            let state = HighlightState(
                selected: model.highlightedIndex == index,
                hovered: model.hoveredID == HoverSpace.resultID(result.id)
            )
            Group {
                switch result {
                case .app(let app):
                    AppTile(
                        app: app,
                        state: state,
                        isHidden: model.isHidden(app),
                        onToggleHidden: { model.setHidden(app, !model.isHidden(app)) },
                        onUninstall: AppUninstaller.canUninstall(app) ? { model.uninstall(app) } : nil
                    )
                case .setting(let setting):
                    SettingRow(setting: setting, state: state)
                }
            }
            .hoverFrame(HoverSpace.resultID(result.id))
            .onTapGesture { model.activate(index: index) }
        }
    }
}

// MARK: - Results views

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

struct HighlightState {
    let selected: Bool
    let hovered: Bool
}

/// Selection is tinted glass, hover is plain glass, both concentric with the panel.
private struct GlassHighlight: ViewModifier {
    let state: HighlightState
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let glass: Glass = state.selected
            ? .regular.tint(.accentColor.opacity(0.55))
            : state.hovered ? .regular : .identity
        content.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct AppTile: View {
    let app: AppEntry
    let state: HighlightState
    let isHidden: Bool
    let onToggleHidden: () -> Void
    let onUninstall: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: IconCache.shared.icon(for: app.url))
                .resizable()
                .frame(width: 52, height: 52)
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state.selected ? .white : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .opacity(isHidden ? 0.4 : 1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .modifier(GlassHighlight(state: state, cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
            Button(isHidden ? "Unhide" : "Hide", systemImage: isHidden ? "eye" : "eye.slash", action: onToggleHidden)
            if let onUninstall {
                Divider()
                Button("Uninstall…", systemImage: "trash", role: .destructive, action: onUninstall)
            }
        }
    }
}

private struct SettingRow: View {
    let setting: SettingEntry
    let state: HighlightState

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(setting.color.gradient)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: setting.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(setting.name).font(.system(size: 13, weight: .medium))
                Text("System Settings")
                    .font(.system(size: 11))
                    .foregroundStyle(state.selected ? .white.opacity(0.8) : .secondary)
            }
            .foregroundStyle(state.selected ? .white : .primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .modifier(GlassHighlight(state: state, cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Bottom bar

/// Floating glass capsules: account, session, tools, power.
private struct BottomBar: View {
    @ObservedObject var model: StartMenuModel

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                UserButton(model: model)
                ButtonGroup(actions: SystemAction.session, model: model)
                Spacer(minLength: 4)
                // Tooltips don't show in a panel of an inactive app, so the
                // hovered button's name is shown here instead.
                Text(model.hoveredAction?.title ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ButtonGroup(actions: SystemAction.tools, model: model)
                ButtonGroup(actions: SystemAction.power, model: model)
            }
        }
        .padding([.horizontal, .bottom], StartMenuView.inset)
        .hoverFrame(HoverSpace.blockerID("bottom"))
    }
}

private struct UserButton: View {
    @ObservedObject var model: StartMenuModel

    var body: some View {
        let hovered = model.hoveredID == HoverSpace.userID
        Button(action: model.openUserSettings) {
            HStack(spacing: 8) {
                Group {
                    if let avatar = model.avatar {
                        Image(nsImage: avatar).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                Text(model.userName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .frame(height: 40)
            .background(Capsule().fill(Color.primary.opacity(hovered ? 0.08 : 0)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .hoverFrame(HoverSpace.userID)
        .help("Users & Groups")
    }
}

/// Several icon buttons sharing one glass capsule, like a toolbar group.
private struct ButtonGroup: View {
    let actions: [SystemAction]
    @ObservedObject var model: StartMenuModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions) { IconButton(action: $0, model: model) }
        }
        .padding(.horizontal, 3)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct IconButton: View {
    let action: SystemAction
    @ObservedObject var model: StartMenuModel

    var body: some View {
        let hovered = model.hoveredID == HoverSpace.actionID(action)
        Button { model.perform(action) } label: {
            Group {
                if let url = action.appIconURL {
                    Image(nsImage: IconCache.shared.icon(for: url)).resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: action.symbol).font(.system(size: 14, weight: .medium))
                }
            }
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.primary.opacity(hovered ? 0.1 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(action.title)
        .hoverFrame(HoverSpace.actionID(action))
    }
}

// MARK: - Sort menu

/// The sort choices as a native menu, right-aligned under the sort button.
private enum SortMenu {
    private final class Target: NSObject {
        let model: StartMenuModel
        init(model: StartMenuModel) { self.model = model }

        @objc func pick(_ item: NSMenuItem) {
            if let mode = item.representedObject as? SortMode { model.sortMode = mode }
        }

        @objc func toggleHidden(_ item: NSMenuItem) {
            model.toggleShowsHidden()
        }
    }

    static func show(model: StartMenuModel) {
        let target = Target(model: model)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem.sectionHeader(title: "Sort apps"))
        for mode in SortMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(Target.pick(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = mode
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            item.state = mode == model.sortMode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let count = model.hiddenCount
        let hiddenItem = NSMenuItem(
            title: count == 0 ? "No Hidden Apps" : "Show Hidden Apps (\(count))",
            action: #selector(Target.toggleHidden(_:)),
            keyEquivalent: ""
        )
        hiddenItem.target = target
        hiddenItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        hiddenItem.state = model.showsHidden ? .on : .off
        hiddenItem.isEnabled = count > 0
        menu.addItem(hiddenItem)

        var origin = NSEvent.mouseLocation
        if let panel = NSApp.windows.first(where: { $0 is StartPanel && $0.isVisible }) {
            origin = NSPoint(
                x: panel.frame.maxX - StartMenuView.inset - menu.size.width,
                y: panel.frame.maxY - StartMenuView.inset - StartMenuView.controlHeight - 6
            )
        }
        // popUp blocks until the menu closes, which keeps `target` alive.
        menu.popUp(positioning: nil, at: origin, in: nil)
        withExtendedLifetime(target) {}
    }
}

// MARK: - Uninstall confirmation

/// Glass card shown over the panel before uninstalling an app.
private struct UninstallConfirmation: View {
    let request: UninstallRequest
    @ObservedObject var model: StartMenuModel

    private var message: String {
        let count = request.leftovers.count
        return count == 0
            ? "The app will be moved to the Trash."
            : "The app and the \(count) item\(count == 1 ? "" : "s") it left in your Library "
                + "(settings, caches, data) will be moved to the Trash."
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { model.cancelUninstall() }

            VStack(alignment: .leading, spacing: 12) {
                Image(nsImage: IconCache.shared.icon(for: request.app.url))
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Uninstall “\(request.app.name)”?")
                    .font(.system(size: 15, weight: .bold))
                Text(message)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                if !request.leftovers.isEmpty {
                    ScrollView {
                        Text(request.leftovers.map(AppUninstaller.abbreviate).joined(separator: "\n"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                    .fixedSize(horizontal: false, vertical: true)
                }
                // Stacked full-width capsules, like macOS alerts.
                VStack(spacing: 8) {
                    Button { model.confirmUninstall() } label: {
                        Text("Move to Trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button { model.cancelUninstall() } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(22)
            .frame(width: 360)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}
