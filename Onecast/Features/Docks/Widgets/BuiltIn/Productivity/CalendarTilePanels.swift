import OnecastPluginKit
import SwiftUI

/// What a Calendar tile's panels draw, resolved once per render so they agree on "now".
struct CalendarTileSource {
    let isAvailable: Bool
    let now: Date
    let featured: MeetingEvent?
    let today: [MeetingEvent]
    let showsCallButton: Bool
}

private extension MeetingEvent {
    var tint: Color { calendarColor?.color ?? Theme.Colors.textTertiary }
}

/// The access prompt every Calendar panel shows while the feature or its permission is off.
struct CalendarAllowPrompt: View {
    let geometry: ProductivityTileGeometry

    var body: some View {
        ProductivityAccessPrompt(
            geometry: geometry, color: Theme.Colors.destructive, label: "Calendar",
            symbol: "calendar.badge.plus", title: "Allow Calendar", action: CalendarDockAccess.allow)
    }
}

/// The weekday, the day of the month and, beneath it, the month or a line of the caller's own.
struct CalendarDateBlock: View {
    let geometry: ProductivityTileGeometry
    let now: Date
    var caption: String?
    var isAbbreviated = false

    var body: some View {
        let isShort = geometry.isCompact || isAbbreviated
        let month: Date.FormatStyle.Symbol.Month = isShort ? .abbreviated : .wide
        let weekday: Date.FormatStyle.Symbol.Weekday = isShort ? .abbreviated : .wide
        ProductivityTileFace(
            geometry: geometry, color: Theme.Colors.destructive,
            label: now.formatted(.dateTime.weekday(weekday)),
            caption: caption ?? now.formatted(.dateTime.month(month))
        ) {
            ProductivityValueText(
                geometry: geometry, text: now.formatted(.dateTime.day()),
                ratio: geometry.isCompact ? 0.42 : 0.5)
        }
    }
}

/// One featured event, or the reason there is none.
struct CalendarEventPanel: View {
    let geometry: ProductivityTileGeometry
    let source: CalendarTileSource
    let size: CGSize

    var body: some View {
        if !source.isAvailable {
            CalendarAllowPrompt(geometry: geometry)
        } else if let event = source.featured {
            let link = source.showsCallButton ? event.link : nil
            ProductivityTileFace(
                geometry: geometry, color: event.tint, label: event.calendarName,
                caption: event.title,
                captionLines: min(3, geometry.lines(of: 0.14, in: size.height * 0.4))
            ) {
                ProductivityValueText(
                    geometry: geometry,
                    text: DockCalendarPlan.startLabel(
                        for: event, now: source.now, calendar: .current),
                    ratio: 0.26)
            } footer: {
                if let link {
                    CalendarJoinButton(geometry: geometry, event: event, link: link, now: source.now)
                }
            }
        } else {
            ProductivityTileFace(
                geometry: geometry, color: Theme.Colors.textTertiary, label: "Calendar"
            ) {
                ProductivityValueText(geometry: geometry, text: "No events", ratio: 0.2)
            }
        }
    }
}

private struct CalendarJoinButton: View {
    let geometry: ProductivityTileGeometry
    let event: MeetingEvent
    let link: MeetingLink
    let now: Date

    private var isDue: Bool {
        event.isInProgress(now: now)
            || event.start.timeIntervalSince(now) <= DockCalendarPlan.imminentWindow
    }

    var body: some View {
        Button {
            AppCore.shared.calendarCoordinator.join(event)
        } label: {
            SymbolImage(name: link.provider.sfSymbol, size: geometry.pointSize(0.15))
                .foregroundStyle(isDue ? Color.white : Theme.Colors.textPrimary)
                .frame(width: geometry.unit * 0.3, height: geometry.unit * 0.3)
                .background(Circle().fill(isDue ? Color.accentColor : Theme.Colors.controlHover))
                .contentShape(Circle())
        }
        .buttonStyle(ProductivityPressStyle())
        .accessibilityLabel("Join \(event.title)")
    }
}

/// Today's remaining events, as rows where there is width and as stacked pairs where there is not.
struct CalendarAgendaPanel: View {
    let geometry: ProductivityTileGeometry
    let source: CalendarTileSource
    let size: CGSize

    var body: some View {
        if !source.isAvailable {
            CalendarAllowPrompt(geometry: geometry)
        } else {
            VStack(spacing: geometry.gap) {
                ProductivityTileHeader(
                    geometry: geometry, color: Color.accentColor, label: "Today")
                if source.today.isEmpty {
                    Spacer(minLength: 0)
                    ProductivityValueText(geometry: geometry, text: "No events", ratio: 0.2)
                    Spacer(minLength: 0)
                } else {
                    rows
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rows: some View {
        let isNarrow = geometry.isNarrow(size)
        let rowHeight =
            isNarrow
            ? geometry.pointSize(0.13) * 1.25 + geometry.pointSize(0.16) * 1.25
            : geometry.pointSize(0.17) * 1.2
        let room = size.height - geometry.pointSize(0.15) * 1.3 - geometry.gap
        let capacity = max(1, Int((room + geometry.gap) / (rowHeight + geometry.gap)))
        return VStack(alignment: .leading, spacing: geometry.gap) {
            ForEach(source.today.prefix(capacity)) { event in
                CalendarAgendaTileRow(
                    geometry: geometry, event: event, isNarrow: isNarrow, height: rowHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CalendarAgendaTileRow: View {
    let geometry: ProductivityTileGeometry
    let event: MeetingEvent
    let isNarrow: Bool
    let height: CGFloat

    private var time: String {
        event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        HStack(spacing: geometry.gap) {
            Circle()
                .fill(event.tint)
                .frame(width: geometry.dotSize, height: geometry.dotSize)
            if isNarrow {
                VStack(alignment: .leading, spacing: 0) {
                    Text(time)
                        .font(geometry.font(0.13).monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Text(event.title)
                        .font(geometry.font(0.16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
            } else {
                Text(time)
                    .font(geometry.font(0.14).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Text(event.title)
                    .font(geometry.font(0.17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height)
    }
}

/// The date beside (or, on a side dock, above) an event or agenda panel.
struct CalendarCompositeTile: View {
    let geometry: ProductivityTileGeometry
    let now: Date
    let source: CalendarTileSource
    let showsAgenda: Bool

    var body: some View {
        if geometry.isCompact {
            compact
        } else {
            let dateSlot = geometry.unit * 0.8
            let spacing = geometry.gap * 2
            let content = geometry.contentSize
            let panel =
                geometry.isVertical
                ? CGSize(width: content.width, height: max(0, content.height - dateSlot - spacing))
                : CGSize(width: max(0, content.width - dateSlot - spacing), height: content.height)
            let layout =
                geometry.isVertical
                ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
            layout {
                CalendarDateBlock(geometry: geometry, now: now, isAbbreviated: !geometry.isVertical)
                    .frame(
                        width: geometry.isVertical ? nil : dateSlot,
                        height: geometry.isVertical ? dateSlot : nil)
                if showsAgenda {
                    CalendarAgendaPanel(geometry: geometry, source: source, size: panel)
                } else {
                    CalendarEventPanel(geometry: geometry, source: source, size: panel)
                }
            }
        }
    }

    /// A compact tile has room for the date and one line about what comes next.
    @ViewBuilder
    private var compact: some View {
        if source.isAvailable {
            CalendarDateBlock(geometry: geometry, now: now, caption: summary)
        } else {
            CalendarAllowPrompt(geometry: geometry)
        }
    }

    private var summary: String {
        if showsAgenda { return source.today.isEmpty ? "No events" : "\(source.today.count) today" }
        return source.featured?.title ?? "No events"
    }
}
