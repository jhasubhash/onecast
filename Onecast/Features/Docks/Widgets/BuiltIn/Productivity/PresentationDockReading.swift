import AppKit
import SwiftUI

/// What a Presentation tile and its popover both say about the coordinator at one moment.
@MainActor
struct PresentationDockReading {
    let phase: PresentationCoordinator.Phase
    let elapsed: String?
    let appName: String?
    let appIcon: NSImage?
    let displayName: String?
    let resolution: String

    init(_ coordinator: PresentationCoordinator, now: Date) {
        phase = coordinator.phase
        elapsed = coordinator.startedAt.map { TimeFormat.duration(now.timeIntervalSince($0)) }
        appName = coordinator.presentedApp?.localizedName
        appIcon = coordinator.presentedApp?.icon
        displayName = coordinator.displayName
        resolution = coordinator.resolution?.title ?? "Unchanged"
    }

    var isPresenting: Bool { phase == .presenting }
    var isBusy: Bool { phase == .starting || phase == .stopping }

    var label: String {
        switch phase {
        case .idle: "Present"
        case .starting, .stopping: "Wait"
        case .presenting: "Live"
        }
    }

    var caption: String {
        switch phase {
        case .idle: "Off"
        case .starting: "Starting"
        case .stopping: "Ending"
        case .presenting: elapsed ?? ""
        }
    }

    var tint: Color {
        switch phase {
        case .idle: Theme.Colors.textSecondary
        case .starting, .stopping: Theme.Colors.warning
        case .presenting: Theme.Colors.destructive
        }
    }

    var toggleTitle: String { isPresenting ? "End Presentation" : "Start Presentation" }
    var toggleSymbol: String { isPresenting ? "stop.fill" : "play.fill" }
}
