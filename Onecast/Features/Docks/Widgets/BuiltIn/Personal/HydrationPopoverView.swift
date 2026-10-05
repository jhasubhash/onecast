import OnecastPluginKit
import SwiftUI

/// The Hydration popover: today's summary, the drink button, Undo and the day-by-day history.
struct HydrationPopoverView: View {
    let model: HydrationModel
    @State private var showsOlder = false

    private static let refreshSeconds: TimeInterval = 20
    private static let recentDays = 3
    private static let ringSize: CGFloat = 64
    private static let ringStroke: CGFloat = 7
    private static let rowGlyph: CGFloat = 14
    private static let timeWidth: CGFloat = 64

    private let locale = Locale.autoupdatingCurrent
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshSeconds)) { timeline in
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                summary(now: timeline.date)
                DrinkButton(title: "I drank water", detail: drinkDetail, action: { model.drink() })
                if let change = model.change { undoBar(change) }
                if let failure = model.saveFailure {
                    Text("Couldn't save history: \(failure)")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.destructive)
                }
                history(now: timeline.date)
            }
            .padding(PersonalPopover.padding)
        }
        .frame(width: PersonalPopover.width)
    }

    private var drinkDetail: String? {
        model.settings.tracksAmounts
            ? HydrationFormat.milliliters(model.settings.drinkMilliliters, locale: locale) : nil
    }

    private func summary(now: Date) -> some View {
        let progress = model.progress(now: now)
        return HStack(spacing: Theme.Spacing.xl) {
            ZStack {
                PersonalProgressRing(
                    progress: progress.ringFraction, lineWidth: Self.ringStroke,
                    tint: progress.isReached ? Theme.Colors.success : .cyan)
                Text("\(progress.percent)%")
                    .font(Theme.Typography.bar)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Today")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(HydrationFormat.consumed(progress, locale: locale))
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(summaryDetail(progress, now: now))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryDetail(_ progress: HydrationProgress, now: Date) -> String {
        let goal = HydrationFormat.goalLine(progress, locale: locale)
        guard let due = model.dueAt else { return "\(goal) · reminders off" }
        let countdown = HydrationFormat.countdown(
            seconds: HydrationReminder.secondsUntil(due, now: now))
        return "\(goal) · next reminder in \(countdown)"
    }

    private func undoBar(_ change: HydrationChange) -> some View {
        HStack {
            Text(undoTitle(change))
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: Theme.Spacing.md)
            BarButton(action: { model.undo() }) {
                Text("Undo").font(Theme.Typography.bar).foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .padding(.leading, Theme.Spacing.lg)
        .padding(.trailing, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill))
    }

    private func undoTitle(_ change: HydrationChange) -> String {
        switch change {
        case .added(let entry): "Added \(HydrationFormat.phrase(entry, locale: locale))"
        case .removed(let entry): "Removed \(HydrationFormat.phrase(entry, locale: locale))"
        }
    }

    private func history(now: Date) -> some View {
        let collapsed = model.log.history(
            now: now, calendar: calendar, recentDays: Self.recentDays, showingOlder: false)
        let shown =
            showsOlder
            ? model.log.history(
                now: now, calendar: calendar, recentDays: Self.recentDays, showingOlder: true)
            : collapsed
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("History")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                if !model.settings.savesHistory {
                    Text("Not saved")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            if shown.days.isEmpty {
                Text("No drinks logged yet")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        ForEach(shown.days) { day in dayBlock(day, now: now) }
                    }
                }
                .frame(maxHeight: PersonalPopover.listMaxHeight)
                .overflowFade()
                .thinScrollbar()
            }
            if collapsed.hasOlder {
                BarButton(chrome: .rounded, action: { showsOlder.toggle() }) {
                    Text(showsOlder ? "Hide older drinks" : "Show older drinks")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.leading, -Theme.Spacing.md)
            }
        }
    }

    private func dayBlock(_ day: HydrationDay, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(
                    HydrationFormat.dayTitle(
                        day.start, now: now, calendar: calendar, locale: locale)
                )
                .font(Theme.Typography.rowTitle.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text(dayTotal(day))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(day.entries) { entry in row(entry) }
        }
    }

    private func dayTotal(_ day: HydrationDay) -> String {
        model.settings.tracksAmounts
            ? HydrationFormat.milliliters(day.milliliters, locale: locale)
            : HydrationFormat.drinks(day.count, locale: locale)
    }

    private func row(_ entry: HydrationEntry) -> some View {
        let time = HydrationFormat.time(entry.date, calendar: calendar, locale: locale)
        return HStack(spacing: Theme.Spacing.md) {
            Text(time)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: Self.timeWidth, alignment: .leading)
            Text(HydrationFormat.entry(entry, locale: locale))
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
            Button {
                model.remove(entry)
            } label: {
                SymbolImage(name: "xmark.circle.fill", size: Self.rowGlyph)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .tooltip("Remove")
            .accessibilityLabel("Remove drink at \(time)")
        }
    }
}

/// The primary action: a full-width pill that lifts under the pointer.
private struct DrinkButton: View {
    let title: String
    let detail: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                SymbolImage(name: "drop.fill", size: Theme.Typography.menuSymbolSize)
                Text(title).font(Theme.Typography.bar)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.menuButton)
            .background(
                Capsule().fill(hovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
