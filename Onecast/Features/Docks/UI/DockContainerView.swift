import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// A pinned tile in flight, as `DockDragItem` JSON; only a dock accepts it.
    static let dockItem = NSPasteboard.PasteboardType("com.onecast.dock.item")
}

/// A pinned tile being dragged: where it came from, and what it is.
struct DockDragItem: Codable {
    let dockID: UUID
    let layoutID: UUID
    let item: DockItem
}

/// What the container needs to start dragging a tile.
struct DockDragPayload {
    let source: DockDragItem
    let image: NSImage
    /// Where the tile is on screen, so the picture starts exactly over it.
    let screenRect: CGRect
}

/// The panel's content: the SwiftUI dock underneath, and the whole of the pointer above it.
///
/// Tiles carry no gestures. This view hit-tests the pointer against the dock's own layout, so a
/// click, a drag, a right click and a scroll all land on the tile the user sees, magnified or
/// not. A widget tile keeps its own clicks: a press on one that never became a drag is replayed.
final class DockContainerView: NSView, NSDraggingSource {
    weak var surface: DockSurface?
    private var trackingArea: NSTrackingArea?
    private var activeDrag: DockDragPayload?
    /// Set while a widget's press is sent again, so it reaches the widget's own SwiftUI view.
    private var isReplaying = false

    private static let dragSlop: CGFloat = 4
    private static let holdDelay: TimeInterval = 0.4

    init(hosting: NSView) {
        super.init(frame: .zero)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        registerForDraggedTypes([.fileURL, .URL, .dockItem])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Hit testing

    /// Claims the events the dock handles itself; everything else falls through to SwiftUI.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let inside = super.hitTest(point) else { return nil }
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged, .scrollWheel:
            return self
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return isReplaying ? inside : self
        default:
            return inside
        }
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        surface?.pointerEntered(atScreen: NSEvent.mouseLocation)
    }

    override func mouseMoved(with event: NSEvent) {
        surface?.pointerMoved(toScreen: NSEvent.mouseLocation)
    }

    override func mouseExited(with event: NSEvent) {
        surface?.pointerExited()
    }

    override func rightMouseDown(with event: NSEvent) {
        surface?.showMenu(atScreen: NSEvent.mouseLocation)
    }

    override func scrollWheel(with event: NSEvent) {
        surface?.scroll(event)
    }

    // MARK: - Press

    private enum Outcome {
        case click, hold, drag
    }

    /// Follows the press itself: a click on release, a hold after a beat for a folder, a drag
    /// once it leaves the slop.
    override func mouseDown(with event: NSEvent) {
        guard !isReplaying, let surface, let window else { return }
        let start = NSEvent.mouseLocation
        if event.modifierFlags.contains(.control) {
            surface.showMenu(atScreen: start)
            return
        }
        if surface.isOverHandle(atScreen: start) {
            moveDock(surface, in: window)
            return
        }
        guard let slotID = surface.slotID(atScreen: start) else { return }
        var outcome = Outcome.click
        var release: NSEvent?
        let timeout = surface.opensOnHold(slotID: slotID) ? Self.holdDelay : NSEvent.foreverDuration
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: timeout, mode: .eventTracking
        ) { tracked, stop in
            guard let tracked else {
                outcome = .hold
                stop.pointee = true
                return
            }
            guard tracked.type != .leftMouseUp else {
                release = tracked
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            if hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragSlop {
                outcome = .drag
                stop.pointee = true
            }
        }
        switch outcome {
        case .click where surface.isWidget(slotID: slotID):
            replay(event, release: release, in: window)
        case .click:
            surface.click(slotID: slotID)
        case .hold:
            surface.hold(slotID: slotID)
            window.trackEvents(
                matching: [.leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking
            ) { _, stop in stop.pointee = true }
        case .drag:
            beginDrag(slotID: slotID, event: event)
        }
    }

    /// The release goes ahead of the press, so a control that tracks the mouse itself finds it.
    private func replay(_ press: NSEvent, release: NSEvent?, in window: NSWindow) {
        isReplaying = true
        defer { isReplaying = false }
        if let release { NSApp.postEvent(release, atStart: true) }
        window.sendEvent(press)
        guard release != nil,
            let pending = NSApp.nextEvent(
                matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
        else { return }
        window.sendEvent(pending)
    }

    /// The handle follows the pointer until the button is released.
    private func moveDock(_ surface: DockSurface, in window: NSWindow) {
        surface.beginHandleDrag(atScreen: NSEvent.mouseLocation)
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            surface.dragHandle(toScreen: NSEvent.mouseLocation)
            if tracked?.type != .leftMouseDragged { stop.pointee = true }
        }
        surface.endHandleDrag()
    }

    // MARK: - Dragging out

    private func beginDrag(slotID: String, event: NSEvent) {
        guard let surface, let window, let payload = surface.dragPayload(slotID: slotID)
        else { return }
        let writer = NSPasteboardItem()
        guard let data = try? JSONEncoder().encode(payload.source) else { return }
        writer.setData(data, forType: .dockItem)
        let dragging = NSDraggingItem(pasteboardWriter: writer)
        let frame = convert(window.convertFromScreen(payload.screenRect), from: nil)
        dragging.setDraggingFrame(frame, contents: payload.image)
        activeDrag = payload
        surface.dragBegan(slotID: slotID)
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        // The dock plays its own exit when a tile is dragged off, so nothing flies back.
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : .delete
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        let payload = activeDrag
        activeDrag = nil
        surface?.dragEnded(payload, atScreen: screenPoint, operation: operation)
    }

    // MARK: - Dropping in

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        surface?.dragUpdated(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        surface?.dragUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        surface?.dragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        surface?.dragPerformed(sender) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        surface?.dragExited()
    }
}
