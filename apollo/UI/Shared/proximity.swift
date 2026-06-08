
import SwiftUI

// MARK: - Global Coordinate Proximity Driver
final class SingleInstanceLock {
    private var fileDescriptor: Int32 = -1

    func acquire(bundleIdentifier: String) -> Bool {
        guard fileDescriptor == -1 else { return true }
        let lockPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("\(bundleIdentifier).instance.lock")
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return true }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            fileDescriptor = descriptor
            return true
        }
        close(descriptor)
        return false
    }

    deinit {
        guard fileDescriptor >= 0 else { return }
        close(fileDescriptor)
        fileDescriptor = -1
    }
}

// Invisible panel anchored to the top-of-screen activation band. Its content
// view installs an NSTrackingArea so AppKit notifies us only when the cursor
// crosses the union of notch + approach rects, replacing always-on polling.
final class ProximityWakeWindow: NSPanel {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onApproachMouseMoved: ((NSPoint) -> Void)?
    var onDraggingEntered: (() -> Void)?
    var onDraggingUpdated: ((NSPoint) -> Void)?
    var onDraggingExited: (() -> Void)?

    var onTapToOpen: (() -> Void)?
    var isTapToOpenEnabled: (() -> Bool)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    private var notchEdgeRect: CGRect = .zero
    private var approachRect: CGRect = .zero

    override func makeKey() {
        // No-op to silence warning: -[NSWindow makeKeyWindow] called on ProximityWakeWindow which returned NO from canBecomeKeyWindow
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        // No-op to prevent window activation
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let localPoint = event.locationInWindow
            if isTapToOpenEnabled?() == true && notchEdgeRect.contains(localPoint) {
                onTapToOpen?()
                return
            } else {
                passClickThrough(event: event)
                return
            }
        }
        super.sendEvent(event)
    }

    private func passClickThrough(event: NSEvent) {
        self.ignoresMouseEvents = true

        let globalLocation = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let cgLocation = CGPoint(x: globalLocation.x, y: primaryScreenHeight - globalLocation.y)

        let source = CGEventSource(stateID: .combinedSessionState)
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: cgLocation, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: cgLocation, mouseButton: .left)

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.ignoresMouseEvents = false
        }
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        let view = TrackingHostView(frame: NSRect(origin: .zero, size: contentRect.size))
        view.onMouseEntered = { [weak self] in self?.onMouseEntered?() }
        view.onMouseExited = { [weak self] in self?.onMouseExited?() }
        view.onApproachMouseMoved = { [weak self] pt in self?.onApproachMouseMoved?(pt) }
        view.onDraggingEntered = { [weak self] in self?.onDraggingEntered?() }
        view.onDraggingUpdated = { [weak self] pt in self?.onDraggingUpdated?(pt) }
        view.onDraggingExited = { [weak self] in self?.onDraggingExited?() }
        contentView = view
    }

    func updateTrackingGeometry(notchEdgeRect: CGRect, approachRect: CGRect) {
        self.notchEdgeRect = notchEdgeRect
        self.approachRect = approachRect
        (contentView as? TrackingHostView)?.updateTrackingGeometry(
            notchEdgeRect: notchEdgeRect,
            approachRect: approachRect
        )
    }

    final class TrackingHostView: NSView {
        private enum ZoneID: String {
            case notchEdge
            case approach
        }

        var onMouseEntered: (() -> Void)?
        var onMouseExited: (() -> Void)?
        var onApproachMouseMoved: ((NSPoint) -> Void)?
        var onDraggingEntered: (() -> Void)?
        var onDraggingUpdated: ((NSPoint) -> Void)?
        var onDraggingExited: (() -> Void)?
        private var notchEdgeTrackingArea: NSTrackingArea?
        private var approachTrackingArea: NSTrackingArea?
        private var notchEdgeRect: CGRect = .zero
        private var approachRect: CGRect = .zero
        private var activeZones = Set<ZoneID>()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL, .URL])
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            registerForDraggedTypes([.fileURL, .URL])
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            rebuildTrackingArea()
        }

        func updateTrackingGeometry(notchEdgeRect: CGRect, approachRect: CGRect) {
            guard self.notchEdgeRect != notchEdgeRect || self.approachRect != approachRect else {
                return
            }
            self.notchEdgeRect = notchEdgeRect
            self.approachRect = approachRect
            rebuildTrackingArea()
        }

        func rebuildTrackingArea() {
            if let existing = notchEdgeTrackingArea {
                removeTrackingArea(existing)
                notchEdgeTrackingArea = nil
            }
            if let existing = approachTrackingArea {
                removeTrackingArea(existing)
                approachTrackingArea = nil
            }
            activeZones.removeAll()

            if notchEdgeRect.width > 0, notchEdgeRect.height > 0 {
                let area = NSTrackingArea(
                    rect: notchEdgeRect,
                    options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                    owner: self,
                    userInfo: ["zone": ZoneID.notchEdge.rawValue]
                )
                addTrackingArea(area)
                notchEdgeTrackingArea = area
            }

            if approachRect.width > 0, approachRect.height > 0 {
                let area = NSTrackingArea(
                    rect: approachRect,
                    options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                    owner: self,
                    userInfo: ["zone": ZoneID.approach.rawValue]
                )
                addTrackingArea(area)
                approachTrackingArea = area
            }
        }

        override func mouseEntered(with event: NSEvent) {
            guard let zone = zoneID(from: event) else { return }
            let inserted = activeZones.insert(zone).inserted
            if inserted {
                onMouseEntered?()
            }
        }

        override func mouseExited(with event: NSEvent) {
            guard let zone = zoneID(from: event) else { return }
            activeZones.remove(zone)
            if activeZones.isEmpty {
                onMouseExited?()
            }
        }

        override func mouseMoved(with event: NSEvent) {
            let localPoint = convert(event.locationInWindow, from: nil)
            // Use event metadata to avoid 120Hz WindowServer IPC queries to NSEvent.mouseLocation
            let globalPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            if notchEdgeRect.contains(localPoint) {
                let inserted = activeZones.insert(.notchEdge).inserted
                if inserted {
                    onMouseEntered?()
                }
                onApproachMouseMoved?(globalPoint)
                return
            }
            if approachRect.contains(localPoint) {
                let inserted = activeZones.insert(.approach).inserted
                if inserted {
                    onMouseEntered?()
                }
                onApproachMouseMoved?(globalPoint)
                return
            }
        }

        private func zoneID(from event: NSEvent) -> ZoneID? {
            guard let raw = event.trackingArea?.userInfo?["zone"] as? String else { return nil }
            return ZoneID(rawValue: raw)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onDraggingEntered?()
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            onDraggingUpdated?(NSEvent.mouseLocation)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onDraggingExited?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never intercept clicks
    }
}
