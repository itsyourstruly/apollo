//
//  apolloApp.swift
//  apollo
//

import SwiftUI
import AppKit
import Combine
import ImageIO
import AVFoundation
import Darwin
import Sparkle
import UniformTypeIdentifiers

public struct LauncherApp: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bundleIdentifier: String?
    public var isPeekerPinned: Bool?

    public init(id: UUID = UUID(), name: String, path: String, bundleIdentifier: String? = nil, isPeekerPinned: Bool? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.isPeekerPinned = isPeekerPinned
    }
}

extension LauncherApp {
    public var isPinned: Bool {
        get { isPeekerPinned ?? true }
        set { isPeekerPinned = newValue }
    }
}

public struct BookmarkItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var urlString: String
    public var customBrowserPath: String?
    public var iconBase64: String?
    public var isPeekerPinned: Bool?

    public init(id: UUID = UUID(), name: String, urlString: String, customBrowserPath: String? = nil, iconBase64: String? = nil, isPeekerPinned: Bool? = nil) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.customBrowserPath = customBrowserPath
        self.iconBase64 = iconBase64
        self.isPeekerPinned = isPeekerPinned
    }
}

extension BookmarkItem {
    public var isPinned: Bool {
        get { isPeekerPinned ?? true }
        set { isPeekerPinned = newValue }
    }
}

struct BoxFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}

struct JotNote: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct ObservedFileToast: Identifiable, Hashable {
    let id = UUID()
    let fileURL: URL
    let folderURL: URL
    let createdAt = Date()
}

// MARK: - App Main Entry
@main
struct ApolloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController
    private let userDriverDelegate: SparkleUserDriverDelegate

    init() {
            let delegate = SparkleUserDriverDelegate()
            self.userDriverDelegate = delegate
            self.updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: delegate
            )
    }

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model, updater: updaterController.updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

// MARK: - Shared UI State
final class NotchMenuModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var expansionProgress: CGFloat = 0
    @Published var currentPage = 0
    @Published var clipboardItems: [ClipboardEntry] = []
    @Published var boxFiles: [BoxFile] = []
    @Published var jotNotes: [JotNote] = []
    @Published var launcherApps: [LauncherApp] = []
    @Published var bookmarkItems: [BookmarkItem] = []
    @Published var boxDragActive = false
    @Published var boxSlimModeActive = false
    @Published var isSlimBoxCollapsed = false
    @Published var slimBoxWidth: CGFloat = 180
    @Published var slimBoxHeight: CGFloat = 260
    @Published var activeJotID: UUID?
    @Published var clipboardPulseItemID: UUID?
    @Published var observedFileToast: ObservedFileToast?
    @Published var canCloseFromVerticalSwipe = false
    @Published var closeGestureProgress: CGFloat = 0
    @Published var isToastDismissing = false
    @Published var chunkedClipboardRows: [[ClipboardEntry]] = []
    
    @Published var isStopwatchRunning = false
    @Published var stopwatchStartTime: TimeInterval? = nil
    @Published var stopwatchAccumulatedTime: TimeInterval = 0
    @Published var isTimerRunning = false
    @Published var timerDuration: TimeInterval = 0
    @Published var timerEndTime: TimeInterval? = nil
    @Published var timerRemainingAtPause: TimeInterval = 0
    @Published var isAddSheetOpen = false
    @Published var isContentActive = false
}

final class SwipeState: ObservableObject {
    static let shared = SwipeState()
    @Published var carouselDragOffset: CGFloat = 0
}

enum AppStorageKey {
    static let clipboardHistory = "clipboardHistory"
    static let accentRed = "accentRed"
    static let accentGreen = "accentGreen"
    static let accentBlue = "accentBlue"
    static let accentAlpha = "accentAlpha"
    static let backgroundRed = "backgroundRed"
    static let backgroundGreen = "backgroundGreen"
    static let backgroundBlue = "backgroundBlue"
    static let backgroundAlpha = "backgroundAlpha"
    static let titleRed = "titleRed"
    static let titleGreen = "titleGreen"
    static let titleBlue = "titleBlue"
    static let titleAlpha = "titleAlpha"
    static let titleUseAccent = "titleUseAccent"
    static let clipboardTitleAlignment = "clipboardTitleAlignment"
    static let clipboardTitleSize = "clipboardTitleSize"
    static let clipboardTitleIconName = "clipboardTitleIconName"
    static let clipboardTitleUseAccent = "clipboardTitleUseAccent"
    static let clipboardTitleRed = "clipboardTitleRed"
    static let clipboardTitleGreen = "clipboardTitleGreen"
    static let clipboardTitleBlue = "clipboardTitleBlue"
    static let clipboardTitleAlpha = "clipboardTitleAlpha"
    static let jotTitleAlignment = "jotTitleAlignment"
    static let jotTitleSize = "jotTitleSize"
    static let jotTitleIconName = "jotTitleIconName"
    static let jotTitleUseAccent = "jotTitleUseAccent"
    static let jotTitleRed = "jotTitleRed"
    static let jotTitleGreen = "jotTitleGreen"
    static let jotTitleBlue = "jotTitleBlue"
    static let jotTitleAlpha = "jotTitleAlpha"
    static let boxTitleAlignment = "boxTitleAlignment"
    static let boxTitleSize = "boxTitleSize"
    static let boxTitleIconName = "boxTitleIconName"
    static let boxTitleUseAccent = "boxTitleUseAccent"
    static let boxTitleRed = "boxTitleRed"
    static let boxTitleGreen = "boxTitleGreen"
    static let boxTitleBlue = "boxTitleBlue"
    static let boxTitleAlpha = "boxTitleAlpha"
    static let notchWidth = "notchWidth"
    static let notchHeight = "notchHeight"
    static let defaultPage = "defaultPage"
    static let rememberClips = "rememberClips"
    static let jotNotes = "jotNotes"
    static let titleAlignment = "titleAlignment"
    static let titleSize = "titleSize"
    static let titleIconName = "titleIconName"
    static let cornerRadius = "cornerRadius"
    static let showPagers = "showPagers"
    static let showBoxFileNames = "showBoxFileNames"
    static let defaultToBoxIfItems = "defaultToBoxIfItems"
    static let clipboardAction = "clipboardAction"
    static let clipboardColumns = "clipboardColumns"
    static let jotColumns = "jotColumns"
    static let boxColumns = "boxColumns"
    static let clipTextSize = "clipTextSize"
    static let clipFileLabelSize = "clipFileLabelSize"
    static let jotTextSize = "jotTextSize"
    static let boxFileNameSize = "boxFileNameSize"
    static let reopenLastPage = "reopenLastPage"
    static let lastVisitedPage = "lastVisitedPage"
    static let animationResponse = "animationResponse"
    static let animationDamping = "animationDamping"
    static let notchAnimationResponse = "notchAnimationResponse"
    static let notchAnimationDamping = "notchAnimationDamping"
    static let carouselAnimationResponse = "carouselAnimationResponse"
    static let carouselAnimationDamping = "carouselAnimationDamping"
    static let swipeAnimationResponse = "swipeAnimationResponse"
    static let swipeAnimationDamping = "swipeAnimationDamping"
    static let observedFolders = "observedFolders"
    static let proximitySensitivity = "proximitySensitivity"
    static let carouselSensitivity = "carouselSensitivity"
    static let closeSensitivity = "closeSensitivity"
    static let approachDelay = "approachDelay"
    static let hoverCloseDelay = "hoverCloseDelay"
    static let swipeCloseDelay = "swipeCloseDelay"
    static let disableApproach = "disableApproach"
    static let alwaysUseApproachWhenDraggingFile = "alwaysUseApproachWhenDraggingFile"
    static let notchEdgeThickness = "notchEdgeThickness"
    static let approachWidth = "approachWidth"
    static let approachHeight = "approachHeight"

    // Custom Titles (String)
    static let clipboardCustomTitle = "clipboardCustomTitle"
    static let jotCustomTitle = "jotCustomTitle"
    static let boxCustomTitle = "boxCustomTitle"
    static let chronoCustomTitle = "chronoCustomTitle"
    static let calendarCustomTitle = "calendarCustomTitle"
    static let launcherCustomTitle = "launcherCustomTitle"
    static let bookmarksCustomTitle = "bookmarksCustomTitle"
    static let combinedCustomTitle = "combinedCustomTitle"

    // Show Title Icons (Bool)
    static let clipboardShowTitleIcon = "clipboardShowTitleIcon"
    static let jotShowTitleIcon = "jotShowTitleIcon"
    static let boxShowTitleIcon = "boxShowTitleIcon"
    static let chronoShowTitleIcon = "chronoShowTitleIcon"
    static let calendarShowTitleIcon = "calendarShowTitleIcon"
    static let launcherShowTitleIcon = "launcherShowTitleIcon"
    static let bookmarksShowTitleIcon = "bookmarksShowTitleIcon"
    static let combinedShowTitleIcon = "combinedShowTitleIcon"

    // Bookmark Layout Customizations
    static let bookmarkIconSize = "bookmarkIconSize"
    static let bookmarkTextSize = "bookmarkTextSize"
    static let bookmarkShowName = "bookmarkShowName"

    // Chrono Title Overrides
    static let chronoTitleAlignment = "chronoTitleAlignment"
    static let chronoTitleSize = "chronoTitleSize"
    static let chronoTitleIconName = "chronoTitleIconName"
    static let chronoTitleUseAccent = "chronoTitleUseAccent"
    static let chronoTitleRed = "chronoTitleRed"
    static let chronoTitleGreen = "chronoTitleGreen"
    static let chronoTitleBlue = "chronoTitleBlue"
    static let chronoTitleAlpha = "chronoTitleAlpha"

    // Calendar Title Overrides
    static let calendarTitleAlignment = "calendarTitleAlignment"
    static let calendarTitleSize = "calendarTitleSize"
    static let calendarTitleIconName = "calendarTitleIconName"
    static let calendarTitleUseAccent = "calendarTitleUseAccent"
    static let calendarTitleRed = "calendarTitleRed"
    static let calendarTitleGreen = "calendarTitleGreen"
    static let calendarTitleBlue = "calendarTitleBlue"
    static let calendarTitleAlpha = "calendarTitleAlpha"

    // Launcher Title Overrides
    static let launcherTitleAlignment = "launcherTitleAlignment"
    static let launcherTitleSize = "launcherTitleSize"
    static let launcherTitleIconName = "launcherTitleIconName"
    static let launcherTitleUseAccent = "launcherTitleUseAccent"
    static let launcherTitleRed = "launcherTitleRed"
    static let launcherTitleGreen = "launcherTitleGreen"
    static let launcherTitleBlue = "launcherTitleBlue"
    static let launcherTitleAlpha = "launcherTitleAlpha"

    // Bookmarks Title Overrides
    static let bookmarksTitleAlignment = "bookmarksTitleAlignment"
    static let bookmarksTitleSize = "bookmarksTitleSize"
    static let bookmarksTitleIconName = "bookmarksTitleIconName"
    static let bookmarksTitleUseAccent = "bookmarksTitleUseAccent"
    static let bookmarksTitleRed = "bookmarksTitleRed"
    static let bookmarksTitleGreen = "bookmarksTitleGreen"
    static let bookmarksTitleBlue = "bookmarksTitleBlue"
    static let bookmarksTitleAlpha = "bookmarksTitleAlpha"

    // Combined Title Overrides
    static let combinedTitleAlignment = "combinedTitleAlignment"
    static let combinedTitleSize = "combinedTitleSize"
    static let combinedTitleIconName = "combinedTitleIconName"
    static let combinedTitleUseAccent = "combinedTitleUseAccent"
    static let combinedTitleRed = "combinedTitleRed"
    static let combinedTitleGreen = "combinedTitleGreen"
    static let combinedTitleBlue = "combinedTitleBlue"
    static let combinedTitleAlpha = "combinedTitleAlpha"
    static let disableChronoHUD = "disableChronoHUD"

    // Per-page enable flags
    static let clipEnabled = "clipEnabled"
    static let jotEnabled = "jotEnabled"
    static let boxEnabled = "boxEnabled"
    static let chronoEnabled = "chronoEnabled"
    static let calendarEnabled = "calendarEnabled"
    static let launcherEnabled = "launcherEnabled"
    static let pagerStyle = "pagerStyle"
    static let peekerSize = "peekerSize"
    static let pageOrder = "pageOrder"
    static let openMethod = "openMethod"
    static let bookmarksEnabled = "bookmarksEnabled"
    static let pagerStyle2BackgroundEnabled = "pagerStyle2BackgroundEnabled"
}

func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
    return max(minValue, min(maxValue, value))
}

func safeDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
    guard value.isFinite else { return fallback }
    return max(1, value)
}

func scaledPanelWidth(for settings: AppSettings) -> CGFloat {
    let widthScale = settings.clampedNotchWidth / baseNotchWidth
    return safeDimension(380 * widthScale, fallback: 380)
}

func scaledPanelHeight(for settings: AppSettings) -> CGFloat {
    let heightScale = settings.clampedNotchHeight / baseNotchHeight
    return safeDimension(200 * heightScale, fallback: 200)
}

let baseNotchWidth: CGFloat = 210
let baseNotchHeight: CGFloat = 32
let toastPanelHeight: CGFloat = 260
let toastPanelWidth: CGFloat = 180

func hardwareNotchDimensions(for screen: NSScreen?) -> (x: CGFloat, width: CGFloat, height: CGFloat) {
    guard let screen else {
        return (0, baseNotchWidth, baseNotchHeight)
    }
    let screenRect = screen.frame
    let topInset = screen.safeAreaInsets.top
    let leftAux = screen.auxiliaryTopLeftArea
    let rightAux = screen.auxiliaryTopRightArea

    let auxGapWidth: CGFloat = {
        guard let leftAux, let rightAux else { return 0 }
        let leftMax = leftAux.maxX
        let rightMin = rightAux.minX
        let gap = rightMin - leftMax
        return gap.isFinite && gap > 0 ? gap : 0
    }()

    let x = leftAux?.maxX ?? (screenRect.width - baseNotchWidth) / 2

    let width = auxGapWidth > 0 ? auxGapWidth : {
        let horizontalDifferential = screenRect.width - screen.visibleFrame.width
        return (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
    }()

    let height = topInset > 0 ? topInset : baseNotchHeight
    return (x, safeDimension(width, fallback: baseNotchWidth), safeDimension(height, fallback: baseNotchHeight))
}

struct BottomRoundedRectangle: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = max(0, cornerRadius)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        let tl = CGPoint(x: rect.minX, y: rect.minY)

        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: CGPoint(x: br.x, y: br.y - radius))
        path.addQuadCurve(to: CGPoint(x: br.x - radius, y: br.y), control: br)
        path.addLine(to: CGPoint(x: bl.x + radius, y: bl.y))
        path.addQuadCurve(to: CGPoint(x: bl.x, y: bl.y - radius), control: bl)
        path.addLine(to: tl)
        path.closeSubpath()
        return path
    }
}

final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private var missingPaths = Set<String>()
    private let lock = NSRecursiveLock()
    
    private init() {
        cache.countLimit = 100
    }
    
    func icon(forPath path: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        
        let nsPath = path as NSString
        if let cached = cache.object(forKey: nsPath) {
            return cached
        }
        if missingPaths.contains(path) {
            return nil
        }
        
        if FileManager.default.fileExists(atPath: path) {
            return autoreleasepool {
                let img = NSWorkspace.shared.icon(forFile: path)
                cache.setObject(img, forKey: nsPath)
                return img
            }
        } else {
            missingPaths.insert(path)
            return nil
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        missingPaths.removeAll()
    }
}

final class PersistenceWriteCoordinator {
    static let shared = PersistenceWriteCoordinator()

    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "apollo.persistence.coalesced-writes", qos: .utility)
    private let flushDelay: TimeInterval = 0.35

    private var pendingClipboardEntries: [ClipboardEntry]?
    private var pendingJotNotes: [JotNote]?
    private var flushWorkItem: DispatchWorkItem?

    private init() {}

    func scheduleClipboardHistory(_ entries: [ClipboardEntry]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingClipboardEntries = entries
            self.scheduleFlushLocked()
        }
    }

    func scheduleJotNotes(_ notes: [JotNote]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingJotNotes = notes
            self.scheduleFlushLocked()
        }
    }

    func flushNow() {
        queue.sync {
            flushLocked()
        }
    }

    private func scheduleFlushLocked() {
        flushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushLocked()
        }
        flushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + flushDelay, execute: workItem)
    }

    private func flushLocked() {
        flushWorkItem?.cancel()
        flushWorkItem = nil

        if let entries = pendingClipboardEntries,
           let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: AppStorageKey.clipboardHistory)
        }
        pendingClipboardEntries = nil

        if let notes = pendingJotNotes,
           let data = try? JSONEncoder().encode(notes) {
            defaults.set(data, forKey: AppStorageKey.jotNotes)
        }
        pendingJotNotes = nil
    }
}

func persistJotNotes(_ notes: [JotNote]) {
    PersistenceWriteCoordinator.shared.scheduleJotNotes(notes)
}

func loadLauncherApps() -> [LauncherApp] {
    guard let data = UserDefaults.standard.data(forKey: "launcherApps"),
          let apps = try? JSONDecoder().decode([LauncherApp].self, from: data) else {
        return []
    }
    return apps
}

func persistLauncherApps(_ apps: [LauncherApp]) {
    if let data = try? JSONEncoder().encode(apps) {
        UserDefaults.standard.set(data, forKey: "launcherApps")
    }
}

func loadBookmarkItems() -> [BookmarkItem] {
    guard let data = UserDefaults.standard.data(forKey: "bookmarkItems"),
          let bookmarks = try? JSONDecoder().decode([BookmarkItem].self, from: data) else {
        return []
    }
    return bookmarks
}

func persistBookmarkItems(_ bookmarks: [BookmarkItem]) {
    if let data = try? JSONEncoder().encode(bookmarks) {
        UserDefaults.standard.set(data, forKey: "bookmarkItems")
    }
}

struct IslandExitTracker {}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var isPointInteractive: ((NSPoint) -> Bool)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.setAccessibilityElement(false)
        self.setAccessibilityRole(.none)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let interactive = isPointInteractive, !interactive(point) {
            return nil
        }
        return super.hitTest(point)
    }
}

extension NSView {
    func stopScrolling() {
        if let scrollView = self as? NSScrollView {
            scrollView.contentView.setBoundsOrigin(scrollView.contentView.bounds.origin)
        }
        for subview in subviews {
            subview.stopScrolling()
        }
    }
}

final class IslandPanel: NSPanel {
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    var onSwipeUp: (() -> Void)?
    var isActiveProvider: (() -> Bool)?
    var canTriggerVertical: (() -> Bool)?
    var onCloseProgress: ((NSDirectionalRectEdge, CGFloat, Bool) -> Void)?
    var onCloseProgressLegacy: ((CGFloat, Bool) -> Void)?
    var onCarouselOffset: ((CGFloat, Bool) -> Void)?
    var carouselSensitivityProvider: (() -> CGFloat)?
    var closeSensitivityProvider: (() -> CGFloat)?
    var onCloseButtonTapped: (() -> Void)?
    var onCollapseButtonTapped: (() -> Void)?
    var isCloseButtonVisible: (() -> Bool)?
    var isCollapseButtonVisible: (() -> Bool)?

    var isAtFirstPageProvider: (() -> Bool)?
    var isAtLastPageProvider: (() -> Bool)?
    var panelWidthProvider: (() -> CGFloat)?
    var isTapToOpenProvider: (() -> Bool)?
    var isExpandedProvider: (() -> Bool)?
    var onTapToOpen: (() -> Void)?

    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private let baseHorizontalThreshold: CGFloat = 80
    private let baseVerticalThreshold: CGFloat = 110
    private let axisLockThreshold: CGFloat = 4
    private let maxCarouselGive: CGFloat = 36
    private var snapBackWorkItem: DispatchWorkItem?
    private var ignoreScrollUntil: TimeInterval = 0
    private var didCommitThisGesture = false
    private var lastCarouselCommitTime: TimeInterval = 0
    private var lastCarouselOffsetEmitTime: TimeInterval = 0
    private var lastCarouselOffsetEmitValue: CGFloat = 0
    private var lastCloseProgressEmitTime: TimeInterval = 0
    private var lastCloseProgressEmitValue: CGFloat = 0
    private var verticalCloseArmed = false
    private enum GestureAxis {
        case horizontal
        case vertical
    }
    private var gestureAxis: GestureAxis?

    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        // Intercept left mouse clicks in the close button region at the AppKit level
        // This bypasses SwiftUI's gesture system which doesn't work reliably in non-activating panels
        if event.type == .leftMouseDown {
            if isTapToOpenProvider?() == true, isExpandedProvider?() == false {
                onTapToOpen?()
                return
            }
            
            let loc = event.locationInWindow
            let size = self.frame.size
            
            // Close button is in the top-right corner: 40x42 hit region
            if let closeHandler = onCloseButtonTapped, isCloseButtonVisible?() == true {
                let closeRect = NSRect(x: size.width - 40, y: size.height - 42, width: 40, height: 42)
                if closeRect.contains(loc) {
                    closeHandler()
                    return
                }
            }
            
            // Collapse button: 40x42 hit region immediately to the left of the close button (x: width - 80 to width - 40)
            if let collapseHandler = onCollapseButtonTapped, isCollapseButtonVisible?() == true {
                let collapseRect = NSRect(x: size.width - 80, y: size.height - 42, width: 40, height: 42)
                if collapseRect.contains(loc) {
                    collapseHandler()
                    return
                }
            }
        }
        if event.type == .scrollWheel || event.type == .swipe {
            if handleGestureEvent(event) {
                return
            }
        }
        super.sendEvent(event)
    }

    private func rubberBand(offset: CGFloat, limit: CGFloat) -> CGFloat {
        let absOffset = abs(offset)
        let sign: CGFloat = offset >= 0 ? 1.0 : -1.0
        let factor = 1.0 / (1.0 + absOffset / limit)
        return sign * limit * (1.0 - factor)
    }

    private func handleGestureEvent(_ event: NSEvent) -> Bool {
        guard isActiveProvider?() == true else { return false }
        guard frame.contains(NSEvent.mouseLocation) else { return false }
        if event.timestamp < ignoreScrollUntil {
            return true
        }

        if event.phase == .began || event.phase == .mayBegin || event.momentumPhase == .began {
            resetAccumulation(resetProgress: false)
            gestureAxis = nil
            snapBackWorkItem?.cancel()
            didCommitThisGesture = false
            lastCarouselOffsetEmitTime = 0
            lastCarouselOffsetEmitValue = 0
            lastCloseProgressEmitTime = 0
            lastCloseProgressEmitValue = 0
            verticalCloseArmed = false
        }

        if event.type == .swipe {
            let swipeX = event.deltaX
            let swipeY = event.deltaY
            if abs(swipeX) >= abs(swipeY) {
                if swipeX < 0 {
                    onSwipeRight?()
                } else if swipeX > 0 {
                    onSwipeLeft?()
                }
                onCloseProgressLegacy?(0, true)
                return true
            }
            if swipeY > 0, canTriggerVertical?() == true {
                onSwipeUp?()
                onCloseProgressLegacy?(0, true)
                return true
            }
            onCloseProgressLegacy?(0, true)
            return false
        }

        let rawDeltaX = event.scrollingDeltaX
        let rawDeltaY = event.scrollingDeltaY
        guard rawDeltaX != 0 || rawDeltaY != 0 else { return false }

        let isTrackpadLike = event.hasPreciseScrollingDeltas || event.phase != [] || event.momentumPhase != []
        let fingerDeltaX = event.isDirectionInvertedFromDevice ? -rawDeltaX : rawDeltaX
        let fingerDeltaY = event.isDirectionInvertedFromDevice ? -rawDeltaY : rawDeltaY
        let absX = abs(fingerDeltaX)
        let absY = abs(fingerDeltaY)

        let carouselSensitivity = max(0.2, carouselSensitivityProvider?() ?? 1.0)
        let closeSensitivity = max(0.2, closeSensitivityProvider?() ?? 1.0)
        let horizontalThreshold = baseHorizontalThreshold / carouselSensitivity
        let verticalThreshold = baseVerticalThreshold / closeSensitivity

        if gestureAxis == nil {
            if max(absX, absY) < axisLockThreshold {
                if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                    scheduleSnapBack(immediate: true)
                }
                return false
            }
            gestureAxis = absX >= absY ? .horizontal : .vertical
        }

        if gestureAxis == .horizontal {
            if !isTrackpadLike && abs(rawDeltaX) <= abs(rawDeltaY) {
                return false
            }
            if didCommitThisGesture {
                return true
            }
            accumulatedDeltaX += fingerDeltaX
            let panelWidth = panelWidthProvider?() ?? 300
            let rawOffset = -accumulatedDeltaX
            
            let finalOffset: CGFloat
            let isAtFirst = isAtFirstPageProvider?() == true
            let isAtLast = isAtLastPageProvider?() == true
            
            if isAtFirst && rawOffset > 0 {
                finalOffset = rubberBand(offset: rawOffset, limit: 60)
            } else if isAtLast && rawOffset < 0 {
                finalOffset = rubberBand(offset: rawOffset, limit: 60)
            } else {
                finalOffset = clamp(rawOffset, min: -panelWidth, max: panelWidth)
            }
            
            let minEmitDelta: CGFloat = isTrackpadLike ? 0.5 : 1.5
            let minEmitInterval: TimeInterval = isTrackpadLike ? (1.0 / 120.0) : (1.0 / 60.0)
            if abs(finalOffset - lastCarouselOffsetEmitValue) >= minEmitDelta,
               (event.timestamp - lastCarouselOffsetEmitTime) >= minEmitInterval {
                onCarouselOffset?(finalOffset, false)
                lastCarouselOffsetEmitValue = finalOffset
                lastCarouselOffsetEmitTime = event.timestamp
            }
            if abs(accumulatedDeltaX) > horizontalThreshold {
                if event.timestamp - lastCarouselCommitTime < 0.08 {
                    return true
                }
                lastCarouselCommitTime = event.timestamp
                didCommitThisGesture = true
                if accumulatedDeltaX < 0 {
                    onSwipeRight?()
                } else {
                    onSwipeLeft?()
                }
                onCarouselOffset?(0, true)
                lastCarouselOffsetEmitValue = 0
                lastCarouselOffsetEmitTime = event.timestamp
                snapBackWorkItem?.cancel()
                resetAccumulation(resetProgress: true)
                gestureAxis = nil
                ignoreScrollUntil = event.timestamp + 0.18
                return true
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                onCarouselOffset?(0, true)
                lastCarouselOffsetEmitValue = 0
                lastCarouselOffsetEmitTime = event.timestamp
                resetAccumulation(resetProgress: true)
                gestureAxis = nil
                scheduleSnapBack(immediate: true)
            }
            return true
        }

        onCarouselOffset?(0, true)

        if canTriggerVertical?() == true && fingerDeltaY > 0 {
            if !verticalCloseArmed {
                if event.phase == .began || event.phase == .mayBegin || event.momentumPhase == .began {
                    verticalCloseArmed = true
                } else {
                    return false
                }
            }
            accumulatedDeltaY = max(0, accumulatedDeltaY + fingerDeltaY)
            let progress = max(0, min(1, accumulatedDeltaY / verticalThreshold))
            let minEmitDelta: CGFloat = 0.03
            let minEmitInterval: TimeInterval = 1.0 / 50.0
            if progress >= 1
                || (abs(progress - lastCloseProgressEmitValue) >= minEmitDelta
                    && (event.timestamp - lastCloseProgressEmitTime) >= minEmitInterval) {
                onCloseProgressLegacy?(progress, false)
                lastCloseProgressEmitValue = progress
                lastCloseProgressEmitTime = event.timestamp
            }
            if progress >= 1 {
                onSwipeUp?()
                accumulatedDeltaY = 0
                gestureAxis = nil
                verticalCloseArmed = false
                lastCloseProgressEmitValue = 0
                lastCloseProgressEmitTime = event.timestamp
                ignoreScrollUntil = event.timestamp + 0.12
                return true
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                onCloseProgressLegacy?(0, true)
                accumulatedDeltaY = 0
                gestureAxis = nil
                didCommitThisGesture = false
                verticalCloseArmed = false
                lastCloseProgressEmitValue = 0
                lastCloseProgressEmitTime = event.timestamp
                scheduleSnapBack(immediate: true)
            }
            return true
        } else {
            if accumulatedDeltaY > 0 {
                onCloseProgressLegacy?(0, true)
                accumulatedDeltaY = 0
                lastCloseProgressEmitValue = 0
                lastCloseProgressEmitTime = event.timestamp
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                gestureAxis = nil
                didCommitThisGesture = false
                verticalCloseArmed = false
            }
            return false
        }
    }

    private func resetAccumulation(resetProgress: Bool = true) {
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        lastCloseProgressEmitTime = 0
        lastCloseProgressEmitValue = 0
        if resetProgress {
            onCloseProgressLegacy?(0, true)
        }
    }

    private func scheduleSnapBack(immediate: Bool = false) {
        snapBackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onCarouselOffset?(0, true)
            self.onCloseProgressLegacy?(0, true)
        }
        snapBackWorkItem = workItem
        if immediate {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
        }
    }
}

extension View {
    @ViewBuilder
    func conditionalDrawingGroup(_ active: Bool) -> some View {
        if active {
            self.drawingGroup()
        } else {
            self
        }
    }
}

extension NSView {
    func findScrollView() -> NSScrollView? {
        if let scrollView = self as? NSScrollView {
            return scrollView
        }
        for subview in subviews {
            if let found = subview.findScrollView() {
                return found
            }
        }
        return nil
    }
}


extension View {
    func nativeSettingsFormStyle() -> some View {
        formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    func conditionalLabelStyle(showIcon: Bool) -> some View {
        if showIcon {
            self.labelStyle(.titleAndIcon)
        } else {
            self.labelStyle(.titleOnly)
        }
    }
}

extension View {
    @ViewBuilder
    func conditionalClip(clipAll: Bool, cornerRadius: CGFloat) -> some View {
        if clipAll {
            self.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.clipShape(BottomRoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - VisualEffectView for Glassmorphism
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
