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
                // Glass: the fades below replace the edge effect, which hid
                // the tiles under the search capsules (nothing to refract).
                .scrollEdgeEffectHidden(style == .glass, for: .vertical)
                .mask { if style == .glass { edgeFades } else { Color.black } }
                // Overlays, not safe area insets: an inset shrinks the scroll
                // view, so the results wouldn't pass under the capsules.
                .contentMargins(.top, style == .glass ? Self.glassTopBarHeight : 0, for: .scrollContent)
                .contentMargins(.bottom, style == .glass ? Self.glassBottomBarHeight : 0, for: .scrollContent)
                .overlay(alignment: .top) {
                    if style == .glass { topBar }
                }
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
            } else if let apps = model.forceQuitApps {
                ForceQuitWindow(apps: apps, model: model)
            } else if let step = model.onboarding {
                OnboardingCard(step: step, model: model)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: model.showToken) { _, _ in searchFocused = true }
    }

    /// Capsules (40) plus their bottom inset, and a little air.
    static let glassBottomBarHeight: CGFloat = 40 + inset + 8
    /// Search field plus its top inset, and a little air.
    static let glassTopBarHeight: CGFloat = inset + controlHeight + 6

    /// Glass: the list scrolls under the top and bottom capsules and fades
    /// out before the panel edges, so nothing shows beyond them.
    private var edgeFades: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.inset - 4)
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
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
                settingsButton
            }
        }
        .padding([.horizontal, .top], Self.inset)
        .blocksClicks()
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
        Button { OptionsMenu.show(.sort, model: model) } label: {
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

    private var settingsButton: some View {
        Button { OptionsMenu.show(.settings, model: model) } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlSurface(style, interactive: true)
        .overlay(alignment: .topTrailing) {
            // A newer version is available (listed in the menu).
            if model.availableUpdate != nil {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: -2, y: 2)
            }
        }
        .hoverFrame(HoverSpace.settingsID)
    }

    // MARK: - Results

    /// Pinned item a drag hovers: the dropped item goes before it.
    @State private var dropTarget: String?

    private var results: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 0).id(Self.topID)
            ForEach(model.sections) { section in
                SectionHeader(title: section.title)
                if section.style == .rows {
                    items(of: section)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: section.style.columns),
                        spacing: 4
                    ) {
                        items(of: section)
                    }
                    .padding(.bottom, section.style == .tiles ? 10 : 6)
                }
            }
        }
        // Files, folders and apps dropped from the Finder are pinned.
        .onDrop(of: [.fileURL, StartMenuModel.dragType], isTargeted: nil) { model.drop($0, before: nil) }
    }

    private func items(of section: ResultSection) -> some View {
        ForEach(Array(section.items.enumerated()), id: \.element.id) { offset, result in
            let index = section.startIndex + offset
            let key = section.key(for: result)
            ResultView(
                result: result,
                asTile: section.style == .tiles,
                state: HighlightState(
                    style: style,
                    selected: model.highlightedIndex == index,
                    hovered: model.hoveredID == HoverSpace.resultID(key) || dropTarget == key
                ),
                isPinned: model.isPinned(result),
                isHidden: { if case .app(let app) = result { model.isHidden(app) } else { false } }(),
                isRunning: { if case .app(let app) = result { model.isRunning(app) } else { false } }(),
                model: model
            )
            .id(key)
            .hoverFrame(HoverSpace.resultID(key))
            .onTapGesture { model.activate(index: index) }
            .modifier(DragAndDrop(result: result, key: key, isPinnedSection: section.isPinned,
                                  dropTarget: $dropTarget, model: model))
        }
    }
}

/// Results can be dragged inside the menu (to pin them, or to reorder the
/// pinned ones); pinned items take drops, which land before them.
private struct DragAndDrop: ViewModifier {
    let result: StartResult
    let key: String
    let isPinnedSection: Bool
    @Binding var dropTarget: String?
    let model: StartMenuModel

    func body(content: Content) -> some View {
        if result.isPinnable {
            let draggable = content.onDrag { model.dragProvider(for: result) }
            if isPinnedSection {
                draggable.onDrop(of: [.fileURL, StartMenuModel.dragType], isTargeted: Binding(
                    get: { dropTarget == key },
                    set: { targeted in
                        if targeted { dropTarget = key } else if dropTarget == key { dropTarget = nil }
                    }
                )) { model.drop($0, before: result.id) }
            } else {
                draggable
            }
        } else {
            content
        }
    }
}

// MARK: - Style helpers

extension UIStyle {
    var panelCornerRadius: CGFloat { self == .glass ? 28 : 20 }
}

private extension View {
    /// A floating bar's gaps and margins swallow clicks, which would
    /// otherwise reach the results scrolled under it.
    func blocksClicks() -> some View {
        background(Color.clear.contentShape(Rectangle()).onTapGesture {})
    }

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

/// Any result, as a grid tile (icon over name) or a row (icon, name, detail).
private struct ResultView: View {
    let result: StartResult
    let asTile: Bool
    let state: HighlightState
    let isPinned: Bool
    let isHidden: Bool
    let isRunning: Bool
    /// Not observed: the parent passes the state, the menu only calls actions.
    let model: StartMenuModel

    private var cornerRadius: CGFloat {
        switch (state.style, asTile) {
        case (.glass, true): 18
        case (.glass, false): 14
        case (.classic, _): 10
        }
    }
    /// Text on tinted glass needs to be white to stay readable.
    private var whiteText: Bool { state.style == .glass && state.selected }

    var body: some View {
        Group {
            if asTile { tile } else { row }
        }
        .opacity(isHidden ? 0.4 : 1)
        .modifier(ResultHighlight(state: state, cornerRadius: cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contextMenu { menu }
    }

    private var tile: some View {
        VStack(spacing: 6) {
            icon(size: 50).overlay(alignment: .bottom) { runningDot.offset(y: 5) }
            Text(title)
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
            icon(size: 32).overlay(alignment: .leading) { runningDot.offset(x: -7) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(whiteText ? .white.opacity(0.8) : .secondary)
            }
            .foregroundStyle(whiteText ? .white : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var runningDot: some View {
        if isRunning {
            Circle()
                .fill(whiteText ? Color.white : Color.primary.opacity(0.55))
                .frame(width: 4, height: 4)
        }
    }

    /// `size` is the footprint of an app icon, whose artwork has a margin.
    @ViewBuilder
    private func icon(size: CGFloat) -> some View {
        switch result {
        case .app(let app): image(IconCache.shared.icon(for: app.url), size: size)
        case .setting(let setting): symbolIcon(setting.symbol, color: setting.color, size: size)
        case .folder(let folder): image(FolderCatalog.icon(for: folder), size: size)
        case .file(let file): image(file.icon, size: size)
        case .shortcut:
            if let url = ShortcutCatalog.appURL { image(IconCache.shared.icon(for: url), size: size) }
            else { symbolIcon("square.stack.3d.up.fill", color: .pink, size: size) }
        case .calculation:
            if let url = Self.calculatorURL { image(IconCache.shared.icon(for: url), size: size) }
            else { symbolIcon("equal", color: .orange, size: size) }
        case .webSearch: symbolIcon("magnifyingglass", color: .blue, size: size)
        }
    }

    private static let calculatorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.calculator")

    private func image(_ image: NSImage, size: CGFloat) -> some View {
        Image(nsImage: image).resizable().frame(width: size, height: size)
    }

    private func symbolIcon(_ symbol: String, color: Color, size: CGFloat) -> some View {
        let inner = size * 0.84
        return RoundedRectangle(cornerRadius: inner * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: inner, height: inner)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: inner / 2, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }

    private var title: String {
        switch result {
        case .app(let app): app.name
        case .setting(let setting): setting.name
        case .folder(let folder): folder.name
        case .file(let file): file.name
        case .shortcut(let shortcut): shortcut.name
        case .calculation(let calculation): "= \(calculation.display)"
        case .webSearch(let text):
            model.webSearchEngine.isAssistant ? L("Ask “%@”", text) : L("Search the web for “%@”", text)
        }
    }

    private var subtitle: String {
        switch result {
        case .app(let app): app.category.title
        case .setting: L("System Settings")
        case .folder(let folder): folder.isFinderLocation ? "Finder" : AppUninstaller.abbreviate(folder.url)
        case .file(let file): file.subtitle
        case .shortcut: L("Shortcuts")
        case .calculation: L("Return copies the result")
        case .webSearch: model.webSearchEngine.title
        }
    }

    @ViewBuilder
    private var menu: some View {
        if result.isPinnable {
            Button(isPinned ? L("Unpin") : L("Pin"), systemImage: isPinned ? "pin.slash" : "pin") {
                model.togglePinned(result)
            }
        }
        switch result {
        case .app(let app):
            showInFinder(app.url)
            Button(isHidden ? L("Unhide") : L("Hide"), systemImage: isHidden ? "eye" : "eye.slash") {
                model.setHidden(app, !isHidden)
            }
            if isRunning {
                Divider()
                Button(L("Quit"), systemImage: "xmark.circle") { model.quit(app) }
                Button(L("Force Quit"), systemImage: "xmark.octagon") { model.forceQuit(app) }
            }
            if AppUninstaller.canUninstall(app) {
                Divider()
                Button(L("Uninstall…"), systemImage: "trash", role: .destructive) { model.uninstall(app) }
            }
        case .folder(let folder):
            if !folder.isFinderLocation { showInFinder(folder.url) }
        case .file(let file):
            showInFinder(file.url)
        case .shortcut(let shortcut):
            Button(L("Edit in Shortcuts"), systemImage: "pencil") {
                var components = URLComponents(string: "shortcuts://open-shortcut")
                components?.queryItems = [URLQueryItem(name: "name", value: shortcut.name)]
                if let url = components?.url { NSWorkspace.shared.open(url) }
                model.dismiss()
            }
        case .setting, .calculation, .webSearch:
            EmptyView()
        }
    }

    private func showInFinder(_ url: URL) -> some View {
        Button(L("Show in Finder"), systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
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
        .blocksClicks()
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

// MARK: - Sort and settings menus

/// Native menus right-aligned under their button: sort, view and hidden apps
/// for the sort button; everything else for the settings button.
private enum OptionsMenu {
    enum Kind { case sort, settings }

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

        @objc func toggleLogin(_ item: NSMenuItem) {
            model.toggleOpensAtLogin()
        }

        @objc func toggleDock(_ item: NSMenuItem) {
            model.toggleHidesDock()
        }

        @objc func toggleHidden(_ item: NSMenuItem) {
            model.toggleShowsHidden()
        }

        @objc func toggleRecentFiles(_ item: NSMenuItem) {
            model.showsRecentFiles.toggle()
        }

        @objc func allowFolders(_ item: NSMenuItem) {
            model.dismiss()
            RecentFiles.shared.requestFolderAccess()
        }

        @objc func pickTrigger(_ item: NSMenuItem) {
            if let key = item.representedObject as? TriggerKey { model.triggerKey = key }
        }

        @objc func toggleAppleMenuClick(_ item: NSMenuItem) {
            model.opensOnAppleMenuClick.toggle()
        }

        @objc func pickEngine(_ item: NSMenuItem) {
            if let engine = item.representedObject as? WebSearchEngine { model.webSearchEngine = engine }
        }

        @objc func openUpdate(_ item: NSMenuItem) {
            model.dismiss()
            NSWorkspace.shared.open(UpdateChecker.releasesPage)
        }
    }

    static func show(_ kind: Kind, model: StartMenuModel) {
        let target = Target(model: model)
        let menu = NSMenu()
        menu.autoenablesItems = false

        @discardableResult
        func addItem(_ title: String, symbol: String?, action: Selector, object: Any? = nil, checked: Bool,
                     to parent: NSMenu? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = object
            item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            item.state = checked ? .on : .off
            (parent ?? menu).addItem(item)
            return item
        }

        func addSubmenu(_ title: String, symbol: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            item.submenu = submenu
            menu.addItem(item)
            return submenu
        }

        switch kind {
        case .sort:
            menu.addItem(NSMenuItem.sectionHeader(title: L("Sort apps")))
            for mode in SortMode.allCases {
                addItem(mode.title, symbol: mode.symbol, action: #selector(Target.pickSort(_:)),
                        object: mode, checked: mode == model.sortMode)
            }
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: L("View")))
            for layout in AppLayout.allCases {
                addItem(layout.title, symbol: layout.symbol, action: #selector(Target.pickLayout(_:)),
                        object: layout, checked: layout == model.layout)
            }
            menu.addItem(.separator())
            let count = model.hiddenCount
            let hidden = addItem(count == 0 ? L("No Hidden Apps") : L("Show Hidden Apps (%d)", count),
                                 symbol: "eye.slash", action: #selector(Target.toggleHidden(_:)),
                                 checked: model.showsHidden)
            hidden.isEnabled = count > 0

        case .settings:
            if let version = model.availableUpdate {
                addItem(L("Update Available: Start Menu %@", version), symbol: "arrow.down.circle",
                        action: #selector(Target.openUpdate(_:)), checked: false)
                menu.addItem(.separator())
            }
            menu.addItem(NSMenuItem.sectionHeader(title: L("Style")))
            for style in UIStyle.allCases {
                addItem(style.title, symbol: style.symbol, action: #selector(Target.pickStyle(_:)),
                        object: style, checked: style == model.style)
            }

            menu.addItem(.separator())
            addItem(L("Show Recent Files"), symbol: "doc", action: #selector(Target.toggleRecentFiles(_:)),
                    checked: model.showsRecentFiles)
            if model.showsRecentFiles && RecentFiles.needsFolderAccess {
                addItem(L("Include Desktop, Documents and Downloads…"), symbol: "lock.open",
                        action: #selector(Target.allowFolders(_:)), checked: false)
            }
            let engines = addSubmenu(L("Web Search"), symbol: "globe")
            for engine in WebSearchEngine.searchEngines {
                addItem(engine.title, symbol: nil, action: #selector(Target.pickEngine(_:)),
                        object: engine, checked: engine == model.webSearchEngine, to: engines)
            }
            engines.addItem(.separator())
            engines.addItem(NSMenuItem.sectionHeader(title: L("AI Assistants")))
            for engine in WebSearchEngine.assistants {
                addItem(engine.title, symbol: nil, action: #selector(Target.pickEngine(_:)),
                        object: engine, checked: engine == model.webSearchEngine, to: engines)
            }

            menu.addItem(.separator())
            let triggers = addSubmenu(L("Open Menu With"), symbol: "keyboard")
            for key in TriggerKey.allCases {
                addItem(key.title, symbol: nil, action: #selector(Target.pickTrigger(_:)),
                        object: key, checked: key == model.triggerKey, to: triggers)
            }
            let appleClick = addItem(L("Open on Apple Menu Click"), symbol: "apple.logo",
                                     action: #selector(Target.toggleAppleMenuClick(_:)),
                                     checked: model.opensOnAppleMenuClick)
            appleClick.toolTip = L("⌥-click the Apple logo for the Apple menu.")

            menu.addItem(.separator())
            addItem(L("Open at Login"), symbol: "power.circle", action: #selector(Target.toggleLogin(_:)),
                    checked: model.opensAtLogin)
            addItem(L("Hide the Dock"), symbol: "dock.rectangle", action: #selector(Target.toggleDock(_:)),
                    checked: model.hidesDock)
        }

        var origin = NSEvent.mouseLocation
        // The button's frame is in the panel's top-left coordinates.
        let buttonID = kind == .sort ? HoverSpace.sortID : HoverSpace.settingsID
        if let panel = NSApp.windows.first(where: { $0 is StartPanel && $0.isVisible }),
           let button = HoverRegistry.shared.frames[buttonID] {
            origin = NSPoint(
                x: panel.frame.minX + button.maxX - menu.size.width,
                y: panel.frame.maxY - button.maxY - 6
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
            ? L("The app will be moved to the Trash.")
            : L("The app and the files it left in your Library (%d: settings, caches, data) will be moved to the Trash.", count)
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
            Text(L("Uninstall “%@”?", request.app.name))
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

// MARK: - Force Quit

/// The apps that can be force quit, like the system ⌥⌘⎋ window, drawn in the
/// panel (Start Menu can't open the system one: it is a protected hotkey).
private struct ForceQuitWindow: View {
    let apps: [NSRunningApplication]
    @ObservedObject var model: StartMenuModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { model.closeForceQuit() }
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Force Quit Applications")
                .font(.system(size: 15, weight: .bold))
            Text("If an app doesn’t respond for a while, select its name and click Force Quit.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(apps.enumerated()), id: \.element.processIdentifier) { index, app in
                        row(app, selected: index == model.forceQuitSelection)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectForceQuit(index) }
                    }
                }
            }
            .frame(height: 240)
            buttons.controlSize(.large).padding(.top, 4)
        }
        .padding(22)
        .frame(width: 380)

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

    private func row(_ app: NSRunningApplication, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let url = app.bundleURL {
                Image(nsImage: IconCache.shared.icon(for: url)).resizable().frame(width: 24, height: 24)
            }
            Text(app.localizedName ?? "").font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : .clear))
    }

    @ViewBuilder
    private var buttons: some View {
        let cancel = Button { model.closeForceQuit() } label: {
            Text("Cancel").frame(maxWidth: .infinity)
        }
        let quit = Button { model.forceQuitSelected() } label: {
            Text("Force Quit").frame(maxWidth: .infinity)
        }
        HStack(spacing: 8) {
            if model.style == .glass {
                cancel.buttonStyle(.glass)
                quit.buttonStyle(.glassProminent)
            } else {
                cancel.buttonStyle(.bordered)
                quit.buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Onboarding

/// First launch: explains why Start Menu needs Accessibility and opens the
/// right settings pane; once granted, confirms that tapping ⌘ works.
private struct OnboardingCard: View {
    let step: StartMenuModel.Onboarding
    @ObservedObject var model: StartMenuModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        let content = VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 72, height: 72)
            }
            Text(step == .permission ? L("Welcome to Start Menu") : L("You’re all set"))
                .font(.system(size: 17, weight: .bold))
            Text(step == .permission
                 ? L("To open when you tap ⌘, Start Menu needs the Accessibility permission. It only watches the ⌘ key; nothing you type is recorded.")
                 : L("Tap ⌘ on its own to open the menu anytime."))
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if step == .permission {
                Text(L("Turn on Start Menu in the list, then come back."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            button.controlSize(.large).padding(.top, 4)
        }
        .padding(24)
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

    @ViewBuilder
    private var button: some View {
        let action = step == .permission ? model.requestPermission : { model.onboarding = nil; model.dismiss() }
        let label = Button(action: action) {
            Text(step == .permission ? L("Open Accessibility Settings") : L("Got It"))
                .frame(maxWidth: .infinity)
        }
        if model.style == .glass { label.buttonStyle(.glassProminent) } else { label.buttonStyle(.borderedProminent) }
    }
}
