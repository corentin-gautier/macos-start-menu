import SwiftUI

struct StartMenuView: View {
    @ObservedObject var model: StartMenuModel
    @FocusState private var searchFocused: Bool
    private static let topID = "top"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                searchBar
                sortMenu
            }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    results
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selection) { _, index in
                    guard model.showsSelection, let id = model.resultID(at: index) else { return }
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
                }
                .onChange(of: model.showToken) { _, _ in
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            }

            Divider().opacity(0.6)

            BottomBar(model: model)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { searchFocused = true }
        .onChange(of: model.showToken) { _, _ in searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search apps and settings", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.07)))
    }

    @ViewBuilder
    private var results: some View {
        if model.isSearching && model.resultCount == 0 {
            Text("No results for “\(model.query)”")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            LazyVStack(alignment: .leading, spacing: 6) {
                Color.clear.frame(height: 0).id(Self.topID)
                ForEach(model.sections) { section in
                    SectionHeader(title: section.title)
                    if section.isGrid {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: Layout.gridColumns),
                            spacing: 2
                        ) {
                            items(of: section)
                        }
                        .padding(.bottom, 6)
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
            let selected = model.highlightedIndex == index
            Group {
                switch result {
                case .app(let app): AppTile(app: app, selected: selected)
                case .setting(let setting): SettingRow(setting: setting, selected: selected)
                }
            }
            .onTapGesture { model.activate(index: index) }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort apps", selection: $model.sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                Text(model.sortMode.title)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
        .opacity(model.isSearching ? 0.4 : 1)
        .help("Sort apps")
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

private struct AppTile: View {
    let app: AppEntry
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: IconCache.shared.icon(for: app.url))
                .resizable()
                .frame(width: 46, height: 46)
            Text(app.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Highlight(selected: selected, hovered: hovered))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }
}

private struct SettingRow: View {
    let setting: SettingEntry
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(setting.color.gradient)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: setting.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(setting.name).font(.system(size: 13))
                Text("System Settings").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Highlight(selected: selected, hovered: hovered))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

private struct Highlight: View {
    let selected: Bool
    let hovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(selected ? Color.accentColor.opacity(0.3) : hovered ? Color.primary.opacity(0.08) : .clear)
    }
}

private struct BottomBar: View {
    @ObservedObject var model: StartMenuModel

    var body: some View {
        HStack(spacing: 2) {
            UserButton(model: model)
            Divider().frame(height: 20).padding(.horizontal, 6)
            ForEach(SystemAction.session) { IconButton(action: $0, model: model) }
            Spacer(minLength: 8)
            // Tooltips don't show in a panel of an inactive app, so the hovered
            // button's name is shown here instead.
            Text(model.hoveredAction?.title ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.trailing, 6)
            ForEach(SystemAction.tools) { IconButton(action: $0, model: model) }
            Divider().frame(height: 20).padding(.horizontal, 6)
            ForEach(SystemAction.power) { IconButton(action: $0, model: model) }
        }
    }
}

private struct UserButton: View {
    @ObservedObject var model: StartMenuModel
    @State private var hovered = false

    var body: some View {
        Button(action: model.openUserSettings) {
            HStack(spacing: 8) {
                Group {
                    if let avatar = model.avatar {
                        Image(nsImage: avatar).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                Text(model.userName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(hovered ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Users & Groups")
    }
}

private struct IconButton: View {
    let action: SystemAction
    @ObservedObject var model: StartMenuModel
    @State private var hovered = false

    var body: some View {
        Button { model.perform(action) } label: {
            Group {
                if let url = action.appIconURL {
                    Image(nsImage: IconCache.shared.icon(for: url)).resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: action.symbol).font(.system(size: 14, weight: .medium))
                }
            }
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovered ? Color.primary.opacity(0.1) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(action.title)
        .onHover { isHovered in
            hovered = isHovered
            if isHovered { model.hoveredAction = action }
            else if model.hoveredAction == action { model.hoveredAction = nil }
        }
    }
}
