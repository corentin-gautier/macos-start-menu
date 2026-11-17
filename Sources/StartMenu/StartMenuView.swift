import SwiftUI

/// Two looks, picked in the sort menu (`UIStyle`):
/// - Liquid Glass: glass capsules for the controls and grouped bottom
///   buttons, glass highlights, radii concentric with the panel's.
/// - Classic: flat translucent fills, a divider above a single bottom bar.
/// Glass: the results scroll under the top and bottom controls (soft scroll
/// edge effect, bottom fade). Classic: the bars sit above and below the list.
struct StartMenuView: View {
    @ObservedObject var model: StartMenuModel
    @FocusState private var searchFocused: Bool
    private static let topID = "top"

    /// Height of the search field and sort button.
    static let controlHeight: CGFloat = 44
    /// Gap between the panel edge and the controls.
    static let inset: CGFloat = 12

    private var style: UIStyle { model.style }

    var body: some View {
        VStack(spacing: 0) {
            // Classic's flat fills would show the list through: its bar sits
            // above the list instead of floating over it.
            if style == .classic { topBar.padding(.bottom, 6) }
            ScrollViewReader { proxy in
                ScrollView {
                    results
                        .padding(.horizontal, Self.inset)
                        .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .mask { if style == .glass { bottomFade } else { Color.black } }
                .safeAreaInset(edge: .top, spacing: 6) {
                    if style == .glass { topBar }
                }
                // An overlay, not a safe area inset: the inset shrinks the
                // scroll view, which put the fade above the capsules.
                .contentMargins(.bottom, style == .glass ? Self.glassBottomBarHeight : 0, for: .scrollContent)
                .overlay(alignment: .bottom) {
                    if style == .glass { BottomBar(model: model) }
                }
                .onChange(of: model.selection) { _, index in
                    guard model.showsSelection, let id = model.resultID(at: index) else { return }
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
                }
                .onChange(of: model.showToken) { _, _ in
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            }
            if style == .classic {
                Divider().opacity(0.6)
                BottomBar(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NSGlassEffectView doesn't clip its content to its rounded shape.
        .clipShape(RoundedRectangle(cornerRadius: style.panelCornerRadius, style: .continuous))
        .coordinateSpace(name: HoverSpace.name)
        .overlay { TooltipLayer(model: model) }
        .overlay {
            if let request = model.pendingUninstall {
                UninstallConfirmation(request: request, model: model)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: model.showToken) { _, _ in searchFocused = true }
    }

    /// Capsules (40) plus their bottom inset, and a little air.
    static let glassBottomBarHeight: CGFloat = 40 + inset + 8

    /// Glass: the list scrolls under the bottom capsules and fades out before
    /// the panel edge, so nothing shows below them.
    private var bottomFade: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
            // Fully gone from the capsules' bottom edge down.
            Color.clear.frame(height: Self.inset + 4)
        }
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
        .controlSurface(style)
    }

    private var sortButton: some View {
        // A plain button over the whole surface (a SwiftUI Menu only reacts
        // on its label), opening a native menu below itself.
        Button { SortMenu.show(model: model) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text(model.sortMode.title)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: Self.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlSurface(style, interactive: true)
        .hoverFrame(HoverSpace.sortID)
        .fixedSize()
        .opacity(model.isSearching ? 0.5 : 1)
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
                style: style,
                selected: model.highlightedIndex == index,
                hovered: model.hoveredID == HoverSpace.resultID(result.id)
            )
            Group {
                switch result {
                case .app(let app):
                    AppTile(
                        app: app,
                        asRow: !section.isGrid,
                        state: state,
                        isHidden: model.isHidden(app),
                        onToggleHidden: { model.setHidden(app, !model.isHidden(app)) },
                        onUninstall: AppUninstaller.canUninstall(app) ? { model.uninstall(app) } : nil
                    )
                case .setting(let setting):
                    SettingRow(setting: setting, state: state)
                case .folder(let folder):
                    FolderRow(folder: folder, state: state)
                }
            }
            .hoverFrame(HoverSpace.resultID(result.id))
            .onTapGesture { model.activate(index: index) }
        }
    }
}

// MARK: - Style helpers

extension UIStyle {
    var panelCornerRadius: CGFloat { self == .glass ? 28 : 20 }
}

private extension View {
    /// Background of the search field and sort button.
    @ViewBuilder
    func controlSurface(_ style: UIStyle, interactive: Bool = false) -> some View {
        switch style {
        case .glass:
            glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        case .classic:
            background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
    }

    /// Background of a bottom bar button: a glass capsule, or a flat fill on hover.
    @ViewBuilder
    func barSurface(_ style: UIStyle, hovered: Bool, in shape: some Shape) -> some View {
        switch style {
        case .glass:
            background(shape.fill(Color.primary.opacity(hovered ? 0.08 : 0)))
        case .classic:
            background(shape.fill(Color.primary.opacity(hovered ? 0.1 : 0)))
        }
    }
}

struct HighlightState {
    let style: UIStyle
    let selected: Bool
    let hovered: Bool
}

/// Hover and keyboard selection: glass (tinted when selected) or flat fills.
private struct ResultHighlight: ViewModifier {
    let state: HighlightState
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch state.style {
        case .glass:
            // Glass only behind the active tile: an effect on every tile, even
            // `.identity`, slows scrolling down.
            content.background {
                if state.selected || state.hovered {
                    Color.clear.glassEffect(
                        state.selected ? .regular.tint(.accentColor.opacity(0.55)) : .regular,
                        in: shape
                    )
                }
            }
        case .classic:
            content.background(shape.fill(
                state.selected ? Color.accentColor.opacity(0.3)
                    : state.hovered ? Color.primary.opacity(0.08) : .clear
            ))
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

/// An app as a grid tile, or as a list row (icon, name, category).
private struct AppTile: View {
    let app: AppEntry
    let asRow: Bool
    let state: HighlightState
    let isHidden: Bool
    let onToggleHidden: () -> Void
    let onUninstall: (() -> Void)?

    private var cornerRadius: CGFloat {
        switch (state.style, asRow) {
        case (.glass, false): 18
        case (.glass, true): 14
        case (.classic, _): 10
        }
    }
    /// Text on tinted glass needs to be white to stay readable.
    private var whiteText: Bool { state.style == .glass && state.selected }

    var body: some View {
        Group {
            if asRow { row } else { tile }
        }
        .opacity(isHidden ? 0.4 : 1)
        .modifier(ResultHighlight(state: state, cornerRadius: cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    private var tile: some View {
        VStack(spacing: 6) {
            Image(nsImage: IconCache.shared.icon(for: app.url))
                .resizable()
                .frame(width: 50, height: 50)
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(whiteText ? .white : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private var row: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.shared.icon(for: app.url))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 13, weight: .medium))
                Text(app.category.title)
                    .font(.system(size: 11))
                    .foregroundStyle(whiteText ? .white.opacity(0.8) : .secondary)
            }
            .foregroundStyle(whiteText ? .white : .primary)
            .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private struct SettingRow: View {
    let setting: SettingEntry
    let state: HighlightState

    private var whiteText: Bool { state.style == .glass && state.selected }

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
                    .foregroundStyle(whiteText ? .white.opacity(0.8) : .secondary)
            }
            .foregroundStyle(whiteText ? .white : .primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .modifier(ResultHighlight(state: state, cornerRadius: state.style == .glass ? 14 : 10))
        .contentShape(Rectangle())
    }
}

private struct FolderRow: View {
    let folder: FolderEntry
    let state: HighlightState

    private var whiteText: Bool { state.style == .glass && state.selected }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: FolderCatalog.icon(for: folder))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name).font(.system(size: 13, weight: .medium))
                Text(AppUninstaller.abbreviate(folder.url))
                    .font(.system(size: 11))
                    .foregroundStyle(whiteText ? .white.opacity(0.8) : .secondary)
            }
            .foregroundStyle(whiteText ? .white : .primary)
            .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .modifier(ResultHighlight(state: state, cornerRadius: state.style == .glass ? 14 : 10))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            }
        }
    }
}

// MARK: - Bottom bar

/// Account, session, tools and power buttons: glass capsules per group, or
/// one flat bar with dividers.
private struct BottomBar: View {
    @ObservedObject var model: StartMenuModel

    var body: some View {
        Group {
            if model.style == .glass {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        UserButton(model: model)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        group(SystemAction.session)
                        Spacer(minLength: 4)
                        group(SystemAction.tools)
                        group(SystemAction.power)
                    }
                }
                .padding([.horizontal, .bottom], StartMenuView.inset)
            } else {
                HStack(spacing: 2) {
                    UserButton(model: model)
                    divider
                    buttons(SystemAction.session)
                    Spacer(minLength: 8)
                    buttons(SystemAction.tools)
                    divider
                    buttons(SystemAction.power)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .hoverFrame(HoverSpace.blockerID("bottom"))
    }

    private var divider: some View {
        Divider().frame(height: 20).padding(.horizontal, 6)
    }

    private func buttons(_ actions: [SystemAction]) -> some View {
        ForEach(actions) { IconButton(action: $0, model: model) }
    }

    /// Several icon buttons sharing one glass capsule, like a toolbar group.
    private func group(_ actions: [SystemAction]) -> some View {
        HStack(spacing: 0) { buttons(actions) }
            .padding(.horizontal, 3)
            .frame(height: 40)
            .glassEffect(.regular, in: .capsule)
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
            .barSurface(model.style, hovered: hovered, in: Capsule())
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .hoverFrame(HoverSpace.userID)
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
                    Image(systemName: action.symbol).font(.system(size: action.symbolSize, weight: .medium))
                }
            }
            .frame(width: 34, height: 34)
            .barSurface(model.style, hovered: hovered, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverFrame(HoverSpace.actionID(action))
    }
}

// MARK: - Tooltip

/// Native tooltips (`.help`) don't show in a panel of an inactive app, so the
/// hovered button's name floats above it, without touching the layout.
private struct TooltipLayer: View {
    @ObservedObject var model: StartMenuModel
    @State private var width: CGFloat = 0
    private let margin: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            if let tooltip = model.tooltip {
                let label = HStack(spacing: 8) {
                    Text(tooltip.text)
                    if let shortcut = tooltip.shortcut {
                        Text(shortcut).foregroundStyle(.secondary)
                    }
                }
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                let half = width / 2 + margin
                label
                    .modifier(TooltipSurface(style: model.style))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    .position(
                        // Centered on the control, kept whole inside the panel.
                        x: min(max(tooltip.anchor.midX, half), geometry.size.width - half),
                        // Above the control, or below when it is at the top edge.
                        y: tooltip.anchor.minY > 40 ? tooltip.anchor.minY - 18 : tooltip.anchor.maxY + 18
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.tooltip?.text)
    }
}

private struct TooltipSurface: ViewModifier {
    let style: UIStyle

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            content.glassEffect(.regular, in: .capsule)
        case .classic:
            content.background(Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.15), radius: 4, y: 1))
        }
    }
}

// MARK: - Sort menu

/// Sort choices, hidden apps, view and style as a native menu, right-aligned under
/// the sort button.
private enum SortMenu {
    private final class Target: NSObject {
        let model: StartMenuModel
        init(model: StartMenuModel) { self.model = model }

        @objc func pickSort(_ item: NSMenuItem) {
            if let mode = item.representedObject as? SortMode { model.sortMode = mode }
        }

        @objc func pickLayout(_ item: NSMenuItem) {
            if let layout = item.representedObject as? AppLayout { model.layout = layout }
        }

        @objc func pickStyle(_ item: NSMenuItem) {
            if let style = item.representedObject as? UIStyle { model.style = style }
        }

        @objc func toggleHidden(_ item: NSMenuItem) {
            model.toggleShowsHidden()
        }
    }

    static func show(model: StartMenuModel) {
        let target = Target(model: model)
        let menu = NSMenu()
        menu.autoenablesItems = false

        func addItem(_ title: String, symbol: String, action: Selector, object: Any?, checked: Bool) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = object
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.state = checked ? .on : .off
            menu.addItem(item)
            return item
        }

        menu.addItem(NSMenuItem.sectionHeader(title: "Sort apps"))
        for mode in SortMode.allCases {
            _ = addItem(mode.title, symbol: mode.symbol, action: #selector(Target.pickSort(_:)),
                        object: mode, checked: mode == model.sortMode)
        }
        menu.addItem(.separator())
        let count = model.hiddenCount
        let hidden = addItem(count == 0 ? "No Hidden Apps" : "Show Hidden Apps (\(count))", symbol: "eye.slash",
                             action: #selector(Target.toggleHidden(_:)), object: nil, checked: model.showsHidden)
        hidden.isEnabled = count > 0

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "View"))
        for layout in AppLayout.allCases {
            _ = addItem(layout.title, symbol: layout.symbol, action: #selector(Target.pickLayout(_:)),
                        object: layout, checked: layout == model.layout)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Style"))
        for style in UIStyle.allCases {
            _ = addItem(style.title, symbol: style.symbol, action: #selector(Target.pickStyle(_:)),
                        object: style, checked: style == model.style)
        }

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

/// Card shown over the panel before uninstalling an app.
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
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
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
            buttons.controlSize(.large).padding(.top, 6)
        }
        .padding(22)
        .frame(width: 360)

        switch model.style {
        case .glass:
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        case .classic:
            content.background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 20)
            )
        }
    }

    /// Stacked full-width buttons, like macOS alerts; Cancel is the default.
    @ViewBuilder
    private var buttons: some View {
        let trash = Button { model.confirmUninstall() } label: {
            Text("Move to Trash").frame(maxWidth: .infinity)
        }
        let cancel = Button { model.cancelUninstall() } label: {
            Text("Cancel").frame(maxWidth: .infinity)
        }
        VStack(spacing: 8) {
            if model.style == .glass {
                trash.buttonStyle(.glass)
                cancel.buttonStyle(.glassProminent)
            } else {
                trash.buttonStyle(.bordered)
                cancel.buttonStyle(.borderedProminent)
            }
        }
    }
}
