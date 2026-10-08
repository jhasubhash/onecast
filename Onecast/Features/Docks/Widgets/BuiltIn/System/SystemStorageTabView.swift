import AppKit
import SwiftUI

struct SystemStorageTabView: View {
    private let sampler = DockWidgetServices.current.activity
    @State private var scanner = SystemStorageScanner()
    @State private var scanRoot = SystemStorage.ScanRoot.home

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                volumes
                scanSection
            }
        }
    }

    private var volumes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(sampler.volumes) { volume in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    SystemValueRow(
                        title: volume.name,
                        value: "\(SystemFormat.bytes(volume.available)) free of \(SystemFormat.bytes(volume.total))")
                    SystemMeterBar(fraction: volume.usedFraction, tint: SystemTint.load(volume.usedFraction))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SystemSectionHeader(title: "Scan folders")
            HStack(spacing: Theme.Spacing.md) {
                SteadySegmentedPicker(
                    title: "Folder to scan",
                    options: SystemStorage.ScanRoot.allCases.map {
                        SteadySegmentedPicker.Option(value: $0, title: $0.title)
                    }, selection: $scanRoot)
                Spacer(minLength: 0)
                BarButton(
                    chrome: .rounded,
                    action: { scanner.isScanning ? scanner.cancel() : scanner.scan(scanRoot) }
                ) {
                    Text(scanner.isScanning ? "Stop" : "Scan")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            status
            results
            Text("Read only: nothing is deleted. Click an item to reveal it in Finder.")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch scanner.phase {
        case .idle:
            EmptyView()
        case .scanning(let current):
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.small)
                Text(current.map { "Measuring \($0)…" } ?? "Starting…")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        case .finished:
            let folder = scanner.root?.title ?? "Folder"
            Text("\(folder): \(SystemFormat.bytes(scanner.scannedBytes)) in \(scanner.entries.count) items")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .cancelled:
            Text("Scan stopped. Showing what was measured so far.")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var results: some View {
        let total = scanner.scannedBytes
        return VStack(spacing: Theme.Spacing.sm) {
            ForEach(scanner.entries) { entry in
                Button {
                    AppLauncher.showInFinder(URL(fileURLWithPath: entry.path))
                } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.md) {
                            SymbolImage(name: entry.isDirectory ? "folder" : "doc", size: Theme.Typography.menuSymbolSize)
                                .foregroundStyle(Theme.Colors.menuSymbol)
                            Text(entry.name)
                                .font(Theme.Typography.rowTrailing)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Theme.Spacing.md)
                            Text(SystemFormat.bytes(entry.bytes))
                                .font(Theme.Typography.rowTrailing.monospacedDigit())
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        SystemMeterBar(
                            fraction: SystemStorage.share(of: entry, in: total), tint: Theme.Colors.progress,
                            height: Theme.Spacing.xs)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tooltip("Reveal in Finder")
                .accessibilityLabel(entry.name)
                .accessibilityValue(SystemFormat.bytes(entry.bytes))
                .accessibilityHint("Reveals it in Finder")
            }
        }
    }
}
