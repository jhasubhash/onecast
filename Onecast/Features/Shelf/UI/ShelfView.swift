import SwiftUI

/// The shelf: a row per drop that drags out as one, opening to pick single items out of it.
struct ShelfView: View {
    let coordinator: ShelfCoordinator
    let tooltips: TooltipPresenter?

    var body: some View {
        VStack(spacing: 0) {
            header
            if coordinator.groups.isEmpty {
                dropZone
            } else if let group = coordinator.openGroup {
                list { ForEach(group.items) { ShelfRow(item: $0, coordinator: coordinator) } }
            } else {
                list { ForEach(coordinator.groups) { ShelfGroupRow(group: $0, coordinator: coordinator) } }
            }
        }
        .frame(width: Theme.Size.shelfWidth, height: coordinator.panelHeight, alignment: .top)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: Theme.Size.formFieldFocusStroke)
                .opacity(coordinator.isTargeted ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .animation(.easeOut(duration: Theme.Duration.hover), value: coordinator.isTargeted)
        .environment(\.tooltipPresenter, tooltips)
    }

    @ViewBuilder
    private var header: some View {
        if let group = coordinator.openGroup { groupHeader(group) } else { shelfHeader }
    }

    private func groupHeader(_ group: ShelfGroup) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ShelfIconButton(symbol: "chevron.left", help: "All Groups", action: coordinator.closeGroup)
            VStack(alignment: .leading, spacing: 0) {
                Text(group.title)
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Drag one item out on its own")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
                .frame(maxHeight: .infinity)
            ShelfIconButton(symbol: "xmark", help: "Close Shelf", action: coordinator.close)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.shelfHeader)
        .background { WindowDragHandle(onBegan: {}, onEnded: {}) }
    }

    private var shelfHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            ShelfStackIcon(items: coordinator.items)
                .overlay {
                    ShelfDragSource(
                        items: { coordinator.items }, onEnded: coordinator.dragEnded(_:operation:))
                }
                .tooltip(coordinator.items.isEmpty ? nil : "Drag to move everything")
            VStack(alignment: .leading, spacing: 0) {
                Text(ShelfStack.summary(of: coordinator.items))
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !coordinator.items.isEmpty {
                    Text(coordinator.groups.count == 1 ? "1 group" : "\(coordinator.groups.count) groups")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
                .frame(maxHeight: .infinity)
            if !coordinator.items.isEmpty { actions }
            ShelfIconButton(symbol: "xmark", help: "Close Shelf", action: coordinator.close)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.shelfHeader)
        .background { WindowDragHandle(onBegan: {}, onEnded: {}) }
    }

    private var actions: some View {
        Menu {
            Button("Copy All", systemImage: "doc.on.doc") { coordinator.copy(coordinator.items) }
            Button("Show in Finder", systemImage: "folder") { coordinator.reveal(coordinator.items) }
                .disabled(!coordinator.items.contains { $0.fileURL != nil })
            Button("Share…", systemImage: "square.and.arrow.up") { coordinator.share(coordinator.items) }
            Divider()
            Button("Clear Shelf", systemImage: "trash", action: coordinator.clear)
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.Typography.menuIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.barButtonHeight, height: Theme.Size.barButtonHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var dropZone: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: Theme.Size.noteEmptyGlyph, weight: .light))
            Text("Drop files, images, links or text")
                .font(.callout)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    Theme.Colors.border,
                    style: StrokeStyle(
                        lineWidth: Theme.Size.dropGuideWidth,
                        dash: [Theme.Size.dropGuideDash, Theme.Size.dropGuideDash / 2]))
        }
        .padding([.horizontal, .bottom], Theme.Spacing.xl)
    }

    private func list(@ViewBuilder rows: () -> some View) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) { rows() }
            .padding(.vertical, Theme.Spacing.md)
            .padding(.horizontal, Theme.Spacing.md)
        }
        .scrollIndicators(.automatic)
    }
}

private struct ShelfRow: View {
    let item: ShelfItem
    let coordinator: ShelfCoordinator

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ShelfThumbnail(item: item)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay {
                ShelfDragSource(
                    items: { coordinator.dragItems(from: item.id) },
                    onPress: { coordinator.press(item.id, $0) }, onClick: { _ in coordinator.click(item.id) },
                    onOpen: { coordinator.open(item) }, menu: { coordinator.menu(forRow: item.id) },
                    onEnded: coordinator.dragEnded(_:operation:))
            }
            ShelfIconButton(symbol: "minus.circle", help: "Remove from Shelf") {
                coordinator.remove([item])
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(height: Theme.Size.shelfRow)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(coordinator.isSelected(item.id) ? Theme.Colors.shelfSelection : .clear))
    }
}

/// One drop: its items fanned into a stack that drags out together; opening it lists them singly.
private struct ShelfGroupRow: View {
    let group: ShelfGroup
    let coordinator: ShelfCoordinator

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ShelfStackIcon(items: group.items)
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(group.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay {
                ShelfDragSource(
                    items: { coordinator.dragItems(from: group.id) },
                    onPress: { coordinator.press(group.id, $0) }, onClick: { _ in coordinator.click(group.id) },
                    onOpen: { coordinator.openGroup(group) }, menu: { coordinator.menu(forRow: group.id) },
                    onEnded: coordinator.dragEnded(_:operation:))
            }
            if group.items.count > 1 {
                ShelfIconButton(symbol: "chevron.right", help: "Show Items") {
                    coordinator.openGroup(group)
                }
            }
            ShelfIconButton(symbol: "minus.circle", help: "Remove from Shelf") {
                coordinator.remove(group.items)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(height: Theme.Size.shelfRow)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(coordinator.isSelected(group.id) ? Theme.Colors.shelfSelection : .clear))
    }
}

private struct ShelfThumbnail: View {
    let item: ShelfItem
    @State private var preview: NSImage?

    var body: some View {
        Image(nsImage: preview ?? ShelfIcon.image(for: item))
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Size.shelfThumbnail, height: Theme.Size.shelfThumbnail)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            .task(id: item.id) {
                guard let url = item.fileURL else { return }
                preview = await FilePreviewThumbnail.loadAsync(
                    url, maxPixel: Theme.Size.shelfThumbnail * 2)
            }
    }
}

/// The header's stack: up to three item icons fanned out, or an empty tray.
private struct ShelfStackIcon: View {
    let items: [ShelfItem]

    private static let fan: CGFloat = 5

    var body: some View {
        ZStack {
            if items.isEmpty {
                Image(systemName: "tray")
                    .font(.system(size: Theme.Size.menuIcon, weight: .regular))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                ShelfThumbnail(item: item)
                    .rotationEffect(.degrees(Double(index) * Self.fan))
                    .offset(x: CGFloat(index) * 2, y: CGFloat(-index) * 2)
            }
        }
        .frame(
            width: Theme.Size.shelfThumbnail + Theme.Spacing.md,
            height: Theme.Size.shelfThumbnail + Theme.Spacing.md)
        .overlay(alignment: .bottomTrailing) {
            if items.count > 1 {
                Text("\(items.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(minWidth: Theme.Size.compactKeyCap, minHeight: Theme.Size.compactKeyCap)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
    }
}

private struct ShelfIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.menuIcon)
                .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: Theme.Size.barButtonHeight, height: Theme.Size.barButtonHeight)
                .background(Circle().fill(hovered ? Theme.Colors.menuHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .tooltip(help)
    }
}
