
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var islandWindow: IslandPanel!
    var notchWindow: IslandPanel! { islandWindow }
    private var clipboardMonitorTask: Task<Void, Never>?
    private var dragPollingTimer: DispatchSourceTimer?
    private var fastDragTrackingTimer: DispatchSourceTimer?
    private var isDragSessionActive = false
    var slimBoxWindow: IslandPanel?
    var slimBoxDidReceiveDropThisSession = false
    private var lastDragChangeCount = -1
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var idleCompactionWorkItem: DispatchWorkItem?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    let model = NotchMenuModel()
    private let settings = AppSettings.shared
    private var settingsCancellables = Set<AnyCancellable>()
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var swipeCloseWorkItem: DispatchWorkItem?
    private var toastHideWorkItem: DispatchWorkItem?
    private var lastCloseProgressEmission: CGFloat = 0
    private var lastCarouselOffsetEmission: CGFloat = 0
    private var batteryWindow: NSPanel?
    
    private var notchPreviewWorkItem: DispatchWorkItem?
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastRetryChangeCount = -1
    private var folderMonitors: [String: FolderMonitor] = [:]
    private var folderSnapshots: [String: Set<String>] = [:]
    private var suppressProximityUntilExit = false
    private var isCursorInActivationZone = false
    private var pendingWindowHeightUpdate: CGFloat?
    private var windowFrameUpdateWorkItem: DispatchWorkItem?
    private var cachedScreenFrame: NSRect = .zero
    private let singleInstanceLock = SingleInstanceLock()
    private var chronoActivity: NSObjectProtocol?
    
    // Event-driven proximity tracking
    private var proximityWakeWindow: ProximityWakeWindow?   // notch-edge / approach (open trigger)
    private var islandOpenMousePollTimer: DispatchSourceTimer?
    private var approachWorkItem: DispatchWorkItem?
    private var cachePurgeWorkItem: DispatchWorkItem?
    private var boxDragHoldWorkItem: DispatchWorkItem?
    private var isDraggingOverProximity = false
    private var lastApproachProgressSampleTime: TimeInterval = 0
    private var lastApproachProgressEmitted: CGFloat = -1
    private var lastPanelExpandedAt: TimeInterval = 0
    private var panelVisibilityEpoch: UInt64 = 0
    
    // Wiggle & Slim Box positioning tracking
    var dragWiggleAccumulator: CGFloat = 0
    var lastDragPoint: NSPoint?
    var lastDragTime: TimeInterval = 0
    var slimBoxOpenPosition: NSPoint?
    private var lastDxSign = 0
    private var lastDySign = 0
    private var directionChanges = 0
    private var lastDirectionChangeTime: TimeInterval = 0
    
    // Dynamic structural dimensions
    private var notchWidth: CGFloat = 210
    private var notchHeight: CGFloat = 32
    private var panelWidth: CGFloat = 380
    private var panelHeight: CGFloat = 160
    
    // Proximity variables
    private let activationYBuffer: CGFloat = 80
    private let exactTriggerPadding: CGFloat = 20
    private let approachProgressUpdateInterval: TimeInterval = 1.0 / 30.0
    private let approachProgressDeltaThreshold: CGFloat = 0.02
    private let idleCompactionDelay: TimeInterval = 1.5 // Lowered to immediately dump memory after Island closes
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }
        
        NSApp.setActivationPolicy(.accessory)
        
        calculateScreenNotchDimensions()
        let initialRaw = settings.reopenLastPage ? settings.lastVisitedPage : settings.defaultPage
        let initialPage = IslandPage(rawValue: initialRaw) ?? .clipboard
        model.currentPage = activePages.firstIndex(of: initialPage) ?? 0
        setupNotchWindow()
        setupBatteryWindow()
        setupStatusItem()
        observeSettings()
        startMemoryPressureMonitoring()
        startGlobalProximityTracking()
        startGlobalDragPolling()
        startBackgroundStateTracking()
        DevicePopupManager.shared.start()
        model.clipboardItems = loadClipboardHistory()
        model.jotNotes = loadJotNotes()
        model.launcherApps = loadLauncherApps()
        model.bookmarkItems = loadBookmarkItems()
        refreshChunkedClipboard()
        normalizeClipboardDirectoryFlagsIfNeeded()
        applyClipboardLimitIfNeeded()
        persistClipboardHistory(model.clipboardItems)
        persistJotNotes(model.jotNotes)
        persistLauncherApps(model.launcherApps)
        persistBookmarkItems(model.bookmarkItems)
        refreshNativeState()
        
        // Bind back decoupled settings data events
        NotificationCenter.default.addObserver(forName: NSNotification.Name("apolloDataChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.model.launcherApps = loadLauncherApps()
            self?.model.bookmarkItems = loadBookmarkItems()
        }
    }
    
    private func acquireSingleInstanceLock() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        return singleInstanceLock.acquire(bundleIdentifier: bundleIdentifier)
    }
    
    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let runningInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) else {
            return
        }
        runningInstance.activate(options: [])
    }
    
    func refreshChunkedClipboard() {
        let items = model.clipboardItems
        let columns = max(1, settings.clipboardColumns)
        Task.detached(priority: .userInitiated) {
            var chunkedRows: [[ClipboardEntry]] = []
            for i in stride(from: 0, to: items.count, by: columns) {
                let end = min(i + columns, items.count)
                chunkedRows.append(Array(items[i..<end]))
            }
            let finalChunked = chunkedRows
            await MainActor.run { [weak self] in
                self?.model.chunkedClipboardRows = finalChunked
            }
        }
    }
    
    private func normalizeClipboardDirectoryFlagsIfNeeded() {
        let entries = model.clipboardItems
        guard entries.contains(where: { entry in
            entry.text != nil && !entry.filePaths.isEmpty
            || entry.fileNames?.count != entry.filePaths.count
            || entry.fileSymbols?.count != entry.filePaths.count
            || entry.isDirectoryFlags == nil && !entry.filePaths.isEmpty
        }) else { return }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let normalizedEntries = entries.map { entry -> ClipboardEntry in
                var updated = entry
                if updated.isDirectoryFlags == nil, !updated.filePaths.isEmpty {
                    var flags: [String: Bool] = [:]
                    for path in entry.filePaths {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                            flags[path] = isDir.boolValue
                        } else {
                            flags[path] = false
                        }
                    }
                    updated.isDirectoryFlags = flags
                }
                return updated.normalizedForLightweightStorage()
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.model.clipboardItems.map(\.id) == entries.map(\.id) else { return }
                self.model.clipboardItems = normalizedEntries
                persistClipboardHistory(normalizedEntries)
                self.refreshChunkedClipboard()
            }
        }
    }
    
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Apollo")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        item.menu = makeStatusMenu()
        statusItem = item
    }
    
    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Island", action: #selector(showNotchFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pin Island", action: #selector(togglePinnedState), keyEquivalent: ""))
        let settingsItem = NSMenuItem()
        settingsItem.view = NSHostingView(rootView: SettingsLink {
            Text("Settings...")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
        })
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }
    
    @objc private func statusItemClicked(_ sender: Any?) {
        togglePinnedState()
    }
    
    @objc private func showNotchFromMenu() {
        showPanel(expanded: true, pinned: true)
    }
    
    @objc private func togglePinnedState() {
        model.isPinned.toggle()
        if model.isPinned {
            showPanel(expanded: true, pinned: true)
        } else if !model.isExpanded {
            hidePanel()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func calculateScreenNotchDimensions() {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
        cachedScreenFrame = screen?.frame ?? .zero
        let (x, width, height) = hardwareNotchDimensions(for: screen)
        settings.updateHardwareNotchDimensions(x: x, width: width, height: height)
        applySettingsNotchSize()
        updateBatteryWindowFrame()
    }
    
    private func applySettingsNotchSize() {
        notchWidth = settings.effectiveNotchWidth
        notchHeight = settings.effectiveNotchHeight
        panelWidth = scaledPanelWidth(for: settings)
        panelHeight = scaledPanelHeight(for: settings)
    }
    
    private func observeSettings() {
        settings.$notchWidth
            .combineLatest(settings.$notchHeight)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applySettingsNotchSize()
                self.updateNotchWindowFrame()
                self.updateProximityWakeWindowFrame()
                self.previewNotchResize()
            }
            .store(in: &settingsCancellables)
        
        Publishers.MergeMany(
            settings.$enableApproach.map { _ in () }.eraseToAnyPublisher(),
            settings.$alwaysUseApproachWhenDraggingFile.map { _ in () }.eraseToAnyPublisher(),
            settings.$approachWidth.map { _ in () }.eraseToAnyPublisher(),
            settings.$approachHeight.map { _ in () }.eraseToAnyPublisher(),
            settings.$notchEdgeThickness.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            self?.updateProximityWakeWindowFrame()
        }
        .store(in: &settingsCancellables)
        
        settings.$rememberClips
            .sink { [weak self] limit in
                guard let self else { return }
                self.applyClipboardLimitIfNeeded()
                persistClipboardHistory(self.model.clipboardItems)
                self.refreshChunkedClipboard()
                
                if limit == 0 {
                    self.stopClipboardObservation()
                } else {
                    self.updateClipboardObservationMode(immediatePoll: true)
                }
            }
            .store(in: &settingsCancellables)
        
        settings.$clipboardColumns
            .sink { [weak self] _ in
                self?.refreshChunkedClipboard()
            }
            .store(in: &settingsCancellables)
        
        settings.$defaultPage
            .sink { [weak self] rawPage in
                guard let self, !self.model.isExpanded, !self.settings.reopenLastPage else { return }
                let page = IslandPage(rawValue: rawPage) ?? .clipboard
                if let idx = self.activePages.firstIndex(of: page) {
                    self.model.currentPage = idx
                }
            }
            .store(in: &settingsCancellables)
        
        model.$currentPage
            .sink { [weak self] pageIndex in
                guard let self = self else { return }
                let pages = self.activePages
                if pages.indices.contains(pageIndex) {
                    self.settings.lastVisitedPage = pages[pageIndex].rawValue
                }
            }
            .store(in: &settingsCancellables)
        
        settings.$customActionsLayoutOption
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    let count = self.activePages.count
                    if self.model.currentPage >= count {
                        self.model.currentPage = count - 1
                    }
                }
            }
            .store(in: &settingsCancellables)
        
        settings.$observedFolders
            .sink { [weak self] folders in
                self?.configureFolderMonitors(with: folders)
            }
            .store(in: &settingsCancellables)
        
        model.$boxFiles
            .receive(on: RunLoop.main)
            .sink { [weak self] files in
                let urls = files.map(\.url)
                if urls.isEmpty {
                    BoxIconCache.shared.removeAll()
                } else {
                    BoxIconCache.shared.trim(keeping: urls)
                }
                
                guard let self = self else { return }
                if files.count <= 1 {
                    self.model.isSlimBoxCollapsed = false
                }
                if self.model.boxSlimModeActive {
                    if files.isEmpty {
                        self.hideSlimBox()
                    } else {
                        self.updateSlimBoxWindowFrame(files: files)
                    }
                }
            }
            .store(in: &settingsCancellables)
        
        model.$jotNotes
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { notes in
                persistJotNotes(notes)
            }
            .store(in: &settingsCancellables)
        
        model.$launcherApps
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { apps in
                persistLauncherApps(apps)
            }
            .store(in: &settingsCancellables)
        
        model.$bookmarkItems
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { bookmarks in
                persistBookmarkItems(bookmarks)
            }
            .store(in: &settingsCancellables)
        
        settings.$hoverPreviewFocus
            .sink { [weak self] focus in
                guard let self else { return }
                if focus == .all {
                    if !self.model.isExpanded && !self.model.isPinned {
                        self.hidePanel()
                    }
                } else {
                    self.showSettingsPreview()
                }
                self.updateClipboardObservationMode(immediatePoll: focus != .all)
            }
            .store(in: &settingsCancellables)
        
        // Issue 6: When a popover or share sheet is dismissed, immediately check
        // whether the cursor is still inside the island. This gives a natural
        // close-after-dismiss feel without waiting for the next 400ms poll tick.
        model.$isAddSheetOpen
            .sink { [weak self] open in
                guard let self, !open else { return }
                self.handleIslandOpenMousePollTick()
            }
            .store(in: &settingsCancellables)
        
        // Issue 1: React to enable-flag changes
        Publishers.MergeMany(
            settings.$clipEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$jotEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$boxEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$chronoEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$calendarEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$launcherEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$bookmarksEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$pagerStyle2BackgroundEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$pageOrder.map { _ in () }.eraseToAnyPublisher(),
            settings.$openMethod.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            guard let self else { return }
            self.updateActivePages()
            
            if !self.settings.clipEnabled {
                self.stopClipboardObservation()
            } else {
                self.updateClipboardObservationMode(immediatePoll: true)
            }
            
            if !self.settings.boxEnabled {
                self.configureFolderMonitors(with: [])
            } else {
                self.configureFolderMonitors(with: self.settings.observedFolders)
            }
        }
        .store(in: &settingsCancellables)
        
        Publishers.CombineLatest4(
            model.$isExpanded,
            model.$isPinned,
            model.$expansionProgress,
            model.$isAddSheetOpen
        )
        .combineLatest(model.$observedFileToast)
        .sink { [weak self] _ in
            self?.updateContentActiveState()
        }
        .store(in: &settingsCancellables)
        
        settings.$boxSlimModeEnabled
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    // Pass `enabled` directly – @Published fires during willSet so the
                    // property itself still holds the old value at this point.
                    self.startGlobalDragPolling(forceEnabled: true)
                } else {
                self.dragPollingTimer?.cancel()
                self.dragPollingTimer = nil
                    self.stopFastDragTracking()
                    self.resetDragTrackingState()
                    self.hideSlimBox()
                }
            }
            .store(in: &settingsCancellables)
            
        Publishers.CombineLatest3(
            model.$isStopwatchRunning,
            model.$isTimerRunning,
            settings.$disableChronoHUD
        )
        .sink { [weak self] isStopwatch, isTimer, disableHUD in
            let needsActivity = (isStopwatch || isTimer) && !disableHUD
            if needsActivity && self?.chronoActivity == nil {
                self?.chronoActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Chrono HUD Active")
            } else if !needsActivity && self?.chronoActivity != nil {
                if let activity = self?.chronoActivity { ProcessInfo.processInfo.endActivity(activity) }
                self?.chronoActivity = nil
            }
        }
            .store(in: &settingsCancellables)
    }
    
    private func updateContentActiveState() {
        let shouldBeActive: Bool
        if model.isExpanded || model.isPinned || model.boxSlimModeActive || (model.expansionProgress > 0) || model.observedFileToast != nil || model.isAddSheetOpen {
            shouldBeActive = true
        } else {
            let isHovered: Bool
            if cachedScreenFrame != .zero {
                let pt = NSEvent.mouseLocation
                let zones = makeProximityZones(screenRect: cachedScreenFrame, point: pt, isFileDrag: false)
                isHovered = zones.isInsideNotch || zones.isHoveringEdge || zones.approachRect.contains(pt)
            } else {
                isHovered = false
            }
            shouldBeActive = isHovered
        }
        
        
        let wasActive = model.isContentActive
        if wasActive != shouldBeActive {
            model.isContentActive = shouldBeActive
            if shouldBeActive {
                self.cachePurgeWorkItem?.cancel()
                self.cachePurgeWorkItem = nil
            } else {
                self.cachePurgeWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.purgeCachesForMemoryPressure()
                    BoxIconCache.shared.removeAll()
                    AppIconCache.shared.clear()
                    BookmarkIconCache.shared.clear()
                }
                self.cachePurgeWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            }
        }
    }
    
    var activePages: [IslandPage] {
        if settings.boxEnabled && model.boxSlimModeActive {
            return [.box]
        }
        var pages: [IslandPage] = []
        for pageInt in settings.pageOrder {
            guard let basePage = IslandPage(rawValue: pageInt) else { continue }
            switch basePage {
            case .clipboard:
                if settings.clipEnabled { pages.append(.clipboard) }
            case .jot:
                if settings.jotEnabled { pages.append(.jot) }
            case .box:
                if settings.boxEnabled { pages.append(.box) }
            case .chrono:
                if settings.chronoEnabled { pages.append(.chrono) }
            case .calendar:
                if settings.calendarEnabled { pages.append(.calendar) }
            case .launcher:
                if settings.launcherEnabled {
                    if settings.customActionsLayoutOption == 0 {
                        if !pages.contains(.customCombined) {
                            pages.append(.customCombined)
                        }
                    } else {
                        pages.append(.launcher)
                    }
                }
            case .bookmarks:
                if settings.bookmarksEnabled {
                    if settings.customActionsLayoutOption == 0 {
                        if !pages.contains(.customCombined) {
                            pages.append(.customCombined)
                        }
                    } else {
                        pages.append(.bookmarks)
                    }
                }
            default:
                break
            }
        }
        if pages.isEmpty {
            pages = [.clipboard]
        }
        return pages
    }
    
    private func updateActivePages() {
        let count = activePages.count
        if model.currentPage >= count {
            model.currentPage = max(0, count - 1)
        }
        updateProximityWakeWindowFrame()
    }
    
    
    private func startMemoryPressureMonitoring() {
        guard memoryPressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self] in
            self?.purgeCachesForMemoryPressure()
        }
        source.resume()
        memoryPressureSource = source
    }
    
    private func purgeCachesForMemoryPressure() {
        let urls = model.boxFiles.map(\.url)
        if urls.isEmpty {
            BoxIconCache.shared.removeAll()
        } else {
            BoxIconCache.shared.trim(keeping: urls)
        }
        AppIconCache.shared.clear()
        BookmarkIconCache.shared.clear()
    }
    
    private func showSettingsPreview() {
        guard let window = islandWindow else { return }
        cancelIdleCompaction()
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
        model.isExpanded = false
        model.isPinned = false
        model.expansionProgress = 0.0
        model.closeGestureProgress = 0
        SwipeState.shared.carouselDragOffset = 0
        updateNotchWindowFrame(heightOverride: panelHeight)
        window.alphaValue = 1.0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        updateClipboardObservationMode(immediatePoll: true)
    }
    
    private func notchTopAnchorY(for screen: NSScreen) -> CGFloat {
        screen.frame.maxY
    }
    
    private func updateNotchWindowFrame(widthOverride: CGFloat? = nil, heightOverride: CGFloat? = nil) {
        guard let window = notchWindow, cachedScreenFrame != .zero else { return }
        let screenRect = cachedScreenFrame
        let defaultWidth = max(panelWidth, notchWidth + 240)
        let windowWidth = widthOverride ?? defaultWidth
        let windowHeight = heightOverride ?? window.frame.height
        
        // Correct window positioning: Center the window's midpoint on the hardware notch's midpoint
        let notchX = settings.hardwareNotchX
        let notchWidth = settings.effectiveNotchWidth
        let windowX = notchX - (windowWidth - notchWidth) / 2
        let windowY = screenRect.maxY - windowHeight
        
        let newFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        let current = window.frame
        if abs(current.origin.x - newFrame.origin.x) < 1.0,
           abs(current.origin.y - newFrame.origin.y) < 1.0,
           abs(current.size.width - newFrame.size.width) < 1.0,
           abs(current.size.height - newFrame.size.height) < 1.0 {
            window.level = .statusBar + 2
            return
        }
        window.setFrame(newFrame, display: true)
        window.level = .statusBar + 2
    }
    
    private func previewNotchResize() {
        notchPreviewWorkItem?.cancel()
        notchPreviewWorkItem = nil
        
        if model.isPinned {
            showPanel(expanded: true, pinned: true)
            return
        }
        
        showPanel(expanded: true, pinned: false)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isPinned else { return }
            self.hidePanel()
        }
        notchPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
    
    private let scrollBottomTolerance: CGFloat = 24
    
    func isCurrentPageAtBottom() -> Bool {
        guard model.isExpanded, !model.isPinned else { return false }
        guard let window = islandWindow else { return true }
        guard let scrollView = window.contentView?.findScrollView() else {
            // If there's no scroll view, it's always ready to close.
            return true
        }
        guard let documentView = scrollView.documentView else { return true }
        let visibleRect = scrollView.documentVisibleRect
        let contentHeight = documentView.frame.height
        let viewportHeight = visibleRect.height
        
        // If content is shorter than the viewport, it's always at the bottom!
        if contentHeight <= viewportHeight { return true }
        
        return visibleRect.maxY >= (contentHeight - scrollBottomTolerance)
    }
    
    private func setupNotchWindow() {
        guard cachedScreenFrame != .zero else { return }
        let screenRect = cachedScreenFrame
        let windowWidth = max(panelWidth, notchWidth + 240)
        let windowHeight = settings.effectiveNotchHeight
        
        let notchX = settings.hardwareNotchX
        let notchWidthActual = settings.effectiveNotchWidth
        let windowX = notchX - (windowWidth - notchWidthActual) / 2
        let windowY = screenRect.maxY - settings.effectiveNotchHeight
        
        let initialRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        islandWindow = IslandPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        notchWindow.backgroundColor = .clear
        notchWindow.isOpaque = false
        notchWindow.hasShadow = false
        notchWindow.level = .statusBar + 2
        notchWindow.alphaValue = 0.0
        notchWindow.ignoresMouseEvents = true
        notchWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        notchWindow.setAccessibilityElement(false)
        notchWindow.setAccessibilityRole(.none)
        
        notchWindow.isActiveProvider = { [weak self] in
            guard let self else { return false }
            return self.model.isExpanded || self.model.isPinned
        }
        notchWindow.canTriggerVertical = { [weak self] in
            self?.isCurrentPageAtBottom() ?? false
        }
        notchWindow.onSwipeLeft = { [weak self] in
            self?.advancePage(direction: 1)
        }
        notchWindow.onSwipeRight = { [weak self] in
            self?.advancePage(direction: -1)
        }
        notchWindow.onSwipeUp = { [weak self] in
            self?.closeNotchFromSwipe()
        }
        notchWindow.onCloseProgressLegacy = { [weak self] progress, animate in
            guard let self else { return }
            let clamped = max(0, min(1, progress))
            if abs(self.lastCloseProgressEmission - clamped) < 0.02 {
                return
            }
            self.lastCloseProgressEmission = clamped
            if animate {
                if clamped == 0 {
                    withAnimation(.easeOut(duration: 0.05)) {
                        self.model.closeGestureProgress = clamped
                    }
                } else {
                    withAnimation(self.settings.swipeAnimation) {
                        self.model.closeGestureProgress = clamped
                    }
                }
            } else {
                self.model.closeGestureProgress = clamped
            }
        }
        notchWindow.onCarouselOffset = { [weak self] offset, animate in
            guard let self else { return }
            if abs(self.lastCarouselOffsetEmission - offset) < (animate ? 0.01 : 0.6) {
                return
            }
            self.lastCarouselOffsetEmission = offset
            
            if offset != 0 {
                self.stopClipboardObservation()
            } else {
                self.updateClipboardObservationMode()
            }
            
            if animate {
                withAnimation(self.settings.carouselAnimation) {
                    SwipeState.shared.carouselDragOffset = offset
                }
            } else {
                SwipeState.shared.carouselDragOffset = offset
            }
        }
        notchWindow.carouselSensitivityProvider = { [weak self] in
            self?.settings.clampedCarouselSensitivity ?? 1.0
        }
        notchWindow.closeSensitivityProvider = { [weak self] in
            self?.settings.clampedCloseSensitivity ?? 1.0
        }
        notchWindow.isAtFirstPageProvider = { [weak self] in
            self?.model.currentPage == 0
        }
        notchWindow.isAtLastPageProvider = { [weak self] in
            guard let self else { return true }
            return self.model.currentPage >= self.activePages.count - 1
        }
        notchWindow.panelWidthProvider = { [weak self] in
            guard let self else { return 300 }
            return scaledPanelWidth(for: self.settings)
        }
        notchWindow.isTapToOpenProvider = { [weak self] in
            self?.settings.openMethod == 1
        }
        notchWindow.isExpandedProvider = { [weak self] in
            self?.model.isExpanded ?? false
        }
        notchWindow.onTapToOpen = { [weak self] in
            self?.showPanel(expanded: true, pinned: false)
        }
        notchWindow.needsKeyFocusProvider = { [weak self] in
            guard let self else { return false }
            if self.model.isAddSheetOpen { return true }
            let pages = self.activePages
            if pages.indices.contains(self.model.currentPage) {
                if pages[self.model.currentPage] == .jot {
                    return true
                }
            }
            return false
        }
        
        let rootHubView = UnifiedNotchContainer(model: model, settings: settings)
            .onPreferenceChange(UnifiedNotchContainer.ShellHeightKey.self) { [weak self] newHeight in
                guard let self else { return }
                self.scheduleWindowFrameUpdate(for: newHeight)
            }
        
        let hostingView = IslandHostingView(rootView: rootHubView)
        hostingView.sizingOptions = []
        if #available(macOS 11.0, *) {
            hostingView.safeAreaRegions = []
        }
        hostingView.isPointInteractive = { [weak self] point in
            guard let self = self else { return true }
            if self.model.isExpanded || self.model.isPinned {
                return true
            }
            let windowWidth = self.notchWindow.frame.width
            let windowHeight = self.notchWindow.frame.height
            if self.model.observedFileToast != nil || self.model.isToastDismissing {
                let toastWidth: CGFloat = 180
                let toastHeight: CGFloat = 260
                let toastRect = NSRect(
                    x: (windowWidth - toastWidth) / 2,
                    y: windowHeight - toastHeight,
                    width: toastWidth,
                    height: toastHeight
                )
                return toastRect.contains(point)
            }
            let notchWidth = self.settings.effectiveNotchWidth
            let notchHeight = self.settings.effectiveNotchHeight
            let slop: CGFloat = 20
            let notchRect = NSRect(
                x: (windowWidth - notchWidth) / 2 - slop,
                y: windowHeight - notchHeight - slop,
                width: notchWidth + (slop * 2),
                height: notchHeight + slop
            )
            return notchRect.contains(point)
        }
        notchWindow.contentView = hostingView
        // Don't order front at startup — window will be ordered front on first show.
        // Keeping it ordered out eliminates all NSTrackingArea and SwiftUI hover
        // events while the panel is idle, preventing CPU usage from cursor movement.
    }
    
    private func advancePage(direction: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let activePagesCount = self.activePages.count
            let next = clamp(self.model.currentPage + direction, min: 0, max: activePagesCount - 1)
            withAnimation(self.settings.carouselAnimation) {
                SwipeState.shared.carouselDragOffset = 0
                self.model.currentPage = next
            }
        }
    }
    
    private func startBackgroundStateTracking() {
        if settings.rememberClips > 0 {
            startClipboardObservation()
        }
    }
    
    private func startClipboardObservation() {
        updateClipboardObservationMode(immediatePoll: true)
    }
    
    private func shouldKeepClipboardTimerRunning() -> Bool {
        return settings.clipEnabled && settings.rememberClips > 0
    }
    
    private func updateClipboardObservationMode(immediatePoll: Bool = false) {
        let shouldPollActively = shouldKeepClipboardTimerRunning()
        if shouldPollActively {
            startClipboardMonitorTaskIfNeeded()
            if immediatePoll {
                pollClipboardFromPasteboard(force: false)
            }
        } else {
            stopClipboardObservation()
        }
    }
    
    private func startClipboardMonitorTaskIfNeeded() {
        guard settings.rememberClips > 0 else { return }
        guard clipboardMonitorTask == nil else { return }
        
        clipboardMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let currentCount = NSPasteboard.general.changeCount
                if currentCount != self.lastClipboardChangeCount {
                    self.pollClipboardFromPasteboard(force: false)
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }
    
    private func stopClipboardObservation() {
        clipboardMonitorTask?.cancel()
        clipboardMonitorTask = nil
    }
    
    func updateObservationState(for pageIndex: Int) {
        let pages = activePages
        guard pages.indices.contains(pageIndex) else { return }
        updateClipboardObservationMode(immediatePoll: pages[pageIndex] == .clipboard)
    }
    
    private func refreshNativeState() {
        pollClipboardFromPasteboard(force: true)
    }
    
    private func pollClipboardFromPasteboard(force: Bool = false) {
            autoreleasepool {
                let pasteboard = NSPasteboard.general
                let currentChangeCount = pasteboard.changeCount
                let isNewChange = currentChangeCount != lastClipboardChangeCount
                guard force || isNewChange else { return }
                
                // Privacy-Safe Metadata Discovery: Inspect types before reading payload
                let availableTypes = pasteboard.types ?? []
                let hasFileURLs = availableTypes.contains(.fileURL) || availableTypes.contains(NSPasteboard.PasteboardType("public.file-url")) || availableTypes.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
                let hasString = availableTypes.contains(.string)
                
                var fileURLs: [URL] = []
                var trimmedText: String? = nil
                
                if hasFileURLs {
                    fileURLs = (pasteboard.readObjects(
                        forClasses: [NSURL.self],
                        options: [.urlReadingFileURLsOnly: true]
                    ) as? [URL] ?? [])
                    .filter(\.isFileURL)
                }
                
                if fileURLs.isEmpty && hasString {
                    trimmedText = cappedClipboardText(pasteboard.string(forType: .string))
                }
                
                if (trimmedText?.isEmpty == false) || !fileURLs.isEmpty {
                    lastClipboardChangeCount = currentChangeCount
                    
                    Task.detached(priority: .utility) { [weak self] in
                        let entry = ClipboardEntry(text: trimmedText, fileURLs: fileURLs).normalizedForLightweightStorage()
                        await MainActor.run {
                            guard let self else { return }
                            guard self.model.clipboardItems.first?.signature != entry.signature else { return }
                            
                            self.model.clipboardItems.removeAll { $0.signature == entry.signature }
                            self.model.clipboardItems.insert(entry, at: 0)
                            self.applyClipboardLimitIfNeeded()
                            persistClipboardHistory(self.model.clipboardItems)
                            self.refreshChunkedClipboard()
                        }
                    }
                } else {
                    if isNewChange && currentChangeCount != lastRetryChangeCount {
                        lastRetryChangeCount = currentChangeCount
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            self?.pollClipboardFromPasteboard(force: true)
                        }
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            self?.pollClipboardFromPasteboard(force: true)
                        }
                    }
                    if !isNewChange {
                        lastClipboardChangeCount = currentChangeCount
                    }
                }
            }
        }
        
        func copyClipboardEntry(_ entry: ClipboardEntry) {
            let entry = entry.normalizedForLightweightStorage()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if entry.hasText {
                pasteboard.setString(entry.normalizedText, forType: .string)
            }
            if entry.hasFiles {
                _ = pasteboard.writeObjects(entry.fileURLs as [NSURL])
            }
            model.clipboardPulseItemID = entry.id
            model.clipboardItems.removeAll { $0.signature == entry.signature }
            model.clipboardItems.insert(entry, at: 0)
            applyClipboardLimitIfNeeded()
            persistClipboardHistory(model.clipboardItems)
            refreshChunkedClipboard()
        }
        
        func clearClipboardHistory() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            lastClipboardChangeCount = pasteboard.changeCount
            model.clipboardItems.removeAll()
            model.chunkedClipboardRows.removeAll()
            model.clipboardPulseItemID = nil
            persistClipboardHistory(model.clipboardItems)
            refreshChunkedClipboard()
        }
        
        private func applyClipboardLimitIfNeeded() {
            guard let limit = settings.effectiveRememberClips else { return }
            if model.clipboardItems.count > limit {
                model.clipboardItems = Array(model.clipboardItems.prefix(limit))
                refreshChunkedClipboard()
            }
        }
        
        func addBoxItems(from urls: [URL]) {
            guard !urls.isEmpty else { return }
            for url in urls.reversed() {
                if !model.boxFiles.contains(where: { $0.url == url }) {
                    model.boxFiles.insert(BoxFile(url: url), at: 0)
                }
            }
            showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
        }
        
        func openBoxPage() {
            showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
        }
        
        func closeNotchFromSwipe() {
            guard !model.isPinned else { return }
            // Issue 4b: Only suppress proximity if the cursor is currently over the notch zone.
            // Suppressing unconditionally blocks re-open when the cursor is already far away.
            if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first {
                let pt = NSEvent.mouseLocation
                let zones = makeProximityZones(screenRect: screen.frame, point: pt, isFileDrag: false)
                suppressProximityUntilExit = zones.isInsideNotch || zones.isHoveringEdge
            } else {
                suppressProximityUntilExit = true
            }
            swipeCloseWorkItem?.cancel()
            swipeCloseWorkItem = nil
            let delay = settings.swipeCloseDelay
            if delay <= 0 {
                hidePanel()
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                self?.hidePanel()
            }
            swipeCloseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
        
        private func startGlobalProximityTracking() {
            setupProximityWakeWindow()
            updateProximityWakeWindowFrame()
        }
        
        private func setupProximityWakeWindow() {
            guard proximityWakeWindow == nil else { return }
            let wake = ProximityWakeWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            wake.isOpaque = false
            wake.backgroundColor = .clear
            wake.hasShadow = false
            wake.level = .statusBar + 1
            wake.alphaValue = 0.001
            wake.ignoresMouseEvents = false
            wake.acceptsMouseMovedEvents = true
            wake.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            wake.setAccessibilityElement(false)
            wake.setAccessibilityRole(.none)
            wake.hidesOnDeactivate = false
            wake.onMouseEntered = { [weak self] in self?.handleProximityWakeEntered() }
            wake.onMouseExited = { [weak self] in self?.handleProximityWakeExited() }
            wake.onApproachMouseMoved = { [weak self] pt in self?.handleProximityApproachMouseMoved(to: pt) }
            wake.onDraggingEntered = { [weak self] in self?.handleProximityDraggingEntered() }
            wake.onDraggingUpdated = { [weak self] pt in self?.handleProximityDraggingUpdated(to: pt) }
            wake.onDraggingExited = { [weak self] in self?.handleProximityDraggingExited() }
            wake.isTapToOpenEnabled = { [weak self] in
                self?.settings.openMethod == 1
            }
            wake.onTapToOpen = { [weak self] in
                self?.showPanel(expanded: true, pinned: false)
            }
            wake.orderFrontRegardless()
            proximityWakeWindow = wake
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScreenParametersChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        }
        
        @objc private func handleScreenParametersChanged() {
            calculateScreenNotchDimensions()
            updateNotchWindowFrame()
            updateProximityWakeWindowFrame()
        }
        
        private func updateProximityWakeWindowFrame() {
            guard let wake = proximityWakeWindow,
                  cachedScreenFrame != .zero else { return }
            let screenRect = cachedScreenFrame
            
            // proximityWakeWindow tracks notch edge + approach zone while island is closed.
            let shouldWakeTrackCursor =
            !model.isExpanded &&
            !model.isPinned &&
            !model.boxSlimModeActive &&
            model.observedFileToast == nil &&
            !(settings.showHoverPreviews && settings.hoverPreviewFocus != .all)
            guard shouldWakeTrackCursor else {
                resetApproachProgressSampling()
                wake.orderOut(nil)
                if !model.isExpanded && !model.isPinned, let window = notchWindow, window.alphaValue < 0.05 {
                    updateNotchWindowFrame(heightOverride: settings.effectiveNotchHeight)
                }
                return
            }
            // Cursor is approaching the notch; reset the suppression flag so hover-to-open works.
            suppressProximityUntilExit = false
            let edge = settings.clampedNotchEdgeThickness
            let edgeNotchWidth = settings.effectiveNotchWidth
            let edgeNotchHeight = settings.effectiveNotchHeight
            let edgeNotchLeft = settings.hardwareNotchX
            let edgeNotchRect = CGRect(
                x: edgeNotchLeft,
                y: screenRect.maxY - edgeNotchHeight,
                width: edgeNotchWidth,
                height: edgeNotchHeight
            ).insetBy(dx: -edge, dy: -edge)
            
            let approachScale: CGFloat = settings.alwaysUseApproachWhenDraggingFile ? 2.0 : 1.0
            let isApproachEnabled = settings.enableApproach && settings.openMethod != 1
            let approachWidth = isApproachEnabled ? settings.clampedApproachWidth * approachScale : 0
            let approachHeight = isApproachEnabled ? settings.clampedApproachHeight * approachScale : 0

            let cushion: CGFloat = 6
            let approachRect = CGRect(
                x: edgeNotchRect.minX - approachWidth,
                y: edgeNotchRect.minY - approachHeight,
                width: edgeNotchRect.width + (approachWidth * 2),
                height: approachHeight
            )
            
            let totalHeight = edgeNotchRect.height + approachHeight + cushion
            let totalWidth = edgeNotchRect.width + approachWidth * 2
            let originX = edgeNotchRect.minX - approachWidth
            let originY = screenRect.maxY - totalHeight
            wake.setFrame(NSRect(x: originX, y: originY, width: totalWidth, height: totalHeight), display: false)
            if !wake.isVisible {
                wake.orderFrontRegardless()
            }
            wake.updateTrackingGeometry(
                notchEdgeRect: edgeNotchRect.offsetBy(dx: -originX, dy: -originY),
                approachRect: approachRect.offsetBy(dx: -originX, dy: -originY)
            )
            
            // If tracking geometry moves under a stationary cursor, AppKit may not
            // emit mouseEntered. Keep activation state in sync, but do not force
            // open from here so hover-open uses the same mouseEntered path.
            let cursor = NSEvent.mouseLocation
            if edgeNotchRect.contains(cursor) {
                setActivationZoneState(true)
            }
        }
        
        private func handleProximityWakeEntered() {
            updateContentActiveState()
            guard !suppressProximityUntilExit else { return }
            // Only the notch-edge/notch itself should count as activation.
            // Entering approach alone should progressively expand, not open.
            let point = NSEvent.mouseLocation
            if cachedScreenFrame != .zero {
                let zones = makeProximityZones(screenRect: cachedScreenFrame, point: point, isFileDrag: false)
                setActivationZoneState(zones.isInsideNotch || zones.isHoveringEdge)
                if zones.isInsideNotch || zones.isHoveringEdge {
                    if settings.openMethod == 0 {
                        showPanel(expanded: true, pinned: false)
                    }
                }
            } else {
                setActivationZoneState(false)
            }
            // Evaluate cursor when tracking areas are entered so approach progress
            // updates immediately, but open only occurs at notch-edge/notch.
            evaluateMouseCoordinates(point, isFileDrag: false)
        }
        
        private func handleProximityWakeExited() {
            suppressProximityUntilExit = false
            resetApproachProgressSampling()
            setActivationZoneState(false)
            if !model.isExpanded && !model.isPinned {
                withAnimation(.easeOut(duration: 0.15)) {
                    model.expansionProgress = 0.0
                }
                if notchWindow?.ignoresMouseEvents == false {
                    notchWindow?.ignoresMouseEvents = true
                }
            }
            updateContentActiveState()
        }
        
        private func handleProximityApproachMouseMoved(to point: NSPoint) {
            updateContentActiveState()
            guard !suppressProximityUntilExit, !model.isExpanded, !model.isPinned else { return }
            evaluateMouseCoordinates(point, isFileDrag: false)
        }
        
        private func setActivationZoneState(_ isInside: Bool) {
            guard isCursorInActivationZone != isInside else { return }
            isCursorInActivationZone = isInside
            applyCursorPresenceState()
        }
        
        private func applyCursorPresenceState() {
            guard !model.isPinned else {
                hoverCloseWorkItem?.cancel()
                hoverCloseWorkItem = nil
                return
            }
            
            if model.isExpanded {
                hoverCloseWorkItem?.cancel()
                hoverCloseWorkItem = nil
                return
            }
            
            guard isCursorInActivationZone, !suppressProximityUntilExit else { return }
        }
        
        private func clearCursorPresenceState() {
            isCursorInActivationZone = false
        }
        
        private func handleLegacyProximityWakeExitedFallback() {
            approachWorkItem?.cancel()
            approachWorkItem = nil
            let globalPoint = NSEvent.mouseLocation
            let isWithinExpandedPanel = notchWindow?.frame.contains(globalPoint) ?? false
            if model.isExpanded {
                if !isWithinExpandedPanel {
                    scheduleHoverCloseIfNeeded()
                }
            } else if !model.isPinned && model.expansionProgress > 0 {
                withAnimation(settings.notchOpenAnimation) {
                    model.expansionProgress = 0
                }
                let checkWindow = notchWindow
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, !self.model.isExpanded, self.model.expansionProgress == 0 else { return }
                        let hasActiveChrono = (self.model.isStopwatchRunning || self.model.isTimerRunning) && !self.settings.disableChronoHUD
                    if !hasActiveChrono {
                        checkWindow?.alphaValue = 0.0
                        checkWindow?.ignoresMouseEvents = true
                        checkWindow?.orderOut(nil)
                    } else {
                        checkWindow?.alphaValue = 1.0
                        checkWindow?.ignoresMouseEvents = true
                    }
                }
            }
        }
        
        private func handleProximityDraggingEntered() {
            isDraggingOverProximity = true
            suppressProximityUntilExit = false
            evaluateMouseCoordinates(NSEvent.mouseLocation, isFileDrag: true)
        }
        
        private func handleProximityDraggingUpdated(to point: NSPoint) {
            evaluateMouseCoordinates(point, isFileDrag: true)
        }
        
        private func handleProximityDraggingExited() {
            isDraggingOverProximity = false
            boxDragHoldWorkItem?.cancel()
            boxDragHoldWorkItem = nil
            dragWiggleAccumulator = 0
            lastDragPoint = nil
            slimBoxOpenPosition = nil
            model.boxDragActive = false
            model.boxSlimModeActive = false
            handleLegacyProximityWakeExitedFallback()
        }
        
        // MARK: - Global Drag Polling & Separate Slim Box
        private func setupSlimBoxWindow() {
            guard slimBoxWindow == nil else { return }
            
            let windowWidth: CGFloat = CGFloat(settings.boxSlimModeWidth)
            let windowHeight: CGFloat = CGFloat(settings.boxSlimModeHeight)
            
            let initialRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
            let window = IslandPanel(
                contentRect: initialRect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .statusBar + 2
            window.alphaValue = 0.0
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setAccessibilityElement(false)
            window.setAccessibilityRole(.none)
            window.isMovableByWindowBackground = false
            window.isSlimWindowProvider = { return true }
            window.needsKeyFocusProvider = { return false }
            
            window.isActiveProvider = { return false }
            
            // AppKit-level close button handler — fires even when the app is inactive
            window.onCloseButtonTapped = { [weak self] in
                self?.hideSlimBox()
            }
            
            // AppKit-level collapse button handler — fires even when the app is inactive
            window.onCollapseButtonTapped = { [weak self] in
                guard let self = self, self.model.boxFiles.count > 1 else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self.model.isSlimBoxCollapsed.toggle()
                }
                DispatchQueue.main.async {
                    self.updateSlimBoxWindowFrame()
                }
            }
            
            window.isCloseButtonVisible = { [weak self] in
                guard let self = self else { return false }
                return !self.model.boxFiles.isEmpty && self.settings.boxSlimModeKeepOpen
            }
            
            window.isCollapseButtonVisible = { [weak self] in
                guard let self = self else { return false }
                return self.model.boxFiles.count > 1 && self.settings.boxSlimModeKeepOpen
            }
            
            let containerView = UnifiedNotchContainer(model: model, settings: settings, isSlimBoxInstance: true)
            let hostingView = IslandHostingView(rootView: containerView)
            hostingView.sizingOptions = []
            if #available(macOS 11.0, *) {
                hostingView.safeAreaRegions = []
            }
            window.contentView = hostingView
            
            slimBoxWindow = window
        }
        
        func updateSlimBoxWindowFrame(files: [BoxFile]? = nil) {
            guard let window = slimBoxWindow, cachedScreenFrame != .zero else { return }
            let screenRect = cachedScreenFrame
            
            let filesList = files ?? model.boxFiles
            let count = model.isSlimBoxCollapsed ? (filesList.isEmpty ? 0 : 1) : filesList.count
            let direction = settings.boxSlimModeExpandDirection // 0 = Horizontal, 1 = Vertical
            
            let itemSize: CGFloat = min(CGFloat(settings.boxSlimModeItemWidth), CGFloat(settings.boxSlimModeItemHeight))
            let maxItems = CGFloat(settings.boxSlimModeMaxViewSize)
            
            let padLeftRight: CGFloat = 24
            let padTopBottom: CGFloat = 24
            let spacing: CGFloat = 8
            let headerHeight: CGFloat = 40
            
            // Compute the max width/height based on the item size and max item settings
            var maxSlimWidth: CGFloat = 180
            var maxSlimHeight: CGFloat = 260
            
            if direction == 0 { // Horizontal
                let rawMaxW = padLeftRight + (itemSize * maxItems) + (spacing * (maxItems - 1)) + padLeftRight
                maxSlimWidth = max(180, rawMaxW)
                maxSlimHeight = itemSize + padTopBottom + padTopBottom + headerHeight
            } else { // Vertical
                maxSlimWidth = max(180, itemSize + padLeftRight + padLeftRight)
                let rawMaxH = headerHeight + padTopBottom + (itemSize * maxItems) + (spacing * (maxItems - 1)) + padTopBottom
                maxSlimHeight = max(180, rawMaxH)
            }
            
            var windowWidth: CGFloat = maxSlimWidth
            var windowHeight: CGFloat = maxSlimHeight
            
            if count == 0 {
                if direction == 0 {
                    windowWidth = 160
                    windowHeight = 90
                } else {
                    windowWidth = 120
                    windowHeight = 160
                }
            } else {
                if direction == 0 { // Horizontal expansion
                    // Height is fixed to the calculated height
                    windowHeight = maxSlimHeight
                    
                    // Width expands to fit current item count up to maxSlimWidth
                    let rawWidth = padLeftRight + (itemSize * CGFloat(count)) + (spacing * CGFloat(count - 1)) + padLeftRight
                    windowWidth = rawWidth
                    if windowWidth > maxSlimWidth { windowWidth = maxSlimWidth }
                    if windowWidth < 180 { windowWidth = 180 }
                } else { // Vertical expansion
                    // Width is fixed to the calculated width
                    windowWidth = maxSlimWidth
                    
                    // Height expands to fit current item count up to maxSlimHeight
                    let rawHeight = headerHeight + padTopBottom + (itemSize * CGFloat(count)) + (spacing * CGFloat(count - 1)) + padTopBottom
                    windowHeight = rawHeight
                    if windowHeight > maxSlimHeight { windowHeight = maxSlimHeight }
                    if windowHeight < 160 { windowHeight = 160 }
                }
            }
            
            var windowX: CGFloat = 0
            var windowY: CGFloat = 0
            
            if model.boxSlimModeActive && window.alphaValue > 0.1 {
                let currentFrame = window.frame
                windowX = currentFrame.midX - windowWidth / 2
                windowY = currentFrame.maxY - windowHeight
            } else if settings.boxSlimModePosition == 1, let openPos = slimBoxOpenPosition {
                windowX = openPos.x - windowWidth / 2
                // Fixed top positioning: top is at openPos.y + 40, growing downwards
                windowY = (openPos.y + 40) - windowHeight
            } else {
                // Default position centered under the notch
                let notchX = settings.hardwareNotchX
                let notchWidth = settings.effectiveNotchWidth
                windowX = notchX - (windowWidth - notchWidth) / 2
                // Fixed top positioning: top is at screenRect.maxY - 20, growing downwards
                windowY = screenRect.maxY - windowHeight - 20
            }
            
            // Clamp to screen bounds with 20px padding
            let screenMinX = screenRect.minX + 20
            let screenMaxX = screenRect.maxX - 20
            let screenMinY = screenRect.minY + 20
            let screenMaxY = screenRect.maxY - 20
            
            if windowX < screenMinX {
                windowX = screenMinX
            } else if windowX + windowWidth > screenMaxX {
                windowX = screenMaxX - windowWidth
            }
            
            if windowY < screenMinY {
                windowY = screenMinY
            } else if windowY + windowHeight > screenMaxY {
                windowY = screenMaxY - windowHeight
            }
            
            window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true)
            model.slimBoxWidth = windowWidth
            model.slimBoxHeight = windowHeight
            settings.boxSlimModeWidth = Double(windowWidth)
            settings.boxSlimModeHeight = Double(windowHeight)
        }
        
        private func triggerSlimBoxMode() {
            setupSlimBoxWindow()
            
            model.boxSlimModeActive = true
            model.boxDragActive = true
            updateProximityWakeWindowFrame()
            if settings.boxSlimModePosition == 1 {
                slimBoxOpenPosition = NSEvent.mouseLocation
            } else {
                slimBoxOpenPosition = nil
            }
            
            if let idx = activePages.firstIndex(of: .box) {
                model.currentPage = idx
            }
            
            updateSlimBoxWindowFrame()
            
            if let window = slimBoxWindow {
                window.alphaValue = 1.0
                window.ignoresMouseEvents = false
                window.orderFrontRegardless()
            }
        }
        
        func hideSlimBox() {
            guard let window = slimBoxWindow else { return }
            model.boxSlimModeActive = false
            model.boxDragActive = false
            updateProximityWakeWindowFrame()
            // Issue 4d: Don't permanently suppress proximity after hiding the slim box.
            // The cursor may already be outside the notch zone, so suppression would
            // block the very next hover attempt. Reset immediately.
            suppressProximityUntilExit = false
            slimBoxOpenPosition = nil
            
            window.alphaValue = 0.0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
        
        private func startGlobalDragPolling(forceEnabled: Bool? = nil) {
            dragPollingTimer?.cancel()
            // Use the caller-supplied value when available (avoids @Published willSet race);
            // otherwise fall back to reading the setting directly (e.g. at launch).
            let isEnabled = forceEnabled ?? settings.boxSlimModeEnabled
            guard isEnabled else { return }
            
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500))
            timer.setEventHandler { [weak self] in
                self?.pollGlobalDragState()
            }
            timer.resume()
            dragPollingTimer = timer
        }
        
        private func pollGlobalDragState() {
            autoreleasepool {
                guard settings.boxSlimModeEnabled else {
                    if isDragSessionActive {
                        isDragSessionActive = false
                        stopFastDragTracking()
                        resetDragTrackingState()
                    }
                    return
                }
                
                let isLeftButtonPressed = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
                
                if isDragSessionActive {
                    if !isLeftButtonPressed {
                        isDragSessionActive = false
                        stopFastDragTracking()
                        resetDragTrackingState()
                        if model.boxSlimModeActive {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                                guard let self = self else { return }
                                if self.slimBoxDidReceiveDropThisSession {
                                    self.slimBoxDidReceiveDropThisSession = false
                                    return
                                }
                                let isHovered = self.slimBoxWindow?.frame.contains(NSEvent.mouseLocation) ?? false
                                if !isHovered {
                                    self.hideSlimBox()
                                }
                            }
                        }
                    }
                    return
                }
                
                let dragPboard = dragPasteboard
                let currentChangeCount = dragPboard.changeCount
                
                if currentChangeCount != lastDragChangeCount {
                    lastDragChangeCount = currentChangeCount
                    
                    let hasFileTypes = dragPboard.types?.contains(where: {
                        $0 == .fileURL || $0.rawValue == "public.file-url" || $0.rawValue == "NSFilenamesPboardType"
                    }) ?? false
                    
                    if hasFileTypes && isLeftButtonPressed {
                        isDragSessionActive = true
                        slimBoxDidReceiveDropThisSession = false
                        startFastDragTracking()
                    }
                }
            }
        }
        
        private func startFastDragTracking() {
            slimBoxDidReceiveDropThisSession = false
            fastDragTrackingTimer?.cancel()
            
            dragWiggleAccumulator = 0
            lastDxSign = 0
            lastDySign = 0
            directionChanges = 0
            lastDirectionChangeTime = 0
            lastDragPoint = NSEvent.mouseLocation
            lastDragTime = ProcessInfo.processInfo.systemUptime
            boxDragHoldWorkItem?.cancel()
            boxDragHoldWorkItem = nil
            
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(30))
            timer.setEventHandler { [weak self] in
                self?.trackDragCursorLocation()
            }
            timer.resume()
            fastDragTrackingTimer = timer
        }
        
        private func stopFastDragTracking() {
            fastDragTrackingTimer?.cancel()
            fastDragTrackingTimer = nil
        }
        
        private func resetDragTrackingState() {
            boxDragHoldWorkItem?.cancel()
            boxDragHoldWorkItem = nil
            dragWiggleAccumulator = 0
            lastDragPoint = nil
            lastDragTime = 0
            lastDxSign = 0
            lastDySign = 0
            directionChanges = 0
            lastDirectionChangeTime = 0
        }
        
        private func trackDragCursorLocation() {
            guard settings.boxSlimModeEnabled else { return }
            guard !model.boxSlimModeActive else { return }
            
            let isLeftButtonPressed = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
            if !isLeftButtonPressed {
                isDragSessionActive = false
                stopFastDragTracking()
                resetDragTrackingState()
                if model.boxSlimModeActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let self = self else { return }
                        if self.slimBoxDidReceiveDropThisSession {
                            self.slimBoxDidReceiveDropThisSession = false
                            return
                        }
                        let isHovered = self.slimBoxWindow?.frame.contains(NSEvent.mouseLocation) ?? false
                        if !isHovered {
                            self.hideSlimBox()
                        }
                    }
                }
                return
            }
            
            guard !model.isExpanded else { return }
            
            let globalPoint = NSEvent.mouseLocation
            let now = ProcessInfo.processInfo.systemUptime
            
            if settings.boxSlimModeTrigger == 0 { // Wiggle Trigger
                if let lastPoint = lastDragPoint {
                    let dx = globalPoint.x - lastPoint.x
                    let dy = globalPoint.y - lastPoint.y
                    
                    let threshold: CGFloat = max(3.0, 25.0 / CGFloat(settings.boxSlimModeWiggleSensitivity))
                    var signChanged = false
                    
                    if abs(dx) > threshold {
                        let currentSignX = dx > 0 ? 1 : -1
                        if lastDxSign != 0 && currentSignX != lastDxSign {
                            signChanged = true
                        }
                        lastDxSign = currentSignX
                    }
                    
                    if abs(dy) > threshold {
                        let currentSignY = dy > 0 ? 1 : -1
                        if lastDySign != 0 && currentSignY != lastDySign {
                            signChanged = true
                        }
                        lastDySign = currentSignY
                    }
                    
                    if signChanged {
                        if now - lastDirectionChangeTime < 0.5 {
                            directionChanges += 1
                        } else {
                            directionChanges = 1
                        }
                        lastDirectionChangeTime = now
                    } else if now - lastDirectionChangeTime > 0.5 {
                        directionChanges = 0
                    }
                    
                    if directionChanges >= 4 {
                        triggerSlimBoxMode()
                        stopFastDragTracking()
                    }
                }
                lastDragPoint = globalPoint
                lastDragTime = now
            } else { // Delay Trigger
                if boxDragHoldWorkItem == nil {
                    let holdDuration = settings.boxSlimModeHoldDuration
                    let item = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.triggerSlimBoxMode()
                        self.stopFastDragTracking()
                    }
                    boxDragHoldWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: item)
                }
            }
        }
        
        private struct ProximityZones {
            let notchRect: CGRect
            let notchEdgeRect: CGRect
            let approachRect: CGRect
            let isHoveringEdge: Bool
            let isInsideNotch: Bool
        }
        
        private func makeProximityZones(screenRect: CGRect, point: NSPoint, isFileDrag: Bool) -> ProximityZones {
            let edge = settings.clampedNotchEdgeThickness
            let forceApproachForDrag = isFileDrag && settings.alwaysUseApproachWhenDraggingFile
            let disableApproachForCurrentInput = (!settings.enableApproach || settings.openMethod == 1) && !forceApproachForDrag
            let approachScale: CGFloat = forceApproachForDrag ? 2.0 : 1.0
            let approachWidth = disableApproachForCurrentInput ? 0 : settings.clampedApproachWidth * approachScale
            let approachHeight = disableApproachForCurrentInput ? 0 : settings.clampedApproachHeight * approachScale
            let edgeNotchWidth = settings.effectiveNotchWidth
            let edgeNotchHeight = settings.effectiveNotchHeight
            let edgeNotchLeft = settings.hardwareNotchX
            
            let notchRect = CGRect(
                x: edgeNotchLeft,
                // Use global screen-space Y (maxY), not local height, to keep
                // inside-notch detection correct on all display origins.
                y: screenRect.maxY - edgeNotchHeight,
                width: edgeNotchWidth,
                height: edgeNotchHeight
            )
            let notchEdgeRect = notchRect.insetBy(dx: -edge, dy: -edge)
            let approachRect = CGRect(
                x: notchEdgeRect.minX - approachWidth,
                y: notchEdgeRect.minY - approachHeight,
                width: notchEdgeRect.width + approachWidth * 2,
                height: approachHeight
            )
            let isInsideNotch = notchRect.contains(point)
            let isHoveringEdge = isPointInNotchEdge(point, notchRect: notchRect, edge: edge)
            
            return ProximityZones(
                notchRect: notchRect,
                notchEdgeRect: notchEdgeRect,
                approachRect: approachRect,
                isHoveringEdge: isHoveringEdge,
                isInsideNotch: isInsideNotch
            )
        }
        
        private func isPointInNotchEdge(_ point: NSPoint, notchRect: CGRect, edge: CGFloat) -> Bool {
            if notchRect.contains(point) {
                return true
            }
            let thickness = max(0, edge)
            guard thickness > 0 else { return false }
            let hitThickness = max(6, thickness)
            let outerRect = notchRect.insetBy(dx: -hitThickness, dy: -hitThickness)
            return outerRect.contains(point)
        }
        
        private func scheduleHoverCloseIfNeeded() {
            guard !model.isAddSheetOpen else { return }
            guard hoverCloseWorkItem == nil else { return }
            let delay = settings.hoverCloseDelay
            if delay <= 0 {
                hidePanel()
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                self?.hidePanel()
            }
            hoverCloseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
        
        private func startIslandOpenMousePolling() {
            guard islandOpenMousePollTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .milliseconds(400), repeating: .milliseconds(400), leeway: .milliseconds(150))
            timer.setEventHandler { [weak self] in
                self?.handleIslandOpenMousePollTick()
            }
            islandOpenMousePollTimer = timer
            timer.resume()
        }
        
        private func stopIslandOpenMousePolling() {
            islandOpenMousePollTimer?.cancel()
            islandOpenMousePollTimer = nil
        }
        
        private func handleIslandOpenMousePollTick() {
            guard !model.isAddSheetOpen else { return }
            guard model.isExpanded, !model.isPinned, let window = islandWindow else {
                stopIslandOpenMousePolling()
                return
            }
            let point = NSEvent.mouseLocation
            let now = ProcessInfo.processInfo.systemUptime
            // Give the panel a brief settling window so fast notch-entry doesn't
            // get interpreted as an immediate leave before geometry catches up.
            if now - lastPanelExpandedAt < 0.45 {
                return
            }
            
            if window.frame.contains(point) || isPointInsideNotchActivationZone(point) {
                return
            }
            scheduleHoverCloseIfNeeded()
        }
        
        private func isPointInsideNotchActivationZone(_ point: NSPoint) -> Bool {
            guard cachedScreenFrame != .zero else { return false }
            let zones = makeProximityZones(screenRect: cachedScreenFrame, point: point, isFileDrag: false)
            return zones.isInsideNotch || zones.isHoveringEdge
        }
        
        private func resetApproachProgressSampling() {
            lastApproachProgressSampleTime = 0
            lastApproachProgressEmitted = -1
        }
        
        private func applyApproachProgressIfNeeded(_ targetProgress: CGFloat) {
            let clamped = min(1.0, max(0.0, targetProgress))
            let now = ProcessInfo.processInfo.systemUptime
            
            if lastApproachProgressEmitted < 0 {
                lastApproachProgressEmitted = clamped
                lastApproachProgressSampleTime = now
                if abs(model.expansionProgress - clamped) > 0.005 {
                    model.expansionProgress = clamped
                }
                return
            }
            
            let delta = abs(clamped - lastApproachProgressEmitted)
            let elapsed = now - lastApproachProgressSampleTime
            let isLargeStep = delta >= 0.08
            guard isLargeStep || (delta >= approachProgressDeltaThreshold && elapsed >= approachProgressUpdateInterval) else {
                return
            }
            
            lastApproachProgressEmitted = clamped
            lastApproachProgressSampleTime = now
            if abs(model.expansionProgress - clamped) > 0.005 {
                model.expansionProgress = clamped
            }
        }
        
        
        
        private func evaluateMouseCoordinates(_ globalPoint: NSPoint, isFileDrag: Bool) {
            autoreleasepool {
                if model.observedFileToast != nil, let frame = notchWindow?.frame, frame.contains(globalPoint) {
                    toastHideWorkItem?.cancel()
                    toastHideWorkItem = nil
                }
                if model.boxSlimModeActive {
                    return
                }
                if model.isAddSheetOpen {
                    hoverCloseWorkItem?.cancel()
                    hoverCloseWorkItem = nil
                    return
                }
                guard cachedScreenFrame != .zero else { return }
                let screenRect = cachedScreenFrame
                let zones = makeProximityZones(screenRect: screenRect, point: globalPoint, isFileDrag: isFileDrag)
                
                if settings.openMethod == 1 && !isFileDrag && !model.isExpanded && !model.isPinned {
                    let isDirectHoverOverNotch = zones.isInsideNotch || zones.isHoveringEdge
                    if isDirectHoverOverNotch {
                        hoverCloseWorkItem?.cancel()
                        hoverCloseWorkItem = nil
                    } else {
                        scheduleHoverCloseIfNeeded()
                    }
                    return
                }
                
                let isInsideActiveZone = zones.isInsideNotch || zones.isHoveringEdge || zones.approachRect.contains(globalPoint)
                
                if isInsideActiveZone {
                    hoverCloseWorkItem?.cancel()
                    hoverCloseWorkItem = nil
                }
                
                if model.isPinned {
                    showPanel(expanded: true, pinned: true)
                    return
                }
                
                if model.isExpanded {
                    var isWithinExpandedPanel = false
                    if let frame = notchWindow?.frame {
                        if model.boxSlimModeActive {
                            let bufferFrame = frame.insetBy(dx: -40, dy: -40)
                            isWithinExpandedPanel = bufferFrame.contains(globalPoint)
                        } else {
                            isWithinExpandedPanel = frame.contains(globalPoint)
                        }
                    }
                    if isWithinExpandedPanel || zones.isInsideNotch || zones.isHoveringEdge {
                        hoverCloseWorkItem?.cancel()
                        hoverCloseWorkItem = nil
                    } else {
                        scheduleHoverCloseIfNeeded()
                    }
                    return
                }
                
                if isFileDrag {
                    if settings.boxSlimModeEnabled {
                        // Issue 3: When slim mode is enabled, still open the full island if the
                        // cursor is directly on the notch edge so the user can drop normally.
                        if zones.isInsideNotch || zones.isHoveringEdge {
                            boxDragHoldWorkItem?.cancel()
                            boxDragHoldWorkItem = nil
                            model.boxDragActive = true
                            showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
                            if notchWindow?.alphaValue != 1.0 { notchWindow?.alphaValue = 1.0 }
                            if notchWindow?.isVisible == false { notchWindow?.orderFrontRegardless() }
                            if notchWindow?.ignoresMouseEvents != false { notchWindow?.ignoresMouseEvents = false }
                        }
                        // Background drag polling handles the Slim Box triggers for non-notch drags.
                        return
                    } else {
                        if isInsideActiveZone {
                            boxDragHoldWorkItem?.cancel()
                            boxDragHoldWorkItem = nil
                            model.boxSlimModeActive = false
                            model.boxDragActive = true
                            showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
                            
                            if notchWindow?.alphaValue != 1.0 {
                                notchWindow?.alphaValue = 1.0
                            }
                            if notchWindow?.isVisible == false {
                                notchWindow?.orderFrontRegardless()
                            }
                            if notchWindow?.ignoresMouseEvents != false {
                                notchWindow?.ignoresMouseEvents = false
                            }
                        } else {
                            boxDragHoldWorkItem?.cancel()
                            boxDragHoldWorkItem = nil
                            dragWiggleAccumulator = 0
                            lastDragPoint = nil
                            hidePanel()
                        }
                    }
                    return
                }
                
                let isDirectHoverOverNotch = zones.isInsideNotch || zones.isHoveringEdge
                let forceApproachForDrag = isFileDrag && settings.alwaysUseApproachWhenDraggingFile
                let disableApproachForCurrentInput = !settings.enableApproach && !forceApproachForDrag
                
                if disableApproachForCurrentInput {
                    if isDirectHoverOverNotch, isFileDrag {
                        let preferredPage = isFileDrag ? IslandPage.box.rawValue : nil
                        showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
                    } else {
                        hidePanel()
                    }
                    return
                }
                
                if isInsideActiveZone {
                    let totalHeight = max(1.0, zones.approachRect.height)
                    let distance = max(0.0, zones.notchEdgeRect.minY - globalPoint.y)
                    let baseProgress = min(1.0, max(0.0, 1.0 - (distance / totalHeight)))
                    let targetProgress = zones.isHoveringEdge ? 1.0 : baseProgress
                    
                    // When cursor is already on the notch edge, skip approach prefill.
                    // Let showPanel drive a full, consistent open animation instead of
                    // arriving with expansionProgress already at 1.0.
                    if !isDirectHoverOverNotch {
                        applyApproachProgressIfNeeded(targetProgress)
                    }
                    if notchWindow?.alphaValue != 1.0 {
                        notchWindow?.alphaValue = 1.0
                    }
                    if notchWindow?.isVisible == false {
                        notchWindow?.orderFrontRegardless()
                    }
                    let shouldIgnoreMouseEvents = !(isFileDrag && zones.approachRect.contains(globalPoint))
                    if notchWindow?.ignoresMouseEvents != shouldIgnoreMouseEvents {
                        notchWindow?.ignoresMouseEvents = shouldIgnoreMouseEvents
                    }
                    
                    if isDirectHoverOverNotch, isFileDrag {
                        approachWorkItem?.cancel()
                        approachWorkItem = nil
                        resetApproachProgressSampling()
                        let preferredPage = isFileDrag ? IslandPage.box.rawValue : nil
                        showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
                    } else {
                        approachWorkItem?.cancel()
                        approachWorkItem = nil
                    }
                } else {
                    approachWorkItem?.cancel()
                    approachWorkItem = nil
                    resetApproachProgressSampling()
                    hidePanel()
                }
            }
        }
        
        private func showPanel(expanded: Bool, pinned: Bool, preferredPage: Int? = nil) {
            guard let window = islandWindow else { return }
            
            // Immediately size window frame when expanding/pinning to avoid layout deadlock and clipping
            if expanded || pinned {
                toastHideWorkItem?.cancel()
                toastHideWorkItem = nil
                let isFloatingPagerActive = settings.pagerStyle == 1 && settings.showPagers
                let floatingPagerHeightAdjustment: CGFloat = isFloatingPagerActive ? (8 + 54) : 0
                let expectedExpandedHeight = panelHeight + floatingPagerHeightAdjustment
                updateNotchWindowFrame(heightOverride: expectedExpandedHeight)
                
                // Re-assert level and ordering to guarantee we stay on top of the menu bar/notch
                window.level = .statusBar + 2
                window.orderFrontRegardless()
            }
            
            if expanded {
                panelVisibilityEpoch &+= 1
            }
            
            let resolvedPage: IslandPage?
            if let preferredPage {
                resolvedPage = IslandPage(rawValue: preferredPage)
            } else if expanded {
                if settings.reopenLastPage {
                    resolvedPage = IslandPage(rawValue: settings.lastVisitedPage)
                } else if settings.defaultToBoxIfItems, !model.boxFiles.isEmpty {
                    resolvedPage = .box
                } else {
                    resolvedPage = IslandPage(rawValue: settings.defaultPage)
                }
            } else {
                resolvedPage = nil
            }
            
            let stateMatches = model.isExpanded == expanded && model.isPinned == pinned
            let currentPageEnum = activePages.indices.contains(model.currentPage) ? activePages[model.currentPage] : .clipboard
            let pageMatches = resolvedPage == nil || currentPageEnum == resolvedPage
            if stateMatches,
               pageMatches,
               abs(model.expansionProgress - 1.0) < 0.001,
               abs(model.closeGestureProgress) < 0.001,
               abs(SwipeState.shared.carouselDragOffset) < 0.001 {
                // Issue 4a: always cancel pending close work items even in the early-return path
                hoverCloseWorkItem?.cancel()
                hoverCloseWorkItem = nil
                swipeCloseWorkItem?.cancel()
                swipeCloseWorkItem = nil
                if window.alphaValue != 1.0 {
                    window.alphaValue = 1.0
                }
                if window.ignoresMouseEvents {
                    window.ignoresMouseEvents = false
                }
                if !window.isVisible {
                    window.orderFrontRegardless()
                }
                updateClipboardObservationMode(immediatePoll: true)
                updateProximityWakeWindowFrame()
                if expanded {
                    startIslandOpenMousePolling()
                } else {
                    stopIslandOpenMousePolling()
                }
                return
            }
            
            cancelIdleCompaction()
            pendingHideWorkItem?.cancel()
            pendingHideWorkItem = nil
            hoverCloseWorkItem?.cancel()
            hoverCloseWorkItem = nil
            swipeCloseWorkItem?.cancel()
            swipeCloseWorkItem = nil
            
            if expanded {
                if model.boxSlimModeActive {
                    hideSlimBox()
                }
            }
            let isFreshOpenRequest = expanded && !model.isExpanded
            let wasExpanded = model.isExpanded
            let shouldAnimateOpen = expanded && (isFreshOpenRequest || !wasExpanded || model.expansionProgress < 0.999 || model.closeGestureProgress > 0.001)
            if model.isExpanded != expanded {
                model.isExpanded = expanded
            }
            if model.isPinned != pinned {
                model.isPinned = pinned
            }
            
            if shouldAnimateOpen {
                var resetTransaction = Transaction()
                resetTransaction.animation = nil
                withTransaction(resetTransaction) {
                    model.expansionProgress = 0
                    model.closeGestureProgress = 0
                    SwipeState.shared.carouselDragOffset = 0
                }
                withAnimation(settings.notchOpenAnimation) {
                    model.expansionProgress = 1.0
                    model.closeGestureProgress = 0
                    SwipeState.shared.carouselDragOffset = 0
                }
            } else {
                if abs(model.expansionProgress - 1.0) > 0.001 {
                    model.expansionProgress = 1.0
                }
                if abs(model.closeGestureProgress) > 0.001 {
                    model.closeGestureProgress = 0
                }
                if abs(SwipeState.shared.carouselDragOffset) > 0.001 {
                    SwipeState.shared.carouselDragOffset = 0
                }
            }
            lastCloseProgressEmission = 0
            lastCarouselOffsetEmission = 0
            if let resolvedPage, let idx = activePages.firstIndex(of: resolvedPage) {
                if model.currentPage != idx {
                    model.currentPage = idx
                }
            }
            if window.alphaValue != 1.0 {
                window.alphaValue = 1.0
            }
            if window.ignoresMouseEvents {
                window.ignoresMouseEvents = false
            }
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            if expanded {
                lastPanelExpandedAt = ProcessInfo.processInfo.systemUptime
            }
            isCursorInActivationZone = window.frame.contains(NSEvent.mouseLocation)
            updateClipboardObservationMode(immediatePoll: true)
            updateProximityWakeWindowFrame()
            if expanded {
                startIslandOpenMousePolling()
            } else {
                stopIslandOpenMousePolling()
            }
        }
        
        private func setupBatteryWindow() {
            settings.$batteryIndicatorEnabled
                .combineLatest(settings.$accentColor.map { Color($0) })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled, _ in
                    if enabled {
                        self?.showBatteryWindow()
                    } else {
                        self?.hideBatteryWindow()
                    }
                }
                .store(in: &settingsCancellables)
            
            if settings.batteryIndicatorEnabled {
                showBatteryWindow()
            }
        }
        
        private func showBatteryWindow() {
            guard cachedScreenFrame != .zero else { return }
            let padding: CGFloat = 24
            let rect = NSRect(
                x: settings.hardwareNotchX - padding,
                y: cachedScreenFrame.maxY - settings.effectiveNotchHeight - padding,
                width: settings.effectiveNotchWidth + (padding * 2),
                height: settings.effectiveNotchHeight + padding
            )
            if batteryWindow == nil {
                let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.level = .statusBar + 3
                let batteryHostingView = NSHostingView(rootView: BatteryNotchView().environmentObject(BatteryMonitor.shared))
                batteryHostingView.sizingOptions = []
                if #available(macOS 11.0, *) {
                    batteryHostingView.safeAreaRegions = []
                }
                panel.contentView = batteryHostingView
                batteryWindow = panel
            } else {
                batteryWindow?.setFrame(rect, display: true)
            }
            batteryWindow?.orderFrontRegardless()
        }
        
        private func hideBatteryWindow() {
            batteryWindow?.orderOut(nil)
        }
        
        private func updateBatteryWindowFrame() {
            guard let window = batteryWindow, cachedScreenFrame != .zero else { return }
            let padding: CGFloat = 24
            let rect = NSRect(
                x: settings.hardwareNotchX - padding,
                y: cachedScreenFrame.maxY - settings.effectiveNotchHeight - padding,
                width: settings.effectiveNotchWidth + (padding * 2),
                height: settings.effectiveNotchHeight + padding
            )
            window.setFrame(rect, display: true)
        }
        
        func hidePanel(preserveCloseProgress: Bool = false) {
            if model.boxSlimModeActive {
                hideSlimBox()
                return
            }
            guard let window = islandWindow else { return }
            if (model.observedFileToast != nil || model.isToastDismissing) && !model.isExpanded {
                return
            }
            if model.isPinned { return }
            pendingHideWorkItem?.cancel()
            swipeCloseWorkItem?.cancel()
            swipeCloseWorkItem = nil
            hoverCloseWorkItem?.cancel()
            hoverCloseWorkItem = nil
            stopIslandOpenMousePolling()
            model.boxDragActive = false
            model.boxSlimModeActive = false
            // Match open exactly: use the same notch spring for collapse.
            // Keep the window visible long enough for the spring to settle.
            withAnimation(settings.notchOpenAnimation) {
                model.isExpanded = false
                model.expansionProgress = 0.0
                if !preserveCloseProgress {
                    model.closeGestureProgress = 0
                }
                SwipeState.shared.carouselDragOffset = 0
            }
            // Reactivate notch/approach tracking immediately on close start so
            // quick re-entry can reopen without waiting for final orderOut.
            updateProximityWakeWindowFrame()
            lastCloseProgressEmission = 0
            lastCarouselOffsetEmission = 0
            
            panelVisibilityEpoch &+= 1
            let hideEpoch = panelVisibilityEpoch
            
            let hideWorkItem = DispatchWorkItem { [weak self] in
                guard let self, !self.model.isPinned else { return }
                guard self.panelVisibilityEpoch == hideEpoch else { return }
                window.contentView?.stopScrolling() // Intercept and kill any NSScrollingAnimators immediately
                let hasActiveChrono = (self.model.isStopwatchRunning || self.model.isTimerRunning) && !self.settings.disableChronoHUD
                if !hasActiveChrono {
                    window.alphaValue = 0.0
                    window.ignoresMouseEvents = true
                    window.orderOut(nil)
                } else {
                    window.alphaValue = 1.0
                    window.ignoresMouseEvents = true
                }
                self.updateNotchWindowFrame(heightOverride: self.settings.effectiveNotchHeight)
                self.clearCursorPresenceState()
                // Issue 4c: ensure suppressProximityUntilExit is cleared after close
                // so the very next hover always works correctly.
                self.suppressProximityUntilExit = false
                self.model.expansionProgress = 0
                self.model.boxSlimModeActive = false
                self.slimBoxOpenPosition = nil
                self.dragWiggleAccumulator = 0
                self.lastDragPoint = nil
                self.scheduleIdleCompactionIfNeeded()
                self.updateClipboardObservationMode()
                self.updateProximityWakeWindowFrame()
            }
            scheduleHideAfterCollapse(
                window: window,
                hideWorkItem: hideWorkItem,
                startedAt: ProcessInfo.processInfo.systemUptime,
                hideEpoch: hideEpoch
            )
        }
        
        private func scheduleHideAfterCollapse(window: NSWindow, hideWorkItem: DispatchWorkItem, startedAt: TimeInterval, hideEpoch: UInt64) {
            let pollWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.panelVisibilityEpoch == hideEpoch else { return }
                guard !self.model.isPinned else { return }
                guard !self.model.isExpanded else { return }
                
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                // Frame updates are quantized to rounded points in
                // `scheduleWindowFrameUpdate`, so compare against the same final value.
                let targetNotchHeight = self.settings.effectiveNotchHeight.rounded()
                let currentHeight = window.frame.height
                let hasCollapsedToNotch = abs(currentHeight - targetNotchHeight) <= 0.01
                
                // Require a small minimum visible duration so close remains
                // perceptible even when frame updates arrive quickly.
                if hasCollapsedToNotch && elapsed >= 0.10 {
                    hideWorkItem.perform()
                    return
                }
                
                if elapsed >= 1.2 {
                    // Safety net: force an exact final-notch frame before hiding.
                    self.updateNotchWindowFrame(heightOverride: targetNotchHeight)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        guard self.panelVisibilityEpoch == hideEpoch else { return }
                        hideWorkItem.perform()
                    }
                    return
                }
                
                self.scheduleHideAfterCollapse(window: window, hideWorkItem: hideWorkItem, startedAt: startedAt, hideEpoch: hideEpoch)
            }
            
            pendingHideWorkItem = pollWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0), execute: pollWorkItem)
        }
        
        private func cancelIdleCompaction() {
            idleCompactionWorkItem?.cancel()
            idleCompactionWorkItem = nil
        }
        
        private func scheduleIdleCompactionIfNeeded() {
            cancelIdleCompaction()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !self.model.isExpanded,
                      !self.model.isPinned,
                      self.model.observedFileToast == nil,
                      !self.model.isToastDismissing,
                      !(self.settings.showHoverPreviews && self.settings.hoverPreviewFocus != .all) else {
                    return
                }
                self.performIdleCompaction()
            }
            idleCompactionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + idleCompactionDelay, execute: workItem)
        }
        
        private func performIdleCompaction() {
            BoxIconCache.shared.removeAll()
            AppIconCache.shared.clear()
            BookmarkIconCache.shared.clear()
            if !model.isExpanded && !model.isPinned {
                SwipeState.shared.carouselDragOffset = 0
                model.closeGestureProgress = 0
            }
        }
        
        private func configureFolderMonitors(with folders: [String]) {
            let desired = Set(folders)
            let existing = Set(folderMonitors.keys)
            
            let toRemove = existing.subtracting(desired)
            let toAdd = desired.subtracting(existing)
            
            for path in toRemove {
                folderMonitors[path]?.stop()
                folderMonitors.removeValue(forKey: path)
                folderSnapshots.removeValue(forKey: path)
            }
            
            for path in toAdd {
                let url = URL(fileURLWithPath: path)
                folderSnapshots[path] = snapshotFiles(in: url)
                let monitor = FolderMonitor(url: url) { [weak self] in
                    self?.handleFolderChange(for: url)
                }
                monitor.start()
                folderMonitors[path] = monitor
            }
        }
        
        private func snapshotFiles(in folder: URL) -> Set<String> {
            let manager = FileManager.default
            let files = (try? manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            
            let filtered = files.filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory != true
            }
            
            return Set(filtered.map { $0.path })
        }
        
        private func handleFolderChange(for folder: URL) {
            let path = folder.path
            let previous = folderSnapshots[path] ?? []
            let current = snapshotFiles(in: folder)
            folderSnapshots[path] = current
            
            let added = current.subtracting(previous)
            guard !added.isEmpty else { return }
            
            let newURLs = added.map { URL(fileURLWithPath: $0) }
            let newest = newURLs.max { lhs, rhs in
                let lhsValues = try? lhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let rhsValues = try? rhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let lhsDate = lhsValues?.creationDate ?? lhsValues?.contentModificationDate ?? .distantPast
                let rhsDate = rhsValues?.creationDate ?? rhsValues?.contentModificationDate ?? .distantPast
                return lhsDate < rhsDate
            }
            
            guard let fileURL = newest else { return }
            DispatchQueue.main.async { [weak self] in
                self?.showObservedFileToast(fileURL: fileURL, folderURL: folder)
            }
        }
        
        private func showObservedFileToast(fileURL: URL, folderURL: URL) {
            withAnimation(settings.notchOpenAnimation) {
                model.observedFileToast = ObservedFileToast(fileURL: fileURL, folderURL: folderURL)
            }
            showToastPanel()
        }
        
        private func showToastPanel() {
            guard let window = islandWindow else { return }
            cancelIdleCompaction()
            pendingHideWorkItem?.cancel()
            pendingHideWorkItem = nil
            toastHideWorkItem?.cancel()
            toastHideWorkItem = nil
            
            model.isToastDismissing = false
            model.isExpanded = false
            model.isPinned = false
            model.expansionProgress = 0.0
            
            // Immediately size window frame to host the toast view to prevent clipping/layout deadlock
            let targetHeight = toastPanelHeight + settings.effectiveNotchHeight
            updateNotchWindowFrame(heightOverride: targetHeight)
            
            window.alphaValue = 1.0
            window.ignoresMouseEvents = false
            window.level = .statusBar + 2
            window.orderFrontRegardless()
            
            withAnimation(settings.notchOpenAnimation) {
                model.expansionProgress = 1.0
            }
            updateClipboardObservationMode(immediatePoll: true)
            
            // Schedule auto-hide if configured (0 = never hide)
            if settings.toastHideDelay > 0 {
                let delay = settings.toastHideDelay
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    withAnimation(self.settings.notchOpenAnimation) {
                        self.model.expansionProgress = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.dismissToastAndHideNotch()
                    }
                }
                toastHideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
        
        func dismissToastAndHideNotch() {
            toastHideWorkItem?.cancel()
            toastHideWorkItem = nil
            scheduleIdleCompactionIfNeeded()
            pendingHideWorkItem?.cancel()
            pendingHideWorkItem = nil
            suppressProximityUntilExit = true
            model.isToastDismissing = true
            model.observedFileToast = nil
            model.isExpanded = false
            model.isPinned = false
            model.expansionProgress = 0.0
            model.closeGestureProgress = 0
            updateNotchWindowFrame(heightOverride: panelHeight)
            if let window = notchWindow {
                let hasActiveChrono = (model.isStopwatchRunning || model.isTimerRunning) && !settings.disableChronoHUD
                if !hasActiveChrono {
                    window.alphaValue = 0.0
                    window.ignoresMouseEvents = true
                    window.orderOut(nil)
                } else {
                    window.alphaValue = 1.0
                    window.ignoresMouseEvents = true
                }
            }
            updateClipboardObservationMode(immediatePoll: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.suppressProximityUntilExit = true
                self?.model.isToastDismissing = false
                self?.updateClipboardObservationMode()
            }
        }
        
        private func updateWindowFrameForNewHeight(_ newHeight: CGFloat) {
            guard let window = notchWindow, cachedScreenFrame != .zero else { return }
            
            // Don't interfere when settings previews are active, as they use a fixed large frame.
            if settings.showHoverPreviews && settings.hoverPreviewFocus != .all {
                return
            }
            
            guard newHeight.isFinite, newHeight > 1 else { return }
            
            var targetHeight = newHeight
            if model.isExpanded || model.isPinned {
                let isFloatingPagerActive = settings.pagerStyle == 1 && settings.showPagers
                let floatingPagerHeightAdjustment: CGFloat = isFloatingPagerActive ? (8 + 54) : 0
                let expectedExpandedHeight = panelHeight + floatingPagerHeightAdjustment
                if targetHeight < expectedExpandedHeight {
                    targetHeight = expectedExpandedHeight
                }
            } else if model.expansionProgress > 0 {
                let targetProgress = model.expansionProgress
                let easedProgress = targetProgress * targetProgress * (3 - 2 * targetProgress)
                let expectedPeekHeight = settings.effectiveNotchHeight + ((panelHeight - settings.effectiveNotchHeight) * easedProgress)
                if targetHeight < expectedPeekHeight {
                    targetHeight = expectedPeekHeight
                }
            }
            
            // Keep the window width fixed at the maximum possible panel width to avoid clipping content during animation.
            let windowWidth = max(self.panelWidth, self.notchWidth + 240)
            let windowHeight = targetHeight
            
            // Correct window positioning: Center the window's midpoint on the hardware notch's midpoint
            let notchX = settings.hardwareNotchX
            let notchWidth = settings.effectiveNotchWidth
            let windowX = notchX - (windowWidth - notchWidth) / 2
            let windowY = cachedScreenFrame.maxY - windowHeight
            
            let newFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
            
            let current = window.frame
            if abs(current.origin.x - newFrame.origin.x) < 1.0,
               abs(current.origin.y - newFrame.origin.y) < 1.0,
               abs(current.size.width - newFrame.size.width) < 1.0,
               abs(current.size.height - newFrame.size.height) < 1.0 {
                return
            }
            window.setFrame(newFrame, display: false)
            window.level = .statusBar + 2
        }
        
        private func scheduleWindowFrameUpdate(for newHeight: CGFloat) {
            guard newHeight.isFinite, newHeight > 1 else { return }
            if model.boxSlimModeActive {
                return
            }
            if !model.isExpanded,
               !model.isPinned,
               model.observedFileToast == nil,
               let window = notchWindow,
               window.alphaValue <= 0.001 {
                pendingWindowHeightUpdate = nil
                return
            }
            let quantizedHeight = newHeight.rounded()
            if let pending = pendingWindowHeightUpdate, abs(pending - quantizedHeight) < 0.6 {
                return
            }
            pendingWindowHeightUpdate = quantizedHeight
            guard windowFrameUpdateWorkItem == nil else { return }
            
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.windowFrameUpdateWorkItem = nil
                guard let targetHeight = self.pendingWindowHeightUpdate else { return }
                self.pendingWindowHeightUpdate = nil
                self.updateWindowFrameForNewHeight(targetHeight)
            }
            windowFrameUpdateWorkItem = workItem
            let frameDelay: TimeInterval = model.isExpanded ? 0.05 : 0.07
            DispatchQueue.main.asyncAfter(deadline: .now() + frameDelay, execute: workItem)
        }
        
        func applicationWillTerminate(_ notification: Notification) {
            dragPollingTimer?.cancel()
            dragPollingTimer = nil
            fastDragTrackingTimer?.cancel()
            fastDragTrackingTimer = nil
            slimBoxWindow?.orderOut(nil)
            slimBoxWindow = nil
            cancelIdleCompaction()
            stopIslandOpenMousePolling()
            stopClipboardObservation()
            settings.flushPendingWrites()
            PersistenceWriteCoordinator.shared.flushNow()
            windowFrameUpdateWorkItem?.cancel()
            windowFrameUpdateWorkItem = nil
            pendingWindowHeightUpdate = nil
            memoryPressureSource?.cancel()
            memoryPressureSource = nil
            for monitor in folderMonitors.values {
                monitor.stop()
            }
        }
}
