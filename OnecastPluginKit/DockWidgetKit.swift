import SwiftUI

// MARK: - DockWidget

/// How much of a dock's length a widget instance is given: one tile, two, or four.
@frozen public enum DockWidgetSize: String, Sendable, Codable, CaseIterable {
    case compact, wide, expanded
}

/// The screen edge the dock hosting a widget hugs; a side dock lays a wide widget out vertically.
@frozen public enum DockWidgetEdge: String, Sendable {
    case bottom, left, right

    public var isVertical: Bool { self != .bottom }
}

/// A DockWidget's fixed identity, read once when it loads.
public struct DockWidgetMetadata: Sendable, Equatable {
    public let name: String
    public let subtitle: String
    /// An SF Symbol for the widget library.
    public let icon: String
    /// The library's grouping, e.g. "Productivity", "System".
    public let category: String
    /// The sizes the widget draws well at; the first is the size a new instance takes.
    public let sizes: [DockWidgetSize]

    public init(
        name: String, subtitle: String = "", icon: String = "square.grid.2x2",
        category: String = "Other", sizes: [DockWidgetSize] = [.compact]
    ) {
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.sizes = sizes.isEmpty ? [.compact] : sizes
    }
}

/// One instance's own settings: the manifest's `preferences`, stored per instance so two copies
/// of a widget on two docks keep separate values. Read one when it is used, not once at load.
public struct DockWidgetPreferences: Sendable {
    public let instanceID: String

    public init(instanceID: String) {
        self.instanceID = instanceID
    }

    /// Where the host keeps one value in its defaults; the settings editor writes the same key.
    public static func key(instanceID: String, name: String) -> String {
        "dockwidget.\(instanceID).\(name)"
    }

    /// A text, dropdown or directory preference; nil when it is empty.
    public func string(_ name: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: key(name)), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// A text preference holding a whole number; nil when it is empty or not a number.
    public func integer(_ name: String) -> Int? {
        string(name).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    public func bool(_ name: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(name))
    }

    /// For a value the widget itself changes, such as a timer's last duration.
    public func set(_ value: String?, for name: String) {
        UserDefaults.standard.set(value, forKey: key(name))
    }

    public func set(_ value: Bool, for name: String) {
        UserDefaults.standard.set(value, forKey: key(name))
    }

    private func key(_ name: String) -> String { Self.key(instanceID: instanceID, name: name) }
}

/// What a widget may ask its host to do. Every call runs on the main actor.
public struct DockWidgetActions: Sendable {
    public let openURL: @MainActor @Sendable (URL) -> Void
    /// Launches or activates the app with this bundle identifier.
    public let launchApp: @MainActor @Sendable (String) -> Void
    /// Runs an Apple Shortcut by name.
    public let runShortcut: @MainActor @Sendable (String) -> Void
    /// Closes this widget's popover if it is open.
    public let closePopover: @MainActor @Sendable () -> Void
    /// Opens Onecast's settings for this widget instance.
    public let openSettings: @MainActor @Sendable () -> Void

    public init(
        openURL: @escaping @MainActor @Sendable (URL) -> Void,
        launchApp: @escaping @MainActor @Sendable (String) -> Void,
        runShortcut: @escaping @MainActor @Sendable (String) -> Void,
        closePopover: @escaping @MainActor @Sendable () -> Void,
        openSettings: @escaping @MainActor @Sendable () -> Void
    ) {
        self.openURL = openURL
        self.launchApp = launchApp
        self.runShortcut = runShortcut
        self.closePopover = closePopover
        self.openSettings = openSettings
    }
}

/// Everything a widget instance knows about where it is drawn.
public struct DockWidgetContext: Sendable {
    public let instanceID: String
    public let size: DockWidgetSize
    public let edge: DockWidgetEdge
    /// The dock's tile size in points; a compact tile is this square, a wide one longer.
    public let tileLength: CGFloat
    public let preferences: DockWidgetPreferences
    public let actions: DockWidgetActions

    public init(
        instanceID: String, size: DockWidgetSize, edge: DockWidgetEdge, tileLength: CGFloat,
        preferences: DockWidgetPreferences, actions: DockWidgetActions
    ) {
        self.instanceID = instanceID
        self.size = size
        self.edge = edge
        self.tileLength = tileLength
        self.preferences = preferences
        self.actions = actions
    }
}

/// A DockWidget: a live tile in a custom dock, with an optional popover opened by a click.
///
/// The host makes one object per instance on a dock, so instance state can live in properties.
/// Expose the type through a `@_cdecl("onecastDockWidgetCreate")` entry point (see
/// `OnecastDockWidgetRuntime.export`). Every call runs on the main actor; heavy work belongs on a
/// `Task.detached` you await.
@MainActor
public protocol OnecastDockWidget: AnyObject {
    init()

    static var metadata: DockWidgetMetadata { get }

    /// The tile drawn in the dock, re-asked whenever the context changes (size, edge, tile length).
    /// Keep it live with your own `@Observable` state; the host never polls.
    func tile(context: DockWidgetContext) -> AnyView

    /// The popover a click opens beside the dock. Nil (the default) makes a click do nothing,
    /// so a tile that acts on click handles its own taps instead.
    func popover(context: DockWidgetContext) -> AnyView?

    /// Called once when the instance is removed from its dock, to release timers or files.
    func didRemove()
}

public extension OnecastDockWidget {
    func popover(context: DockWidgetContext) -> AnyView? { nil }
    func didRemove() {}
}

/// The C entry point signature the host `dlsym`s for a DockWidget.
public typealias OnecastDockWidgetCreate = @convention(c) () -> UnsafeMutableRawPointer

/// The bridge between a DockWidget's `@_cdecl` entry point and the host loader.
public enum OnecastDockWidgetRuntime {
    /// Wrap a freshly-made widget for the host. Call this, and only this, from your entry point:
    ///
    /// ```swift
    /// @_cdecl("onecastDockWidgetCreate")
    /// public func onecastDockWidgetCreate() -> UnsafeMutableRawPointer {
    ///     OnecastDockWidgetRuntime.export { MyWidget() }
    /// }
    /// ```
    public static func export(_ make: @MainActor () -> any OnecastDockWidget)
        -> UnsafeMutableRawPointer
    {
        let bits: UInt = MainActor.assumeIsolated {
            UInt(bitPattern: Unmanaged.passRetained(make() as AnyObject).toOpaque())
        }
        return UnsafeMutableRawPointer(bitPattern: bits)!
    }

    /// The host side of `export`: turn the opaque pointer back into a widget. Balances the retain.
    public static func consume(_ pointer: UnsafeMutableRawPointer) -> (any OnecastDockWidget)? {
        Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue() as? any OnecastDockWidget
    }
}
