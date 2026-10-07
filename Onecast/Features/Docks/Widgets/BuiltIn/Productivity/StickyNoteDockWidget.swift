import AppKit
import OnecastPluginKit
import SwiftUI

/// A note kept on the dock, autosaved in this instance's own preferences.
@MainActor
final class StickyNoteDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Sticky Note", subtitle: "A note to jot on, always in view", icon: "note.text",
        category: "Productivity", sizes: [.compact, .wide, .expanded])

    private let model = StickyNoteModel()

    func tile(context: DockWidgetContext) -> AnyView {
        model.attach(context.preferences)
        return AnyView(StickyNoteTile(context: context, model: model))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        model.attach(context.preferences)
        return AnyView(StickyNotePopover(context: context, model: model))
    }
}

@MainActor
@Observable
final class StickyNoteModel {
    /// Written through to the instance's preferences on every edit, so a quit never loses a word.
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            preferences?.set(text, for: ProductivityPreferenceName.text)
        }
    }

    @ObservationIgnored private var preferences: DockWidgetPreferences?

    /// Loads the saved text before keeping the preferences, so the load itself writes nothing.
    func attach(_ preferences: DockWidgetPreferences) {
        guard self.preferences == nil else { return }
        text = preferences.string(ProductivityPreferenceName.text) ?? ""
        self.preferences = preferences
    }
}

// MARK: - Tile

struct StickyNoteTile: View {
    let context: DockWidgetContext
    let model: StickyNoteModel
    @AppStorage private var colorName: String
    @AppStorage private var textureName: String
    @AppStorage private var inkName: String
    @Environment(\.colorScheme) private var scheme

    init(context: DockWidgetContext, model: StickyNoteModel) {
        self.context = context
        self.model = model
        _colorName = AppStorage(
            wrappedValue: StickyPaperColor.yellow.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.color))
        _textureName = AppStorage(
            wrappedValue: StickyPaperTexture.plain.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.texture))
        _inkName = AppStorage(
            wrappedValue: StickyInkColor.automatic.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.ink))
    }

    var body: some View {
        let paper = (StickyPaperColor(rawValue: colorName) ?? .yellow)
            .paper(
                isDarkAppearance: scheme == .dark,
                ink: StickyInkColor(rawValue: inkName) ?? .automatic)
        let texture = StickyPaperTexture(rawValue: textureName) ?? .plain
        ProductivityTile(context: context) { geometry in
            StickyNoteTileContent(geometry: geometry, model: model, paper: paper, texture: texture)
        }
    }
}

/// The note's text in the slot, split out so its own read of the model is what SwiftUI observes.
private struct StickyNoteTileContent: View {
    let geometry: ProductivityTileGeometry
    let model: StickyNoteModel
    let paper: StickyNotePaper
    let texture: StickyPaperTexture

    var body: some View {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = text.isEmpty
        let fontSize = geometry.pointSize(0.2)
        Text(isEmpty ? "Write a note" : text)
            .font(.system(size: fontSize))
            .foregroundStyle(isEmpty ? paper.faintInk : paper.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(geometry.lines(of: 0.2, in: geometry.contentSize.height))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Drawn out past the tile's inset, so the paper runs to the card's edge; the texture's
            // origin is then the card's corner, and the text starts one inset in from it.
            .background {
                ZStack {
                    paper.fill
                    StickyPaperTextureView(
                        texture: texture, ink: paper.ink,
                        lineHeight: StickyPaperTextureView.lineHeight(forFontSize: fontSize),
                        top: geometry.inset, leading: geometry.inset)
                }
                .padding(-geometry.inset)
            }
    }
}

// MARK: - Popover

struct StickyNotePopover: View {
    private static let textSize: CGFloat = 24
    private static let height: CGFloat = 330
    private static let customizeHeight: CGFloat = 500
    private static let swatchSize: CGFloat = 28
    private static let inkSwatchSize: CGFloat = 24
    private static let noteSpace = "stickyNote"

    let context: DockWidgetContext
    @Bindable var model: StickyNoteModel
    @AppStorage private var colorName: String
    @AppStorage private var textureName: String
    @AppStorage private var inkName: String
    @FocusState private var isEditing: Bool
    @State private var isCustomizing = false
    /// Where the editor's text starts, so a lined paper's rules fall under the lines of text.
    @State private var editorTop: CGFloat = 0
    @Environment(\.metrics) private var metrics
    @Environment(\.colorScheme) private var scheme

    init(context: DockWidgetContext, model: StickyNoteModel) {
        self.context = context
        self.model = model
        _colorName = AppStorage(
            wrappedValue: StickyPaperColor.yellow.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.color))
        _textureName = AppStorage(
            wrappedValue: StickyPaperTexture.plain.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.texture))
        _inkName = AppStorage(
            wrappedValue: StickyInkColor.automatic.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.ink))
    }

    var body: some View {
        let color = StickyPaperColor(rawValue: colorName) ?? .yellow
        let texture = StickyPaperTexture(rawValue: textureName) ?? .plain
        let ink = StickyInkColor(rawValue: inkName) ?? .automatic
        let paper = color.paper(isDarkAppearance: scheme == .dark, ink: ink)
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if isCustomizing {
                customize(color: color, texture: texture, ink: ink, paper: paper)
            } else {
                note(paper)
            }
        }
        .coordinateSpace(name: Self.noteSpace)
        .padding(Theme.Spacing.xl)
        .frame(
            width: DockProductivityMetrics.popoverWidth,
            height: isCustomizing ? Self.customizeHeight : Self.height)
        // The dock pads, tints and rounds every widget popover; the paper is drawn out over that
        // padding so the whole panel is the note, and the dock's own clip gives it its corners.
        // The texture's origin is that outer corner, hence both paddings in where the text starts.
        .background {
            let inset = Theme.Spacing.xl + metrics.spacing.xl
            ZStack {
                paper.fill
                StickyPaperTextureView(
                    texture: texture, ink: paper.ink,
                    lineHeight: StickyPaperTextureView.lineHeight(forFontSize: Self.textSize),
                    top: editorTop + inset, leading: inset)
            }
            .padding(-metrics.spacing.xl)
        }
        // The text controls follow the paper, not the system: light ink needs a dark editor.
        .environment(\.colorScheme, paper.isDark ? .dark : .light)
        .onAppear { isEditing = true }
    }

    // MARK: The note

    @ViewBuilder
    private func note(_ paper: StickyNotePaper) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("Sticky Note")
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(paper.faintInk)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.md)
            headerButton("slider.horizontal.3", label: "Customize note", paper: paper) {
                isCustomizing = true
            }
            headerButton("xmark", label: "Close note", paper: paper, action: context.actions.closePopover)
        }
        TextEditor(text: $model.text)
            .font(.system(size: Self.textSize))
            .foregroundStyle(paper.ink)
            .tint(paper.ink)
            .scrollContentBackground(.hidden)
            .focused($isEditing)
            // The editor's own inset, taken back so its text lines up with the title.
            .padding(.horizontal, -5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear { editorTop = proxy.frame(in: .named(Self.noteSpace)).minY }
                }
            }
    }

    // MARK: Customize

    /// The hues on offer; the rest are still in Settings.
    private static let hues: [StickyPaperColor] = [.yellow, .orange, .red, .purple, .blue, .green]
    private static let neutrals: [StickyPaperColor] = [.silver, .graphite, .charcoal, .black]

    @ViewBuilder
    private func customize(
        color: StickyPaperColor, texture: StickyPaperTexture, ink: StickyInkColor,
        paper: StickyNotePaper
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                isCustomizing = false
                isEditing = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: "chevron.left", size: Theme.Typography.menuSymbolSize)
                    Text("Back").font(Theme.Typography.panelTitle)
                }
                .foregroundStyle(paper.faintInk)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(paper.ink.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Customize")
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(paper.faintInk)
            Spacer(minLength: Theme.Spacing.md)
            headerButton("xmark", label: "Close note", paper: paper, action: context.actions.closePopover)
        }
        sectionTitle("Paper color", paper)
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(Self.hues, id: \.self) { swatch($0, selected: color, paper: paper) }
        }
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(Self.neutrals, id: \.self) { swatch($0, selected: color, paper: paper) }
        }
        sectionTitle("Paper texture", paper)
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4),
            spacing: Theme.Spacing.md
        ) {
            ForEach(StickyPaperTexture.allCases, id: \.self) { choice in
                texturePreview(choice, selected: texture, paper: paper)
            }
        }
        sectionTitle("Text color", paper)
        HStack(spacing: Theme.Spacing.md) {
            ForEach(StickyInkColor.allCases, id: \.self) {
                inkSwatch($0, selected: ink, paper: paper)
            }
        }
        Spacer(minLength: 0)
    }

    private func sectionTitle(_ title: String, _ paper: StickyNotePaper) -> some View {
        Text(title)
            .font(Theme.Typography.panelTitle)
            .foregroundStyle(paper.faintInk)
    }

    /// A hue shows its vivid dot; a neutral shows the grey paper itself, ringed so it can be seen
    /// against a note of the same grey.
    private func swatch(
        _ choice: StickyPaperColor, selected: StickyPaperColor, paper: StickyNotePaper
    ) -> some View {
        let worn = choice.paper(isDarkAppearance: scheme == .dark)
        let isSelected = choice == selected
        return Button {
            context.preferences.set(choice.rawValue, for: ProductivityPreferenceName.color)
        } label: {
            Circle()
                .fill(choice.vividSwatch ?? worn.fill)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .overlay {
                    if choice.isNeutral {
                        Circle().strokeBorder(paper.ink.opacity(0.3), lineWidth: 1)
                    }
                }
                .overlay {
                    if isSelected {
                        SymbolImage(name: "checkmark", size: Self.swatchSize * 0.45)
                            .foregroundStyle(choice.isNeutral ? worn.ink : Color.white)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Automatic is an "A" on the paper's own ink; a colour shows itself as it will read on this paper.
    private func inkSwatch(
        _ choice: StickyInkColor, selected: StickyInkColor, paper: StickyNotePaper
    ) -> some View {
        let isSelected = choice == selected
        let shown = choice.color(onDarkPaper: paper.isDark)
        return Button {
            context.preferences.set(choice.rawValue, for: ProductivityPreferenceName.ink)
        } label: {
            ZStack {
                if let shown {
                    Circle().fill(shown)
                } else {
                    Circle().fill(paper.ink.opacity(0.12))
                    SymbolImage(name: "a.circle", size: Self.inkSwatchSize * 0.7)
                        .foregroundStyle(paper.ink)
                }
                Circle().strokeBorder(paper.ink.opacity(0.3), lineWidth: 1)
                if isSelected {
                    Circle().strokeBorder(paper.ink, lineWidth: 2).padding(-3)
                }
            }
            .frame(width: Self.inkSwatchSize, height: Self.inkSwatchSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The texture drawn small on the current paper, with its name under it.
    private func texturePreview(
        _ choice: StickyPaperTexture, selected: StickyPaperTexture, paper: StickyNotePaper
    ) -> some View {
        let isSelected = choice == selected
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return Button {
            context.preferences.set(choice.rawValue, for: ProductivityPreferenceName.texture)
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                shape
                    .fill(paper.fill)
                    .overlay {
                        StickyPaperTextureView(
                            texture: choice, ink: paper.ink, lineHeight: 9, top: 2, leading: 10)
                    }
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(
                            paper.ink.opacity(isSelected ? 0.85 : 0.22),
                            lineWidth: isSelected ? 2 : 1)
                    }
                    .frame(height: 36)
                Text(choice.title)
                    .font(.system(size: 11))
                    .foregroundStyle(paper.faintInk)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func headerButton(
        _ symbol: String, label: String, paper: StickyNotePaper, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: Theme.Typography.menuSymbolSize + 2)
                .foregroundStyle(paper.faintInk)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
