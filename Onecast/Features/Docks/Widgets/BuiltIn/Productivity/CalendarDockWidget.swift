import AppKit
import OnecastPluginKit
import SwiftUI

/// Today's date, the meeting worth joining next and a day agenda, read from `CalendarStore`.
@MainActor
final class CalendarDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "Calendar", subtitle: "The date, your next event and a join button", icon: "calendar",
        category: "Productivity", sizes: [.compact, .wide, .expanded])

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(CalendarDockTile(context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(CalendarDockPopover(context: context))
    }
}

/// Granting Calendar from a dock goes through Settings' own consent path, never around it.
@MainActor
enum CalendarDockAccess {
    static var isAvailable: Bool {
        let core = AppCore.shared
        return core.settings.calendarEnabled && core.calendarStore.access == .granted
    }

    static var isDenied: Bool { AppCore.shared.calendarStore.access == .denied }

    static func allow() {
        let core = AppCore.shared
        core.calendarStore.refreshAccess()
        if core.calendarStore.access == .denied {
            Permissions.openCalendarSettings()
        } else {
            core.calendarCoordinator.setCalendarEnabled(true)
        }
    }

    /// With only a dock watching, nothing else ticks the store past midnight or a Settings grant.
    static func keepFresh() async {
        let core = AppCore.shared
        while !Task.isCancelled {
            if core.settings.calendarEnabled {
                if !isAvailable { core.calendarStore.refreshAccess() }
                core.calendarStore.reloadIfStale(now: Date())
            }
            try? await Task.sleep(for: isAvailable ? .seconds(60) : .seconds(3))
        }
    }
}

// MARK: - Tile

struct CalendarDockTile: View {
    let context: DockWidgetContext
    @AppStorage private var layoutName: String
    @AppStorage private var includeAllDay: Bool
    @AppStorage private var showsCallButton: Bool

    init(context: DockWidgetContext) {
        self.context = context
        let id = context.instanceID
        _layoutName = AppStorage(
            wrappedValue: DockCalendarPlan.Layout.date.rawValue,
            DockWidgetPreferences.key(instanceID: id, name: ProductivityPreferenceName.layout))
        _includeAllDay = AppStorage(
            wrappedValue: true,
            DockWidgetPreferences.key(instanceID: id, name: ProductivityPreferenceName.includeAllDay))
        _showsCallButton = AppStorage(
            wrappedValue: true,
            DockWidgetPreferences.key(instanceID: id, name: ProductivityPreferenceName.showCallButton))
    }

    var body: some View {
        ProductivityTile(context: context) { geometry in
            TimelineView(.everyMinute) { timeline in
                CalendarTileContent(
                    geometry: geometry, now: timeline.date,
                    layout: DockCalendarPlan.Layout(preference: layoutName),
                    includeAllDay: includeAllDay, showsCallButton: showsCallButton)
            }
        }
        .task { await CalendarDockAccess.keepFresh() }
    }
}

/// The tile's body, split out so its own reads of the store are what SwiftUI observes.
private struct CalendarTileContent: View {
    let geometry: ProductivityTileGeometry
    let now: Date
    let layout: DockCalendarPlan.Layout
    let includeAllDay: Bool
    let showsCallButton: Bool

    var body: some View {
        let core = AppCore.shared
        let isAvailable = CalendarDockAccess.isAvailable
        let agenda =
            isAvailable
            ? DockCalendarPlan.agenda(
                from: core.calendarStore.events, now: now, includeAllDay: includeAllDay)
            : []
        let source = CalendarTileSource(
            isAvailable: isAvailable, now: now,
            featured: DockCalendarPlan.featured(from: agenda, now: now, calendar: .current),
            today: DockCalendarPlan.today(agenda, now: now, calendar: .current),
            showsCallButton: showsCallButton)
        switch layout {
        case .date:
            CalendarDateBlock(geometry: geometry, now: now)
        case .nextEvent:
            CalendarEventPanel(geometry: geometry, source: source, size: geometry.contentSize)
        case .dateAndNextEvent:
            CalendarCompositeTile(geometry: geometry, now: now, source: source, showsAgenda: false)
        case .dateAndAgenda:
            CalendarCompositeTile(geometry: geometry, now: now, source: source, showsAgenda: true)
        }
    }
}

// MARK: - Popover

struct CalendarDockPopover: View {
    let context: DockWidgetContext
    @AppStorage private var includeAllDay: Bool

    init(context: DockWidgetContext) {
        self.context = context
        _includeAllDay = AppStorage(
            wrappedValue: true,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: ProductivityPreferenceName.includeAllDay))
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            CalendarPopoverContent(context: context, now: timeline.date, includeAllDay: includeAllDay)
        }
    }
}

private struct CalendarPopoverContent: View {
    let context: DockWidgetContext
    let now: Date
    let includeAllDay: Bool

    var body: some View {
        let core = AppCore.shared
        let isAvailable = CalendarDockAccess.isAvailable
        let groups = MeetingDayGroup.grouping(
            DockCalendarPlan.agenda(
                from: isAvailable ? core.calendarStore.events : [], now: now,
                includeAllDay: includeAllDay),
            now: now, calendar: .current)
        ProductivityPopover {
            ProductivityPopoverHeader(
                title: "Calendar",
                subtitle: now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                actionTitle: "Open", actionSymbol: "calendar",
                action: { context.actions.launchApp("com.apple.iCal") })
            if !isAvailable {
                access
            } else if groups.isEmpty {
                ProductivityPopoverMessage(
                    symbol: "calendar.badge.checkmark",
                    text: "Nothing scheduled \(core.settings.calendarSpan.orPhrase).")
            } else {
                agenda(groups)
            }
        }
    }

    private var access: some View {
        let isDenied = CalendarDockAccess.isDenied
        return ProductivityPopoverMessage(
            symbol: "calendar.badge.exclamationmark",
            text: isDenied
                ? "Calendar access is off. Turn Onecast on under Privacy & Security ▸ Calendars."
                : "Allow Onecast to read your calendar to see events and join meetings here."
        ) {
            ProductivityPill(
                title: isDenied ? "Open System Settings…" : "Allow Calendar", isProminent: true
            ) {
                context.actions.closePopover()
                CalendarDockAccess.allow()
            }
        }
    }

    private func agenda(_ groups: [MeetingDayGroup]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(groups) { group in
                    Text(group.day.title(calendar: .current))
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                    ForEach(group.meetings) { event in
                        CalendarAgendaRow(context: context, event: event, now: now)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: DockProductivityMetrics.popoverListMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CalendarAgendaRow: View {
    let context: DockWidgetContext
    let event: MeetingEvent
    let now: Date
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                context.actions.closePopover()
                AppCore.shared.calendarCoordinator.openInCalendar(event)
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Capsule()
                        .fill(event.calendarColor?.color ?? Theme.Colors.textTertiary)
                        .frame(
                            width: DockProductivityMetrics.calendarBarWidth,
                            height: DockProductivityMetrics.calendarBarHeight)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(event.title)
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text(timing)
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(
                                event.isInProgress(now: now)
                                    ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
                            )
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let link = event.link {
                joinPill(link)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                .fill(hovered ? Theme.Colors.menuHover : Color.clear)
        )
        .onHover { hovered = $0 }
    }

    private var timing: String {
        if event.isAllDay { return "All day" }
        return MeetingTimeFormat.range(of: event)
    }

    private func joinPill(_ link: MeetingLink) -> some View {
        let isDue =
            event.isInProgress(now: now)
            || event.start.timeIntervalSince(now) <= DockCalendarPlan.imminentWindow
        return ProductivityPill(title: "Join", symbol: link.provider.sfSymbol, isProminent: isDue) {
            context.actions.closePopover()
            AppCore.shared.calendarCoordinator.join(event)
        }
    }
}
