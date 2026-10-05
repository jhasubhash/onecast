import AppKit
import SwiftUI

/// A bare glyph button for a row's trailing edge; `label` is its hover text and VoiceOver name.
struct DockIconButton: View {
    let symbol: String
    let label: String
    var isDestructive = false
    var isHighlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var tint: AnyShapeStyle {
        if isDestructive { return AnyShapeStyle(Theme.Colors.destructive) }
        if isHighlighted { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.primary)
    }
}

/// A text field that commits on ↵ or when focus leaves, never per keystroke.
///
/// A rename that arrives per keystroke would be refused the moment the field was emptied, so the
/// draft is held here and the owner sees only a finished value.
struct DockTextField: View {
    let value: String
    var prompt = ""
    let accessibilityName: String
    var allowsEmpty = false
    var characterLimit: Int?
    var width: CGFloat? = DockSettingsMetrics.nameFieldWidth
    /// Turns what was typed into what is stored, or nil to refuse it and keep the old value.
    var normalize: (String) -> String? = { $0 }
    let commit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .frame(width: width)
            .focused($focused)
            .pointerStyle(.horizontalText)
            .onSubmit(finish)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { finish() }
            }
            .onChange(of: draft) { _, text in
                if let characterLimit, text.count > characterLimit {
                    draft = String(text.prefix(characterLimit))
                }
            }
            .onAppear { draft = value }
            .onChange(of: value) { _, stored in
                if !focused { draft = stored }
            }
            .accessibilityLabel(accessibilityName)
    }

    private func finish() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsEmpty || !trimmed.isEmpty, let stored = normalize(trimmed), stored != value
        else {
            draft = value
            return
        }
        commit(stored)
        draft = stored
    }
}

/// The named tints as a row of dots, with an optional "none" before them.
struct DockColorSwatches: View {
    let selection: DockColor?
    var allowsNone = false
    let onSelect: (DockColor?) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if allowsNone { swatch(nil) }
            ForEach(DockColor.allCases, id: \.self) { swatch($0) }
        }
    }

    private func swatch(_ color: DockColor?) -> some View {
        let isSelected = color == selection
        return Button {
            onSelect(color)
        } label: {
            ZStack {
                if let color {
                    Circle().fill(color.swatch)
                } else {
                    Circle().strokeBorder(Theme.Colors.border)
                    Image(systemName: "slash.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: DockSettingsMetrics.swatch, height: DockSettingsMetrics.swatch)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 1.5)
                    .padding(-Theme.Spacing.xxs)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(Theme.Spacing.xxs)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color?.title ?? "None")
        .accessibilityLabel(color?.title ?? "No colour")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row's colour dot, which opens the swatches so a tint is changed where it is shown.
struct DockColorMenuButton: View {
    let color: DockColor
    let name: String
    let onSelect: (DockColor) -> Void
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            ColorDot(color: color.swatch)
                .padding(Theme.Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Colour")
        .accessibilityLabel("Colour of \(name)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            DockColorSwatches(selection: color) { choice in
                showing = false
                if let choice { onSelect(choice) }
            }
            .padding(Theme.Spacing.lg)
        }
    }
}

/// A file or app icon from `IconCache`, painting a placeholder while it decodes.
struct DockFileIcon: View {
    let path: String
    var bundleID: String?
    let size: CGFloat
    @State private var image: NSImage?

    init(path: String, bundleID: String? = nil, size: CGFloat) {
        self.path = path
        self.bundleID = bundleID
        self.size = size
        _image = State(initialValue: IconCache.cached(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        .frame(width: size, height: size)
        .task(id: IconRequest([path, bundleID ?? ""])) { await load() }
        .accessibilityHidden(true)
    }

    /// An app that moved since it was pinned still has its bundle ID to be found by.
    private func load() async {
        if let icon = await IconCache.loadAsync(forFile: path) {
            image = icon
            return
        }
        guard let bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            image = nil
            return
        }
        image = await IconCache.loadAsync(forFile: url.path)
    }
}

/// A symbol on a rounded tile, the stand-in for any tile that has no file icon of its own.
struct DockSymbolTile: View {
    let name: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(Theme.Colors.controlSurface)
            .frame(width: size, height: size)
            .overlay {
                SymbolImage(name: name, size: size * 0.5)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
    }
}

/// Rows in the palette's menu shape, in a popover: the palette's own `PopoverMenu` belongs to its
/// panel and arms hover from there, which a Settings window never does.
struct DockPopoverMenu: View {
    let items: [PopoverMenuItem]
    let dismiss: () -> Void
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Size.menuRowSpacing) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0, items[index].startsSection {
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(height: Theme.Size.hairline)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .accessibilityHidden(true)
                }
                row(items[index], at: index)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.Size.clipboardFilterMenuWidth)
    }

    private func row(_ item: PopoverMenuItem, at index: Int) -> some View {
        Button {
            dismiss()
            item.action()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                icon(item.icon)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                Text(item.title)
                    .font(Theme.Typography.menuRow)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(hovered == index ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .settingsEnabled(item.isEnabled)
        .onHover { inside in
            if inside {
                hovered = index
            } else if hovered == index {
                hovered = nil
            }
        }
    }

    @ViewBuilder
    private func icon(_ icon: PopoverMenuIcon) -> some View {
        switch icon {
        case .symbol(let name):
            SymbolImage(name: name, size: Theme.Typography.menuSymbolSize)
                .foregroundStyle(Theme.Colors.menuSymbol)
        case .file(let path):
            DockFileIcon(path: path, size: Theme.Size.menuIcon)
        case .asset, .thumbnail, .blank:
            EmptyView()
        }
    }
}
