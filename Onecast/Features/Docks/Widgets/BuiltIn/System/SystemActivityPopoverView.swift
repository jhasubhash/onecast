import OnecastPluginKit
import SwiftUI

struct SystemActivityPopoverView: View {
    let context: DockWidgetContext
    @AppStorage private var metricName: String
    @State private var tab: SystemActivityMetric?

    init(context: DockWidgetContext) {
        self.context = context
        _metricName = AppStorage(
            wrappedValue: SystemActivityMetric.cpu.rawValue,
            DockWidgetPreferences.key(
                instanceID: context.instanceID, name: SystemActivityWidget.PreferenceName.metric))
    }

    private var selection: Binding<SystemActivityMetric> {
        Binding(
            get: { tab ?? SystemActivityMetric(rawValue: metricName) ?? .cpu },
            set: { tab = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SteadySegmentedPicker(
                title: "Activity",
                options: SystemActivityMetric.allCases.map {
                    SteadySegmentedPicker.Option(value: $0, title: $0.title)
                }, selection: selection)
            Group {
                switch selection.wrappedValue {
                case .cpu: SystemCPUTabView()
                case .memory: SystemMemoryTabView()
                case .storage: SystemStorageTabView()
                }
            }
            .frame(height: SystemPopover.bodyHeight, alignment: .top)
        }
        .padding(SystemPopover.padding)
        .frame(width: SystemPopover.width, alignment: .leading)
    }
}
