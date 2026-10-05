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

extension DockColor {
    var stickyTitle: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The accent dot of a note's tile and the wash its popover editor sits on.
    var stickyTint: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }
}

// MARK: - Tile

struct StickyNoteTile: View {
    let context: DockWidgetContext
    let model: StickyNoteModel
    @AppStorage private var colorName: String

    init(context: DockWidgetContext, model: StickyNoteModel) {
        self.context = context
        self.model = model
        _colorName = AppStorage(
            wrappedValue: DockColor.yellow.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.color))
    }

    var body: some View {
        ProductivityTile(context: context) { geometry in
            StickyNoteTileContent(
                geometry: geometry, model: model,
                tint: (DockColor(rawValue: colorName) ?? .yellow).stickyTint)
        }
    }
}

/// The note's text in the slot, split out so its own read of the model is what SwiftUI observes.
private struct StickyNoteTileContent: View {
    let geometry: ProductivityTileGeometry
    let model: StickyNoteModel
    let tint: Color

    var body: some View {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            ProductivityTileFace(
                geometry: geometry, color: tint, label: "Note", caption: "Write a note"
            ) {
                SymbolImage(name: "square.and.pencil", size: geometry.pointSize(0.3))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } else {
            let room = geometry.contentSize.height - geometry.pointSize(0.15) * 1.3 - geometry.gap
            VStack(spacing: geometry.gap) {
                ProductivityTileHeader(geometry: geometry, color: tint, label: "Note")
                Text(text)
                    .font(geometry.font(0.17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(geometry.lines(of: 0.17, in: room))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Popover

struct StickyNotePopover: View {
    private static let editorHeight: CGFloat = 220

    let context: DockWidgetContext
    @Bindable var model: StickyNoteModel
    @AppStorage private var colorName: String
    @FocusState private var isEditing: Bool

    init(context: DockWidgetContext, model: StickyNoteModel) {
        self.context = context
        self.model = model
        _colorName = AppStorage(
            wrappedValue: DockColor.yellow.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.color))
    }

    var body: some View {
        let tint = (DockColor(rawValue: colorName) ?? .yellow).stickyTint
        ProductivityPopover {
            ProductivityPopoverHeader(title: "Sticky Note", subtitle: "Saved as you type")
            TextEditor(text: $model.text)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isEditing)
                .padding(Theme.Spacing.md)
                .frame(height: Self.editorHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(tint.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(tint.opacity(0.5), lineWidth: 1)
                )
        }
        .onAppear { isEditing = true }
    }
}
