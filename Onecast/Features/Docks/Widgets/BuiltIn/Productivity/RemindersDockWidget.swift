import AppKit
import OnecastPluginKit
import SwiftUI

/// The incomplete reminders of one list, or all of them: listed, counted or the next one.
@MainActor
final class RemindersDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Reminders", subtitle: "Your to-dos, completed with a tap", icon: "checklist",
        category: "Productivity", sizes: [.compact, .wide, .expanded])

    private let model = RemindersDockModel()

    func tile(context: DockWidgetContext) -> AnyView {
        model.attach(context.preferences)
        return AnyView(RemindersDockTile(context: context, model: model))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        model.attach(context.preferences)
        return AnyView(RemindersDockPopover(context: context, model: model))
    }

    func didRemove() {
        model.stop()
    }
}

/// What a tile or popover calls its subject: the chosen list, or just "Reminders".
private func remindersTitle(_ listName: String) -> String {
    let trimmed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Reminders" : trimmed
}

// MARK: - Tile

struct RemindersDockTile: View {
    let context: DockWidgetContext
    let model: RemindersDockModel
    @AppStorage private var modeName: String
    @AppStorage private var listName: String

    init(context: DockWidgetContext, model: RemindersDockModel) {
        self.context = context
        self.model = model
        let id = context.instanceID
        _modeName = AppStorage(
            wrappedValue: DockReminderPlan.Mode.list.rawValue,
            DockWidgetPreferences.key(instanceID: id, name: ProductivityPreferenceName.mode))
        _listName = AppStorage(
            wrappedValue: "",
            DockWidgetPreferences.key(instanceID: id, name: ProductivityPreferenceName.list))
    }

    var body: some View {
        ProductivityTile(context: context) { geometry in
            TimelineView(.everyMinute) { timeline in
                RemindersTileContent(
                    geometry: geometry, model: model, now: timeline.date,
                    mode: DockReminderPlan.Mode(preference: modeName),
                    title: remindersTitle(listName))
            }
        }
        .task { await model.keepFresh() }
        .onChange(of: listName) { model.refresh() }
    }
}

private struct RemindersTileContent: View {
    let geometry: ProductivityTileGeometry
    let model: RemindersDockModel
    let now: Date
    let mode: DockReminderPlan.Mode
    let title: String

    private let calendar = Calendar.current
    private let accent = Theme.Colors.warning

    var body: some View {
        if model.access != .granted {
            ProductivityAccessPrompt(
                geometry: geometry, color: accent, label: title, symbol: "checklist",
                title: model.access == .denied ? "Open Settings" : "Allow Reminders",
                action: model.requestAccess)
        } else if !model.isLoaded {
            ProductivityTileFace(geometry: geometry, color: accent, label: title) {
                ProductivityValueText(geometry: geometry, text: "…")
            }
        } else if let missing = model.missingList {
            ProductivityTileFace(
                geometry: geometry, color: accent, label: title, caption: "No list “\(missing)”"
            ) {
                glyph("questionmark.folder")
            }
        } else if model.reminders.isEmpty {
            ProductivityTileFace(
                geometry: geometry, color: Theme.Colors.success, label: title, caption: "All done"
            ) {
                glyph("checkmark.circle")
            }
        } else {
            switch mode {
            case .list: list
            case .next: next(model.reminders[0])
            case .count: count
            }
        }
    }

    private func glyph(_ name: String) -> some View {
        SymbolImage(name: name, size: geometry.pointSize(0.3))
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    // MARK: Modes

    private var list: some View {
        let room = geometry.contentSize.height - geometry.pointSize(0.15) * 1.3 - geometry.gap
        let capacity = geometry.lines(of: 0.17, in: room)
        return VStack(spacing: geometry.gap) {
            ProductivityTileHeader(geometry: geometry, color: accent, label: title)
            VStack(alignment: .leading, spacing: geometry.gap) {
                ForEach(model.reminders.prefix(capacity)) { reminder in
                    row(reminder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ reminder: DockReminder) -> some View {
        let isOverdue = DockReminderPlan.isOverdue(reminder, now: now, calendar: calendar)
        let showsDue = geometry.contentSize.width >= geometry.unit * 3
        return HStack(spacing: geometry.gap) {
            Circle()
                .strokeBorder(
                    isOverdue ? Theme.Colors.destructive : Theme.Colors.textTertiary, lineWidth: 1
                )
                .frame(width: geometry.dotSize, height: geometry.dotSize)
            Text(reminder.title)
                .font(geometry.font(0.17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            if showsDue, let due = DockReminderPlan.dueLabel(for: reminder, now: now, calendar: calendar) {
                Spacer(minLength: 0)
                Text(due)
                    .font(geometry.font(0.14))
                    .foregroundStyle(isOverdue ? Theme.Colors.destructive : Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(height: geometry.pointSize(0.17) * 1.2)
    }

    private func next(_ reminder: DockReminder) -> some View {
        let isOverdue = DockReminderPlan.isOverdue(reminder, now: now, calendar: calendar)
        return ProductivityTileFace(
            geometry: geometry, color: isOverdue ? Theme.Colors.destructive : accent,
            label: isOverdue ? "Overdue" : "Next",
            caption: DockReminderPlan.dueLabel(for: reminder, now: now, calendar: calendar),
            captionColor: isOverdue ? Theme.Colors.destructive : Theme.Colors.textSecondary
        ) {
            ProductivityValueText(
                geometry: geometry, text: reminder.title, ratio: 0.22,
                lines: min(3, geometry.lines(of: 0.22, in: geometry.contentSize.height * 0.5)))
        }
    }

    private var count: some View {
        let overdue = DockReminderPlan.overdueCount(model.reminders, now: now, calendar: calendar)
        return ProductivityTileFace(
            geometry: geometry, color: overdue > 0 ? Theme.Colors.destructive : accent, label: title,
            caption: overdue > 0 ? "\(overdue) overdue" : "to do",
            captionColor: overdue > 0 ? Theme.Colors.destructive : Theme.Colors.textSecondary
        ) {
            ProductivityValueText(geometry: geometry, text: "\(model.reminders.count)", ratio: 0.5)
        }
    }
}

// MARK: - Popover

struct RemindersDockPopover: View {
    let context: DockWidgetContext
    let model: RemindersDockModel
    @AppStorage private var listName: String

    init(context: DockWidgetContext, model: RemindersDockModel) {
        self.context = context
        self.model = model
        _listName = AppStorage(
            wrappedValue: "",
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.list))
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            RemindersPopoverContent(
                context: context, model: model, now: timeline.date, title: remindersTitle(listName),
                showsListNames: listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .task { model.refresh() }
    }
}

private struct RemindersPopoverContent: View {
    let context: DockWidgetContext
    let model: RemindersDockModel
    let now: Date
    let title: String
    let showsListNames: Bool
    @State private var draft = ""

    var body: some View {
        ProductivityPopover {
            ProductivityPopoverHeader(
                title: title, subtitle: subtitle, actionTitle: "Open", actionSymbol: "checklist",
                action: { context.actions.launchApp("com.apple.reminders") })
            if model.access != .granted {
                access
            } else {
                if let missing = model.missingList {
                    ProductivityPopoverMessage(
                        symbol: "questionmark.folder",
                        text: "There is no list named “\(missing)”. Change it in this widget's settings.")
                } else if model.reminders.isEmpty {
                    ProductivityPopoverMessage(symbol: "checkmark.circle", text: "Nothing left to do.")
                } else {
                    rows
                }
                if let completion = model.lastCompletion { undoBar(completion) }
                if let failure = model.failure {
                    Text(failure)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.missingList == nil {
                    ProductivityField(
                        prompt: "Add a reminder", text: $draft, symbol: "plus.circle", onSubmit: submit)
                }
            }
        }
        .onChange(of: draft) { model.dismissFailure() }
    }

    private var subtitle: String? {
        guard model.access == .granted, model.isLoaded else { return nil }
        let count = model.reminders.count
        let overdue = DockReminderPlan.overdueCount(model.reminders, now: now, calendar: .current)
        let base = count == 1 ? "1 reminder" : "\(count) reminders"
        return overdue > 0 ? "\(base) · \(overdue) overdue" : base
    }

    private var access: some View {
        let isDenied = model.access == .denied
        return ProductivityPopoverMessage(
            symbol: "checklist",
            text: isDenied
                ? "Reminders access is off. Turn Onecast on under Privacy & Security ▸ Reminders."
                : "Allow Onecast to read and complete your reminders from this dock."
        ) {
            ProductivityPill(
                title: isDenied ? "Open System Settings…" : "Allow Reminders", isProminent: true,
                action: model.requestAccess)
        }
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                ForEach(model.reminders) { reminder in
                    RemindersRow(
                        reminder: reminder, now: now, showsListName: showsListNames,
                        onComplete: { complete(reminder) })
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: DockProductivityMetrics.popoverListMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func undoBar(_ completion: RemindersDockModel.Completion) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("Completed “\(completion.title)”")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            ProductivityPill(title: "Undo", symbol: "arrow.uturn.backward", action: model.undoCompletion)
        }
    }

    private func submit() {
        if model.add(title: draft) { draft = "" }
    }

    private func complete(_ reminder: DockReminder) {
        withAnimation(.easeOut(duration: Theme.Duration.hover)) { model.complete(reminder) }
    }
}

private struct RemindersRow: View {
    let reminder: DockReminder
    let now: Date
    let showsListName: Bool
    let onComplete: () -> Void
    @State private var hovered = false
    @State private var circleHovered = false

    var body: some View {
        let isOverdue = DockReminderPlan.isOverdue(reminder, now: now, calendar: .current)
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Button(action: onComplete) {
                SymbolImage(
                    name: circleHovered ? "checkmark.circle.fill" : "circle",
                    size: DockProductivityMetrics.rowIcon
                )
                .foregroundStyle(circleHovered ? Color.accentColor : Theme.Colors.textSecondary)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { circleHovered = $0 }
            .accessibilityLabel("Complete \(reminder.title)")
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(reminder.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                detail(isOverdue: isOverdue)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                .fill(hovered ? Theme.Colors.menuHover : Color.clear)
        )
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private func detail(isOverdue: Bool) -> some View {
        let due = DockReminderPlan.dueLabel(for: reminder, now: now, calendar: .current)
        let list = showsListName && !reminder.listTitle.isEmpty ? reminder.listTitle : nil
        if due != nil || list != nil {
            HStack(spacing: Theme.Spacing.xs) {
                if let due {
                    Text(due)
                        .foregroundStyle(
                            isOverdue ? Theme.Colors.destructive : Theme.Colors.textSecondary)
                }
                if due != nil, list != nil {
                    Text("·").foregroundStyle(Theme.Colors.textTertiary)
                }
                if let list {
                    Text(list).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
            }
            .font(Theme.Typography.rowTrailing)
        }
    }
}
