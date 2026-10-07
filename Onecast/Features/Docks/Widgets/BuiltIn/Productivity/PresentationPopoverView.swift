import OnecastPluginKit
import SwiftUI

/// The tile's detail page: state, the toggle, and the window settings a presenter changes mid-call.
struct PresentationPopoverView: View {
    let context: DockWidgetContext

    private var coordinator: PresentationCoordinator { AppCore.shared.presentationCoordinator }
    private var settings: AppSettings { AppCore.shared.settings }

    var body: some View {
        TimeLiveView(granularity: .second) { now in
            let reading = PresentationDockReading(coordinator, now: now)
            ProductivityPopover {
                ProductivityPopoverHeader(
                    title: "Presentation Mode", subtitle: subtitle(reading),
                    actionTitle: "Settings", actionSymbol: "gearshape", action: openSettings)
                if !settings.presentationEnabled {
                    ProductivityPopoverMessage(
                        symbol: PresentationDockWidget.symbol,
                        text: "Presentation Mode is off. Turn it on in Settings.")
                } else {
                    if reading.isPresenting { facts(reading) }
                    controls
                    actions(reading)
                }
            }
        }
    }

    private func subtitle(_ reading: PresentationDockReading) -> String {
        switch reading.phase {
        case .idle: "Off"
        case .starting: "Starting…"
        case .stopping: "Ending…"
        case .presenting: "Live for \(reading.elapsed ?? "")"
        }
    }

    private func facts(_ reading: PresentationDockReading) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            fact("App", reading.appName ?? "Switch to the app to share")
            fact("Display", reading.displayName ?? "")
            fact("Resolution", reading.resolution)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: Theme.Spacing.md)
            Text(value)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(Theme.Typography.rowTrailing)
    }

    @ViewBuilder
    private var controls: some View {
        SteadySegmentedPicker(
            title: "Window",
            options: PresentationWindowSize.allCases.map {
                SteadySegmentedPicker.Option(value: $0, title: $0.shortTitle)
            },
            selection: binding(\.presentationWindowSize))
        if settings.presentationWindowSize == .margin {
            SteadySegmentedPicker(
                title: "Margin",
                options: PresentationMargin.choices.map {
                    SteadySegmentedPicker.Option(value: $0, title: "\($0)%")
                },
                selection: binding(\.presentationMarginPercent))
        }
    }

    private func actions(_ reading: PresentationDockReading) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ProductivityPill(
                title: reading.toggleTitle, symbol: reading.toggleSymbol, isProminent: true
            ) {
                context.actions.closePopover()
                coordinator.toggle()
            }
            .disabled(reading.isBusy)
            if reading.isPresenting {
                ProductivityPill(
                    title: "Re-fit Window", symbol: "arrow.up.left.and.arrow.down.right",
                    action: coordinator.refit)
            }
        }
    }

    /// A change re-fits the presented window through `AppCore`'s settings sink, as Settings does.
    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func openSettings() {
        context.actions.closePopover()
        AppCore.shared.settingsCoordinator.showSettings(tab: .presentation)
    }
}
