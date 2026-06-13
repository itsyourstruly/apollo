
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Master Container Structural Layout
struct UnifiedNotchContainer: View {
    @ObservedObject var model: NotchMenuModel
    @ObservedObject var settings: AppSettings
    var isSlimBoxInstance: Bool = false
    
    @State var isJotEditorFocused: Bool = false
    
    @State var highlightedClipboardID: UUID?
    @State var clipboardTapFeedbackProgress: CGFloat = 0
    @State var isNotchFileDropTargeted = false
    @State var isBoxDropTargeted = false
    @State var selectedBoxFileIDs = Set<UUID>()
    @State private var isAddAppPresented = false
    @State private var isAddBookmarkPresented = false
    @State private var animatingFromPage: Int? = nil
    
    @AppStorage(AppStorageKey.peekerAlignment) private var peekerAlignment = 0
    
    var isSlimModeActive: Bool {
        isSlimBoxInstance
    }
    
    private var peekerOverlayAlignment: Alignment {
        switch peekerAlignment {
        case 1: return .bottomLeading
        case 2: return .bottomTrailing
        default: return .bottom
        }
    }
    
    @ViewBuilder
    private func peekerWidgetOverlay(isPeekerVisible: Bool) -> some View {
        if isPeekerVisible {
            HStack(spacing: 8) {
                PeekerWidgetView(
                    apps: model.launcherApps,
                    bookmarks: model.bookmarkItems,
                    showApps: settings.showLauncherInPeeker,
                    showBookmarks: settings.showBookmarksInPeeker,
                    accentColor: Color(settings.accentColor),
                    itemSize: settings.peekerSize
                )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 8)
            .padding(.leading, peekerAlignment == 1 ? 16 : 0)
            .padding(.trailing, peekerAlignment == 2 ? 16 : 0)
        }
    }
    
    var activePages: [IslandPage] {
        if isSlimModeActive {
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
    
    
    let pageTopContentInset: CGFloat = 2
    
    // This preference key is used to report the animated height of the island back to the AppDelegate.
    struct ShellHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    func updateCloseProgress(_ progress: CGFloat, animate: Bool) {
        let clamped = max(0, min(1, progress))
        if clamped >= 1, model.isExpanded, !model.isPinned {
            DispatchQueue.main.async {
                closeNotchFromSwipe()
            }
        }
        if animate {
            if clamped == 0 {
                withAnimation(.easeOut(duration: 0.05)) {
                    model.closeGestureProgress = clamped
                }
            } else {
                withAnimation(settings.swipeAnimation) {
                    model.closeGestureProgress = clamped
                }
            }
        } else {
            model.closeGestureProgress = clamped
        }
    }
    
    func closeNotchFromSwipe() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.closeNotchFromSwipe()
        }
    }
    
    private func previewBadge(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.35)))
            .overlay(Capsule().stroke(accent.opacity(0.7), lineWidth: 1))
    }
    
    private func previewTitleSample(page: IslandPage, width: CGFloat) -> some View {
        let size = settings.titleSize(for: page)
        let color = Color(settings.titleColor(for: page))
        let alignment = settings.titleAlignment(for: page).alignment
        return Text("Title")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
            .frame(width: width, alignment: alignment)
    }
    
    private var slimBoxMenuBarControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    if selectedBoxFileIDs.count == model.boxFiles.count {
                        selectedBoxFileIDs.removeAll()
                    } else {
                        selectedBoxFileIDs = Set(model.boxFiles.map { $0.id })
                    }
                }
            } label: {
                Image(systemName: selectedBoxFileIDs.count == model.boxFiles.count ? "bookmark.slash.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(selectedBoxFileIDs.count == model.boxFiles.count ? "Deselect All" : "Select All")
            
            Button {
                withAnimation {
                    if selectedBoxFileIDs.isEmpty {
                        model.boxFiles.removeAll()
                        selectedBoxFileIDs.removeAll()
                    } else {
                        model.boxFiles.removeAll { selectedBoxFileIDs.contains($0.id) }
                        selectedBoxFileIDs.removeAll()
                    }
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(selectedBoxFileIDs.isEmpty ? "Clear All" : "Clear Selected")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .padding(6)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.clear
                
                if isSlimBoxInstance || model.isContentActive || ((model.isStopwatchRunning || model.isTimerRunning) && !settings.disableChronoHUD) {
                    activeIslandContent
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var activeIslandContent: some View {
        let currentSlimWidth: CGFloat = model.slimBoxWidth
        let currentSlimHeight: CGFloat = model.slimBoxHeight
        
        let panelWidth: CGFloat = isSlimModeActive ? currentSlimWidth : scaledPanelWidth(for: settings)
        let panelHeight: CGFloat = isSlimModeActive ? currentSlimHeight : scaledPanelHeight(for: settings)
        
        let notchWidth: CGFloat = isSlimModeActive ? 0 : settings.effectiveNotchWidth
        let notchHeight: CGFloat = isSlimModeActive ? 0 : settings.effectiveNotchHeight
        let rawProgress: CGFloat = isSlimModeActive ? 1.0 : model.expansionProgress
        let progress: CGFloat = rawProgress.isFinite ? max(0, min(1, rawProgress)) : 0
        let easedProgress: CGFloat = progress * progress * (3 - 2 * progress)
        
        let showStopwatch: Bool = model.isStopwatchRunning && !settings.disableChronoHUD
        let showTimer: Bool = model.isTimerRunning && !settings.disableChronoHUD
        let targetLeftExt: CGFloat = showStopwatch ? 100 : 0
        let targetRightExt: CGFloat = showTimer ? 100 : 0
        let activeLeftExt: CGFloat = targetLeftExt * (1 - easedProgress)
        let activeRightExt: CGFloat = targetRightExt * (1 - easedProgress)
        
        let baseRawShellWidth: CGFloat = notchWidth + ((panelWidth - notchWidth) * easedProgress)
        let rawShellWidth: CGFloat = isSlimModeActive ? panelWidth : max(baseRawShellWidth, notchWidth + activeLeftExt + activeRightExt)
        let rawShellHeight: CGFloat = notchHeight + ((panelHeight - notchHeight) * easedProgress)
        let shellWidth: CGFloat = safeDimension(rawShellWidth, fallback: panelWidth)
        let shellHeight: CGFloat = safeDimension(rawShellHeight, fallback: panelHeight)
        let baseIslandWidth: CGFloat = notchWidth + ((panelWidth - notchWidth) * easedProgress * 0.4)
        let islandWidth: CGFloat = baseIslandWidth + activeLeftExt + activeRightExt
        let targetIslandWidth: CGFloat = notchWidth + ((panelWidth - notchWidth) * 0.4)
        let islandOffset: CGFloat = (activeRightExt - activeLeftExt) / 2
        let islandHeight: CGFloat = notchHeight
        let pagerRowHeight: CGFloat = (settings.showPagers && !isSlimModeActive) ? 14 : 0
        let pagerBottomInset: CGFloat = (settings.showPagers && !isSlimModeActive) ? 8 : 0
        let pagerReservedHeight: CGFloat = 0 // Don't reserve height; float it on top
        let isPeekerVisible: Bool = !isSlimModeActive && ((settings.showLauncherInPeeker && !model.launcherApps.isEmpty) ||
                                                          (settings.showBookmarksInPeeker && !model.bookmarkItems.isEmpty))
        let peekerHeight: CGFloat = 0 // Floating on top
        let contentAreaHeight: CGFloat = max(1, panelHeight - notchHeight - pagerReservedHeight - (isSlimModeActive ? 0 : 2))
        let cornerRadius: CGFloat = safeDimension(max(4, settings.cornerRadius * (0.6 + 0.4 * easedProgress)), fallback: 8)
        let contentProgress: CGFloat = easedProgress.isFinite ? max(0, min(1, (easedProgress - 0.18) / 0.82)) : 0
        let showToastOnly: Bool = (model.observedFileToast != nil || model.isToastDismissing) && !model.isExpanded && !model.isPinned
        let isFloatingPagerActive: Bool = settings.pagerStyle == 1 && settings.showPagers && !isSlimModeActive
        let bottomPagerSpacing: CGFloat = (isFloatingPagerActive && settings.pagerAlignment == 0) ? settings.pagerSpacing : 8
        let floatingPagerHeightAdjustment: CGFloat = (isFloatingPagerActive && settings.pagerAlignment == 0) ? (bottomPagerSpacing * easedProgress + (settings.pagerSize + 22) * easedProgress) : 0
        
        let baseContainerHeight: CGFloat = {
            var height: CGFloat = isSlimModeActive ? currentSlimHeight : (showToastOnly ? max(panelHeight, toastPanelHeight) : panelHeight)
            if isFloatingPagerActive && settings.pagerAlignment != 0 {
                let activePagesCount = CGFloat(activePages.count)
                let verticalPagerHeight = (activePagesCount * settings.pagerSize) + ((activePagesCount - 1) * 12) + 20 + 16
                height = max(height, verticalPagerHeight)
            }
            return height
        }()
        
        let containerHeight: CGFloat = safeDimension(baseContainerHeight + floatingPagerHeightAdjustment, fallback: panelHeight)
        let toastWidth: CGFloat = toastPanelWidth
        let sidePagerWidth: CGFloat = (isFloatingPagerActive && settings.pagerAlignment != 0) ? (settings.pagerSize * 2 + settings.pagerSpacing * 2) * 2 : 0
        let containerWidth: CGFloat = isSlimModeActive ? currentSlimWidth : panelWidth + sidePagerWidth
        let closeProgress: CGFloat = max(0, min(1, model.closeGestureProgress))
        let closeEase: CGFloat = closeProgress * closeProgress * (3 - 2 * closeProgress)
        let closeOffset: CGFloat = -44 * closeEase
        let closeScale: CGFloat = 1 - (0.14 * closeEase)
        let shouldRenderExpandedContent: Bool = model.isExpanded || model.isPinned || isSlimModeActive
        
        ZStack(alignment: .top) {
            // Overlay previews so they don't impact the measured height of the island body
            if settings.showHoverPreviews && !isSlimModeActive {
                settingsPreviewOverlay
                    .zIndex(100)
            }
            
            if let toast = model.observedFileToast {
                ObservedFileToastView(
                    toast: toast,
                    progress: easedProgress,
                    onClose: {
                        withAnimation(settings.notchOpenAnimation) {
                            model.expansionProgress = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.dismissToastAndHideNotch()
                            } else {
                                model.observedFileToast = nil
                            }
                        }
                    },
                    baseWidth: toastWidth,
                    baseHeight: notchHeight,
                    expandedHeight: toastPanelHeight,
                    backgroundColor: Color(settings.backgroundColor),
                    cornerRadius: settings.cornerRadius
                )
                .offset(y: baseNotchHeight - 2)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ShellHeightKey.self, value: proxy.size.height + (baseNotchHeight - 2))
                })
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
            
            if !showToastOnly {
                VStack(spacing: bottomPagerSpacing * easedProgress) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            // UNIFIED FIX: Pad internal layouts to offset default top window inset masking values
                            if !isSlimModeActive {
                                ZStack {
                                    Capsule()
                                        .fill(Color(nsColor: settings.backgroundColor.withAlphaComponent(1.0)))
                                        .frame(width: islandWidth, height: islandHeight)
                                    
                                    
                                    if !model.isExpanded && !model.isPinned {
                                        closedIslandChronoWidgets(islandWidth: islandWidth, islandHeight: islandHeight, leftExt: activeLeftExt, rightExt: activeRightExt)
                                    }
                                }
                                .compositingGroup()
                                .frame(width: islandWidth, height: islandHeight)
                                .padding(.top, 0)
                                .overlay {
                                    ZStack {
                                        globalTitleOverlay(islandWidth: containerWidth, islandHeight: islandHeight)
                                            .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                                            .allowsHitTesting(shouldRenderExpandedContent)
                                        globalControlsOverlay(islandWidth: containerWidth, islandHeight: islandHeight)
                                            .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                                            .allowsHitTesting(shouldRenderExpandedContent)
                                    }
                                    .frame(width: containerWidth, height: islandHeight)
                                }
                            }
                            
                            let pages = activePages
                            CarouselContainer(isSlimBoxInstance: isSlimBoxInstance, currentPage: model.currentPage, panelWidth: panelWidth) {
                                HStack(spacing: 0) {
                                    ForEach(0..<pages.count, id: \.self) { index in
                                        let resolvedCurrentPage = isSlimBoxInstance ? 0 : model.currentPage
                                        if shouldRenderExpandedContent && (index == resolvedCurrentPage || index == animatingFromPage) {
                                            pageView(for: pages[index], contentAreaHeight: contentAreaHeight)
                                                .frame(width: panelWidth, height: contentAreaHeight, alignment: .top)
                                                .clipped()
                                        } else {
                                            Color.clear
                                                .frame(width: panelWidth, height: contentAreaHeight, alignment: .top)
                                        }
                                    }
                                }
                                .frame(width: panelWidth, height: contentAreaHeight, alignment: .leading)
                            }
                            .padding(.top, 2)
                            .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                            .allowsHitTesting(shouldRenderExpandedContent)
                            .overlay(alignment: peekerOverlayAlignment) {
                                peekerWidgetOverlay(isPeekerVisible: isPeekerVisible)
                                    .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                                    .allowsHitTesting(shouldRenderExpandedContent)
                            }
                            
                            if settings.showPagers && !isSlimModeActive && settings.pagerStyle == 0 {
                                HStack(spacing: 8) {
                                    ForEach(0..<pages.count, id: \.self) { index in
                                        Button {
                                            setPageFromCarousel(index)
                                        } label: {
                                            Capsule(style: .continuous)
                                                .fill(model.currentPage == index ? Color.white : Color.white.opacity(0.28))
                                                .frame(width: model.currentPage == index ? 24 : 14, height: 4)
                                                .padding(.vertical, 8)
                                                .padding(.horizontal, 4)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: pagerRowHeight)
                                .opacity(easedProgress)
                                .padding(.bottom, pagerBottomInset)
                                .offset(y: -(panelHeight - notchHeight - settings.clampedNotchEdgeThickness) * (1 - (model.isExpanded || model.isPinned ? easedProgress : 0)))
                                .allowsHitTesting(shouldRenderExpandedContent)
                            }
                        }
                        .frame(width: panelWidth, height: panelHeight, alignment: .top)
                        .frame(width: shellWidth, height: shellHeight, alignment: .top)
                        .conditionalClip(clipAll: isSlimModeActive, cornerRadius: cornerRadius)
                        .background(
                            Group {
                                if isSlimModeActive {
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .fill(Color(settings.backgroundColor))
                                        .shadow(color: Color.black.opacity(shouldRenderExpandedContent ? 0.22 : 0),
                                                radius: shouldRenderExpandedContent ? 18 : 0, x: 0, y: shouldRenderExpandedContent ? 10 : 0)
                                } else {
                                    BottomRoundedRectangle(cornerRadius: cornerRadius)
                                        .fill(Color(settings.backgroundColor))
                                        .shadow(color: Color.black.opacity(shouldRenderExpandedContent ? 0.22 : 0),
                                                radius: shouldRenderExpandedContent ? 18 : 0, x: 0, y: shouldRenderExpandedContent ? 10 : 0)
                                }
                            }
                        )
                    .overlay(alignment: .bottom) {
                        if settings.showPagers && !isSlimModeActive && settings.pagerStyle == 0 {
                            let pages = activePages
                            HStack(spacing: 8) {
                                ForEach(0..<pages.count, id: \.self) { index in
                                    Button {
                                        setPageFromCarousel(index)
                                    } label: {
                                        Capsule(style: .continuous)
                                            .fill(model.currentPage == index ? Color.white : Color.white.opacity(0.28))
                                            .frame(width: model.currentPage == index ? 24 : 14, height: 4)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 4)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: pagerRowHeight)
                            .opacity(easedProgress)
                            .padding(.bottom, pagerBottomInset + peekerHeight)
                            .allowsHitTesting(shouldRenderExpandedContent)
                        }
                    }
                        .animation(settings.notchOpenAnimation, value: model.expansionProgress)
                        .overlay(alignment: settings.pagerAlignment == 1 ? .topLeading : .topTrailing) {
                            if isFloatingPagerActive && settings.pagerAlignment != 0 {
                                floatingPagerView(pages: activePages, isVertical: true)
                                    .opacity(easedProgress)
                                    .scaleEffect(0.6 + 0.4 * easedProgress)
                                    .offset(x: settings.pagerAlignment == 1 ? -(settings.pagerSize + settings.pagerSpacing) : (settings.pagerSize + settings.pagerSpacing), y: 0)
                            }
                        }
                    }
                    
                    if isFloatingPagerActive && settings.pagerAlignment == 0 {
                        floatingPagerView(pages: activePages, isVertical: false)
                            .opacity(easedProgress)
                            .scaleEffect(0.6 + 0.4 * easedProgress)
                            .frame(height: (settings.pagerSize + 22) * easedProgress)
                    }
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ShellHeightKey.self, value: proxy.size.height)
                })
                .offset(x: islandOffset)
                // Apply interactive features ONLY to the tight visual components
                .simultaneousGesture(isSlimModeActive ? nil : horizontalPagingGesture)
                .contextMenu {
                    SettingsLink { Text("Settings") }
                }
                .onDrop(of: [.fileURL], isTargeted: $isNotchFileDropTargeted, perform: handleNotchFileDrop)
            } // End if !showToastOnly
        } // End ZStack
        .frame(width: containerWidth, height: containerHeight, alignment: .top)
        .overlay(alignment: .topLeading) {
            if isSlimModeActive {
                if !model.boxFiles.isEmpty && settings.boxSlimModeKeepOpen {
                    slimBoxMenuBarControls
                        .zIndex(50)
                }
            }
        }
        .scaleEffect(closeScale, anchor: .top)
        .offset(y: closeOffset)
        .onChange(of: isNotchFileDropTargeted) { _, targeted in
            if targeted {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.openBoxPage()
                }
            }
        }
        .onChange(of: isAddBookmarkPresented) { _, newValue in
            model.isAddSheetOpen = newValue
        }
        .onChange(of: isAddAppPresented) { _, newValue in
            model.isAddSheetOpen = newValue
        }
        .onChange(of: model.currentPage) { oldValue, newValue in
            animatingFromPage = oldValue
            // Issue 7: Reduce from 400ms to 220ms — the spring (response: 0.32) settles in ~240ms.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                if animatingFromPage == oldValue {
                    animatingFromPage = nil
                }
            }
        }
        .onReceive(model.$currentPage) { newValue in
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.updateObservationState(for: newValue)
            }
            unloadInactivePageState(activePage: newValue)
        }
        .onReceive(model.$isExpanded) { expanded in
            if !expanded {
                unloadCollapsedPageState()
            }
        }
    }
    
    @ViewBuilder
    private var settingsPreviewOverlay: some View {
        GeometryReader { geo in
            let edgeNotchWidth = settings.effectiveNotchWidth
            let edgeNotchHeight = settings.effectiveNotchHeight
            let edge = settings.clampedNotchEdgeThickness
            let approachWidth = settings.clampedApproachWidth
            let approachHeight = settings.clampedApproachHeight
            let focus = settings.hoverPreviewFocus
            let accent = Color(settings.accentColor)
            let edgeNotchX = (geo.size.width - edgeNotchWidth) / 2
            let edgeNotchRect = CGRect(x: edgeNotchX, y: 0, width: edgeNotchWidth, height: edgeNotchHeight)
            let edgeInset = max(0, edge)
            let outerRect = edgeNotchRect.insetBy(dx: -edgeInset, dy: -edgeInset)
            let approachRect = CGRect(
                x: edgeNotchRect.minX - edgeInset - approachWidth,
                y: edgeNotchRect.maxY + edgeInset,
                width: edgeNotchRect.width + (edgeInset * 2) + approachWidth * 2,
                height: approachHeight
            )
            let clipboardLimitText = settings.clampedRememberClips == 0 ? "Unlimited" : "\(settings.clampedRememberClips)"
            let previewY = edgeNotchRect.maxY + 28
            let innerRadius = settings.cornerRadius * 0.6
            
            ZStack(alignment: .topLeading) {
                Group {
                    switch focus {
                    case .all:
                        if (approachHeight > 0 || approachWidth > 0) && settings.enableApproach {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                                .frame(width: approachRect.width, height: approachRect.height)
                                .position(x: approachRect.midX, y: approachRect.midY)
                        }
                        if edgeInset > 0 {
                            BottomRoundedRectangle(cornerRadius: innerRadius + edgeInset)
                                .fill(accent.opacity(0.45))
                                .frame(width: outerRect.width, height: outerRect.height)
                                .position(x: outerRect.midX, y: outerRect.midY)
                        }
                        BottomRoundedRectangle(cornerRadius: innerRadius)
                            .fill(Color(settings.backgroundColor))
                            .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                            .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                        BottomRoundedRectangle(cornerRadius: innerRadius)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                            .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                    case .islandSize:
                        EmptyView()
                    case .notchEdge:
                        if edgeInset > 0 {
                            BottomRoundedRectangle(cornerRadius: innerRadius + edgeInset)
                                .fill(accent.opacity(0.55))
                                .frame(width: outerRect.width, height: outerRect.height)
                                .position(x: outerRect.midX, y: outerRect.midY)
                        }
                        BottomRoundedRectangle(cornerRadius: innerRadius)
                            .fill(Color(settings.backgroundColor))
                            .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                            .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                        BottomRoundedRectangle(cornerRadius: innerRadius)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                            .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                    case .approach:
                        if (approachHeight > 0 || approachWidth > 0) && settings.enableApproach {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                                .frame(width: approachRect.width, height: approachRect.height)
                                .position(x: approachRect.midX, y: approachRect.midY)
                        }
                    case .clipboardLimit:
                        previewBadge("Clip limit \(clipboardLimitText)", accent: accent)
                            .position(x: edgeNotchRect.midX, y: previewY)
                    case .titleSize:
                        previewTitleSample(page: settings.hoverPreviewTitlePage, width: edgeNotchRect.width)
                            .position(x: edgeNotchRect.midX, y: previewY)
                    case .cornerRadius:
                        RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 2)
                            .frame(width: 140, height: 52)
                            .position(x: edgeNotchRect.midX, y: previewY)
                    case .sensitivityCarousel:
                        previewBadge("Carousel sensitivity \(String(format: "%.2f", settings.carouselSensitivity))", accent: accent)
                            .position(x: edgeNotchRect.midX, y: previewY)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .opacity(0.8)
        .padding(.top, 4)
        .drawingGroup()
    }
    
    private func symbolForPage(_ page: IslandPage) -> String {
        switch page {
        case .clipboard: return "doc.on.clipboard"
        case .jot: return "note.text"
        case .box: return "shippingbox.fill"
        case .chrono: return "timer"
        case .calendar: return "calendar"
        case .launcher: return "app.fill"
        case .bookmarks: return "globe"
        case .customCombined: return "square.grid.2x2.fill"
        }
    }
    
    private func floatingPagerView(pages: [IslandPage], isVertical: Bool) -> some View {
        let pSize = settings.pagerSize
        let content = ForEach(0..<pages.count, id: \.self) { index in
            let page = pages[index]
            let isSelected = model.currentPage == index
            
            Button {
                setPageFromCarousel(index)
            } label: {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.15))
                        .frame(width: isSelected ? pSize * 0.93 : pSize * 0.75, height: isSelected ? pSize * 0.93 : pSize * 0.75)
                        .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0), radius: 3)
                    
                    Image(systemName: symbolForPage(page))
                        .font(.system(size: isSelected ? pSize * 0.37 : pSize * 0.31, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? Color.black : Color.white.opacity(0.8))
                }
                .frame(width: pSize, height: pSize)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.currentPage)
        }
        
        return Group {
            if isVertical { VStack(spacing: 12) { content } } else { HStack(spacing: 12) { content } }
        }
        .padding(.horizontal, isVertical ? 6 : 10)
        .padding(.vertical, isVertical ? 10 : 6)
        .background(
            Group {
                if settings.pagerStyle2BackgroundEnabled {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(Capsule()))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
        .padding(isVertical ? .top : .bottom, 6)
    }
    
    @ViewBuilder
    private func pageView(for page: IslandPage, contentAreaHeight: CGFloat) -> some View {
        switch page {
        case .clipboard:
            clipboardPage(contentAreaHeight: contentAreaHeight)
        case .jot:
            sidebarPage(contentAreaHeight: contentAreaHeight)
        case .box:
            boxPage(contentAreaHeight: contentAreaHeight)
        case .chrono:
            chronoPage(contentAreaHeight: contentAreaHeight)
        case .calendar:
            calendarPage(contentAreaHeight: contentAreaHeight)
        case .launcher:
            launcherPage(contentAreaHeight: contentAreaHeight)
        case .bookmarks:
            bookmarksPage(contentAreaHeight: contentAreaHeight)
        case .customCombined:
            customCombinedPage(contentAreaHeight: contentAreaHeight)
        }
    }
    
    private var horizontalPagingGesture: some Gesture {
        let pagesCount = activePages.count
        return DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 40 else { return }
                let nextPage = value.translation.width < 0
                ? min(pagesCount - 1, model.currentPage + 1)
                : max(0, model.currentPage - 1)
                setPageFromCarousel(nextPage)
            }
    }
    
    private func setPageFromCarousel(_ page: Int) {
        let pagesCount = activePages.count
        let nextPage = clamp(page, min: 0, max: pagesCount - 1)
        SwipeState.shared.carouselDragOffset = 0
        withAnimation(settings.carouselAnimation) {
            model.currentPage = nextPage
        }
    }
    
    private func unloadInactivePageState(activePage: Int) {
        let pages = activePages
        guard pages.indices.contains(activePage) else { return }
        let resolvedPage = pages[activePage]
        
        // Clipboard-only transient UI should reset when the clipboard page is inactive.
        if resolvedPage != .clipboard {
            highlightedClipboardID = nil
            clipboardTapFeedbackProgress = 0
        }
        
        // Cancel box preview work only when the Box page is inactive.
        // We deliberately do NOT trim the shared NSCache here — it has its own
        // count/cost limits and a memory-pressure handler.
        if resolvedPage != .box {
            BoxIconCache.shared.cancelQueuedPreviewLoads()
            selectedBoxFileIDs.removeAll()
        }
        
        if resolvedPage != .jot {
            isJotEditorFocused = false
        }
    }
    
    private func unloadCollapsedPageState() {
        unloadInactivePageState(activePage: -1)
        BoxIconCache.shared.cancelQueuedPreviewLoads()
        if model.isFolderSlotsOpen {
            FolderSlotsManager.shared.close()
            model.isFolderSlotsOpen = false
        }
    }
    
    func emptyDismissableScrollView<Content: View>(
        onMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DismissableScrollView(
            closeSensitivity: settings.clampedCloseSensitivity,
            onOverscrollProgress: { progress, animate in
                updateCloseProgress(progress, animate: animate)
            },
            onBottomOverscroll: { closeNotchFromSwipe() },
            onMetricsChange: { offset, contentHeight, viewportHeight in
                onMetricsChange(offset, contentHeight, viewportHeight)
            }
        ) {
            content()
        }
    }
    
    // MARK: - Drop Handling
    func handleNotchFileDrop(providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers: providers, openBoxPage: true)
    }
    
    func handleBoxDrop(providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers: providers, openBoxPage: false)
    }
    
    func handleFileDrop(providers: [NSItemProvider], openBoxPage: Bool) -> Bool {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.slimBoxDidReceiveDropThisSession = true
        }
        let acceptedProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !acceptedProviders.isEmpty else { return false }
        
        let loadGroup = DispatchGroup()
        let resultLock = NSLock()
        var droppedURLs: [URL] = []
        
        for provider in acceptedProviders {
            loadGroup.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { loadGroup.leave() }
                guard let fileUrl = url else { return }
                resultLock.lock()
                droppedURLs.append(fileUrl)
                resultLock.unlock()
            }
        }
        
        loadGroup.notify(queue: .main) {
            let existing = Set(model.boxFiles.map(\.url))
            var seen = Set<URL>()
            var urlsToInsert: [URL] = []
            
            for url in droppedURLs where !existing.contains(url) {
                if seen.insert(url).inserted {
                    urlsToInsert.append(url)
                }
            }
            
            if !urlsToInsert.isEmpty {
                model.boxFiles.insert(contentsOf: urlsToInsert.reversed().map(BoxFile.init(url:)), at: 0)
            }
            
            if model.boxSlimModeActive {
                if !settings.boxSlimModeKeepOpen {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.hidePanel()
                    }
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.slimBoxWindow?.makeKeyAndOrderFront(nil)
                    }
                }
            } else if openBoxPage {
                if let idx = activePages.firstIndex(of: .box) {
                    model.currentPage = idx
                }
                model.isExpanded = true
                model.expansionProgress = 1.0
            }
        }
        
        return true
    }
    
    // MARK: - Shared UI
    @ViewBuilder
    private func headerControls<Content: View>(@ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Spacer()
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
    
    private func globalControlsOverlay(islandWidth: CGFloat, islandHeight: CGFloat) -> some View {
        let page = activePages.indices.contains(model.currentPage) ? activePages[model.currentPage] : .clipboard
        let edgeNotchWidth = settings.effectiveNotchWidth
        let alignmentOption = settings.titleAlignment(for: page)
        
        return Color.clear
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let notchLeft = (geo.size.width - edgeNotchWidth) / 2
                    let notchRight = (geo.size.width + edgeNotchWidth) / 2
                    
                    if page == .customCombined {
                        VStack(alignment: .leading, spacing: 2) {
                            let bName = model.bookmarksCurrentFolderID != nil ? (model.bookmarkItems.first(where: { $0.id == model.bookmarksCurrentFolderID })?.name ?? "Folder") : settings.titleText(for: .bookmarks)
                            let bSym = model.bookmarksCurrentFolderID != nil ? "folder.fill" : settings.titleSymbol(for: .bookmarks, fallback: "globe")
                            
                            if model.bookmarksCurrentFolderID != nil {
                                HStack(spacing: 4) {
                                    if settings.showTitleIcon(for: .bookmarks) {
                                        Image(systemName: bSym)
                                            .foregroundColor(Color(settings.titleColor(for: .bookmarks)))
                                            .font(.system(size: settings.titleSize(for: .bookmarks), weight: .bold))
                                    }
                                    TextField("Folder", text: Binding(
                                        get: { model.bookmarkItems.first(where: { $0.id == model.bookmarksCurrentFolderID })?.name ?? "Folder" },
                                        set: { newValue in
                                            if let idx = model.bookmarkItems.firstIndex(where: { $0.id == model.bookmarksCurrentFolderID }) {
                                                model.bookmarkItems[idx].name = newValue
                                                persistBookmarkItems(model.bookmarkItems)
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.plain)
                                    .font(.system(size: settings.titleSize(for: .bookmarks), weight: .bold))
                                    .foregroundColor(Color(settings.titleColor(for: .bookmarks)))
                                }
                            } else {
                                Label(bName, systemImage: bSym)
                                    .conditionalLabelStyle(showIcon: settings.showTitleIcon(for: .bookmarks))
                                    .font(.system(size: settings.titleSize(for: .bookmarks), weight: .bold))
                                    .foregroundColor(Color(settings.titleColor(for: .bookmarks)))
                            }
                            
                            HStack(spacing: 12) {
                                if model.bookmarksCurrentFolderID != nil {
                                    Button {
                                        withAnimation { model.bookmarksCurrentFolderID = nil }
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.8))
                                            .padding(6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                if settings.showAddBookmarkButton {
                                    Button {
                                        model.isAddSheetOpen = true
                                        isAddBookmarkPresented = true
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.8))
                                            .padding(6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $isAddBookmarkPresented, arrowEdge: .bottom) {
                                        AddBookmarkSheet(isPresented: Binding(
                                            get: { self.isAddBookmarkPresented },
                                            set: { newValue in
                                                self.isAddBookmarkPresented = newValue
                                                if !newValue { self.model.isAddSheetOpen = false }
                                            }
                                        ), onAdd: { bookmark in
                                            var newBookmark = bookmark
                                            newBookmark.parentId = model.bookmarksCurrentFolderID
                                            model.bookmarkItems.append(newBookmark)
                                            persistBookmarkItems(model.bookmarkItems)
                                            
                                            fetchFaviconBase64(for: bookmark.urlString) { base64 in
                                                if let base64 = base64 {
                                                    DispatchQueue.main.async {
                                                        if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                                            model.bookmarkItems[idx].iconBase64 = base64
                                                            persistBookmarkItems(model.bookmarkItems)
                                                        }
                                                    }
                                                }
                                            }
                                        })
                                    }
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: max(0, geo.size.width - notchRight - 16), alignment: .leading)
                        .offset(x: notchRight + 12, y: 2)
                    } else {
                        let controls = HStack {
                                switch page {
                                case .clipboard:
                                    if !model.clipboardItems.isEmpty {
                                        Button {
                                            clearClipboardHistory()
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.white.opacity(0.7))
                                                .padding(6)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                case .jot:
                                    HStack(spacing: 12) {
                                        Button {
                                            if model.activeJotID == nil {
                                                createJot()
                                            } else {
                                                closeActiveJot()
                                            }
                                        } label: {
                                            Image(systemName: model.activeJotID == nil ? "plus" : "chevron.left")
                                                .foregroundColor(.white)
                                                .padding(6)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if model.activeJotID != nil {
                                            Button {
                                                exportActiveJot()
                                            } label: {
                                                Image(systemName: "square.and.arrow.down")
                                                    .foregroundColor(.white)
                                                    .padding(6)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                case .box:
                                    if !model.boxFiles.isEmpty || (settings.enableFolderSlots && !settings.folderSlotsPaths.isEmpty) {
                                        if !model.boxFiles.isEmpty {
                                            VStack(alignment: alignmentOption == .left ? .leading : .trailing, spacing: -4) {
                                                HStack(spacing: 12) {
                                                    Button {
                                                        DispatchQueue.main.async {
                                                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                                                if selectedBoxFileIDs.count == model.boxFiles.count {
                                                                    selectedBoxFileIDs.removeAll()
                                                                } else {
                                                                    selectedBoxFileIDs = Set(model.boxFiles.map { $0.id })
                                                                }
                                                            }
                                                        }
                                                    } label: {
                                                        Text(selectedBoxFileIDs.count == model.boxFiles.count ? "Deselect" : "Select All")
                                                            .font(.caption)
                                                            .foregroundColor(.white.opacity(0.85))
                                                            .padding(6)
                                                            .contentShape(Rectangle())
                                                    }
                                                    .buttonStyle(.plain)
                                                    
                                                    Button {
                                                        DispatchQueue.main.async {
                                                            withAnimation {
                                                                if selectedBoxFileIDs.isEmpty {
                                                                    model.boxFiles.removeAll()
                                                                    selectedBoxFileIDs.removeAll()
                                                                } else {
                                                                    model.boxFiles.removeAll { selectedBoxFileIDs.contains($0.id) }
                                                                    selectedBoxFileIDs.removeAll()
                                                                }
                                                            }
                                                        }
                                                    } label: {
                                                        Text(selectedBoxFileIDs.isEmpty ? "Clear" : "Clear Selected")
                                                            .font(.caption)
                                                            .foregroundColor(.red.opacity(0.9))
                                                            .padding(6)
                                                            .contentShape(Rectangle())
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                
                                                if settings.enableFolderSlots && !settings.folderSlotsPaths.isEmpty {
                                                    Button {
                                                        model.isFolderSlotsOpen.toggle()
                                                        if model.isFolderSlotsOpen {
                                                            FolderSlotsManager.shared.open(anchor: .zero, model: model, settings: settings)
                                                        } else {
                                                            FolderSlotsManager.shared.close()
                                                        }
                                                    } label: {
                                                        Image(systemName: "text.below.folder.fill")
                                                            .font(.system(size: 13, weight: .semibold))
                                                            .foregroundColor(model.isFolderSlotsOpen ? Color(settings.accentColor) : .white.opacity(0.85))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 4)
                                                            .contentShape(Rectangle())
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        } else {
                                            if settings.enableFolderSlots && !settings.folderSlotsPaths.isEmpty {
                                                Button {
                                                    model.isFolderSlotsOpen.toggle()
                                                    if model.isFolderSlotsOpen {
                                                        FolderSlotsManager.shared.open(anchor: .zero, model: model, settings: settings)
                                                    } else {
                                                        FolderSlotsManager.shared.close()
                                                    }
                                                } label: {
                                                    Image(systemName: "text.below.folder.fill")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundColor(model.isFolderSlotsOpen ? Color(settings.accentColor) : .white.opacity(0.85))
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                case .chrono:
                                    EmptyView()
                                case .launcher:
                                     HStack(spacing: 12) {
                                         if model.launcherCurrentFolderID != nil {
                                             Button {
                                                 withAnimation { model.launcherCurrentFolderID = nil }
                                             } label: {
                                                 Image(systemName: "chevron.left")
                                                     .foregroundColor(.white)
                                                     .padding(6)
                                                     .contentShape(Rectangle())
                                             }
                                             .buttonStyle(.plain)
                                         }
                                         if settings.showAddAppButton {
                                             Button {
                                                 model.isAddSheetOpen = true
                                                 isAddAppPresented = true
                                             } label: {
                                                 Image(systemName: "plus")
                                                     .foregroundColor(.white)
                                                     .padding(6)
                                                     .contentShape(Rectangle())
                                             }
                                             .buttonStyle(.plain)
                                             .popover(isPresented: $isAddAppPresented, arrowEdge: .bottom) {
                                                 AddAppSheet(isPresented: Binding(
                                                     get: { self.isAddAppPresented },
                                                     set: { newValue in
                                                         self.isAddAppPresented = newValue
                                                         if !newValue { self.model.isAddSheetOpen = false }
                                                     }
                                                 ), onAdd: { app in
                                                     var newApp = app
                                                     newApp.parentId = model.launcherCurrentFolderID
                                                     model.launcherApps.append(newApp)
                                                     persistLauncherApps(model.launcherApps)
                                                 })
                                             }
                                         }
                                     }
                                 case .bookmarks:
                                     HStack(spacing: 12) {
                                         if model.bookmarksCurrentFolderID != nil {
                                             Button {
                                                 withAnimation { model.bookmarksCurrentFolderID = nil }
                                             } label: {
                                                 Image(systemName: "chevron.left")
                                                     .foregroundColor(.white)
                                                     .padding(6)
                                                     .contentShape(Rectangle())
                                             }
                                             .buttonStyle(.plain)
                                         }
                                         if settings.showAddBookmarkButton {
                                             Button {
                                                 model.isAddSheetOpen = true
                                                 isAddBookmarkPresented = true
                                             } label: {
                                                 Image(systemName: "plus")
                                                     .foregroundColor(.white)
                                                     .padding(6)
                                                     .contentShape(Rectangle())
                                             }
                                             .buttonStyle(.plain)
                                             .popover(isPresented: $isAddBookmarkPresented, arrowEdge: .bottom) {
                                                 AddBookmarkSheet(isPresented: Binding(
                                                     get: { self.isAddBookmarkPresented },
                                                     set: { newValue in
                                                         self.isAddBookmarkPresented = newValue
                                                         if !newValue { self.model.isAddSheetOpen = false }
                                                     }
                                                 ), onAdd: { bookmark in
                                                     var newBookmark = bookmark
                                                     newBookmark.parentId = model.bookmarksCurrentFolderID
                                                     model.bookmarkItems.append(newBookmark)
                                                     persistBookmarkItems(model.bookmarkItems)
                                                     
                                                     fetchFaviconBase64(for: bookmark.urlString) { base64 in
                                                         if let base64 = base64 {
                                                             DispatchQueue.main.async {
                                                                 if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                                                     model.bookmarkItems[idx].iconBase64 = base64
                                                                     persistBookmarkItems(model.bookmarkItems)
                                                                 }
                                                             }
                                                         }
                                                     }
                                                 })
                                             }
                                         }
                                     }
                                default:
                                    EmptyView()
                                }
                                }
                                    .fixedSize(horizontal: true, vertical: false)
                                
                                if alignmentOption == .left {
                                    controls
                                        .frame(width: max(0, geo.size.width - notchRight - 16), alignment: .leading)
                                        .offset(x: notchRight + 12, y: 2)
                                } else {
                                    controls
                                        .frame(width: max(0, notchLeft - 12), alignment: .trailing)
                                        .offset(y: 2)
                                }
                        }
                    }
                    .frame(width: islandWidth, height: islandHeight)
            }
    }
                
    func globalTitleOverlay(islandWidth: CGFloat, islandHeight: CGFloat) -> some View {
                    let page = activePages.indices.contains(model.currentPage) ? activePages[model.currentPage] : .clipboard
                    let edgeNotchWidth = settings.effectiveNotchWidth
                    let alignmentOption = settings.titleAlignment(for: page)
                    let title: String
                    let symbol: String
                    
                    switch page {
                    case .clipboard:
                        title = "Clip"
                        symbol = "doc.on.clipboard"
                    case .jot:
                        title = "Jot"
                        symbol = "note.text"
                    case .box:
                        title = "Box"
                        symbol = "shippingbox.fill"
                    case .chrono:
                        title = "Chrono"
                        symbol = "timer"
                    case .calendar:
                        title = "Calendar"
                        symbol = "calendar"
                    case .launcher:
                        if let folderId = model.launcherCurrentFolderID, let folder = model.launcherApps.first(where: { $0.id == folderId }) {
                            title = folder.name
                            symbol = "folder.fill"
                        } else {
                            title = "Launcher"
                            symbol = "app.fill"
                        }
                    case .bookmarks:
                        if let folderId = model.bookmarksCurrentFolderID, let folder = model.bookmarkItems.first(where: { $0.id == folderId }) {
                            title = folder.name
                            symbol = "folder.fill"
                        } else {
                            title = "Bookmarks"
                            symbol = "globe"
                        }
                    default:
                        title = ""
                        symbol = "empty"
                    }
                    
                    return Color.clear
                        .overlay(alignment: .topLeading) {
                            GeometryReader { geo in
                                let notchLeft = (geo.size.width - edgeNotchWidth) / 2
                                let notchRight = (geo.size.width + edgeNotchWidth) / 2
                                
                                if page == .customCombined {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        let lName = model.launcherCurrentFolderID != nil ? (model.launcherApps.first(where: { $0.id == model.launcherCurrentFolderID })?.name ?? "Folder") : settings.titleText(for: .launcher)
                                        let lSym = model.launcherCurrentFolderID != nil ? "folder.fill" : settings.titleSymbol(for: .launcher, fallback: "app.fill")
                                        
                                        if model.launcherCurrentFolderID != nil {
                                            HStack(spacing: 4) {
                                                if settings.showTitleIcon(for: .launcher) {
                                                    Image(systemName: lSym)
                                                        .foregroundColor(Color(settings.titleColor(for: .launcher)))
                                                        .font(.system(size: settings.titleSize(for: .launcher), weight: .bold))
                                                }
                                                TextField("Folder", text: Binding(
                                                    get: { model.launcherApps.first(where: { $0.id == model.launcherCurrentFolderID })?.name ?? "Folder" },
                                                    set: { newValue in
                                                        if let idx = model.launcherApps.firstIndex(where: { $0.id == model.launcherCurrentFolderID }) {
                                                            model.launcherApps[idx].name = newValue
                                                            persistLauncherApps(model.launcherApps)
                                                        }
                                                    }
                                                ))
                                                .textFieldStyle(.plain)
                                                .font(.system(size: settings.titleSize(for: .launcher), weight: .bold))
                                                .foregroundColor(Color(settings.titleColor(for: .launcher)))
                                            }
                                        } else {
                                            Label(lName, systemImage: lSym)
                                                .conditionalLabelStyle(showIcon: settings.showTitleIcon(for: .launcher))
                                                .font(.system(size: settings.titleSize(for: .launcher), weight: .bold))
                                                .foregroundColor(Color(settings.titleColor(for: .launcher)))
                                        }
                                        
                                        HStack(spacing: 12) {
                                            if model.launcherCurrentFolderID != nil {
                                                Button {
                                                    withAnimation { model.launcherCurrentFolderID = nil }
                                                } label: {
                                                    Image(systemName: "chevron.left")
                                                        .foregroundColor(.white)
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            if settings.showAddAppButton {
                                                Button {
                                                    model.isAddSheetOpen = true
                                                    isAddAppPresented = true
                                                } label: {
                                                    Image(systemName: "plus")
                                                        .foregroundColor(.white)
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .popover(isPresented: $isAddAppPresented, arrowEdge: .bottom) {
                                                    AddAppSheet(isPresented: Binding(
                                                        get: { self.isAddAppPresented },
                                                        set: { newValue in
                                                            self.isAddAppPresented = newValue
                                                            if !newValue { self.model.isAddSheetOpen = false }
                                                        }
                                                    ), onAdd: { app in
                                                        var newApp = app
                                                        newApp.parentId = model.launcherCurrentFolderID
                                                        model.launcherApps.append(newApp)
                                                        persistLauncherApps(model.launcherApps)
                                                    })
                                                }
                                            }
                                        }
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: max(0, notchLeft - 12), alignment: .trailing)
                                    .offset(y: 2)
                                } else {
                                    if symbol != "empty" {
                                        let titleView = Group {
                                            if page == .launcher, model.launcherCurrentFolderID != nil {
                                                HStack(spacing: 4) {
                                                    if settings.showTitleIcon(for: .launcher) {
                                                        Image(systemName: symbol)
                                                            .foregroundColor(Color(settings.titleColor(for: .launcher)))
                                                            .font(.system(size: settings.titleSize(for: .launcher), weight: .bold))
                                                    }
                                                    TextField("Folder", text: Binding(
                                                        get: { model.launcherApps.first(where: { $0.id == model.launcherCurrentFolderID })?.name ?? "Folder" },
                                                        set: { newValue in
                                                            if let idx = model.launcherApps.firstIndex(where: { $0.id == model.launcherCurrentFolderID }) {
                                                                model.launcherApps[idx].name = newValue
                                                                persistLauncherApps(model.launcherApps)
                                                            }
                                                        }
                                                    ))
                                                    .textFieldStyle(.plain)
                                                    .font(.system(size: settings.titleSize(for: .launcher), weight: .bold))
                                                    .foregroundColor(Color(settings.titleColor(for: .launcher)))
                                                }
                                            } else if page == .bookmarks, model.bookmarksCurrentFolderID != nil {
                                                HStack(spacing: 4) {
                                                    if settings.showTitleIcon(for: .bookmarks) {
                                                        Image(systemName: symbol)
                                                            .foregroundColor(Color(settings.titleColor(for: .bookmarks)))
                                                            .font(.system(size: settings.titleSize(for: .bookmarks), weight: .bold))
                                                    }
                                                    TextField("Folder", text: Binding(
                                                        get: { model.bookmarkItems.first(where: { $0.id == model.bookmarksCurrentFolderID })?.name ?? "Folder" },
                                                        set: { newValue in
                                                            if let idx = model.bookmarkItems.firstIndex(where: { $0.id == model.bookmarksCurrentFolderID }) {
                                                                model.bookmarkItems[idx].name = newValue
                                                                persistBookmarkItems(model.bookmarkItems)
                                                            }
                                                        }
                                                    ))
                                                    .textFieldStyle(.plain)
                                                    .font(.system(size: settings.titleSize(for: .bookmarks), weight: .bold))
                                                    .foregroundColor(Color(settings.titleColor(for: .bookmarks)))
                                                }
                                            } else {
                                                header(title: title, symbol: symbol, page: page)
                                            }
                                        }
                                        .fixedSize(horizontal: true, vertical: false)
                                        
                                        if alignmentOption == .left {
                                            titleView
                                                .frame(width: max(0, notchLeft - 12), alignment: .trailing)
                                                .offset(y: 2)
                                        } else {
                                            titleView
                                                .frame(width: max(0, geo.size.width - notchRight - 16), alignment: .leading)
                                                .offset(x: notchRight + 12, y: 2)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: islandWidth, height: islandHeight)
                }
                
                func header(title: String, symbol: String, page: IslandPage) -> some View {
                    let displaySymbol = settings.titleSymbol(for: page, fallback: symbol)
                    return Label(settings.titleText(for: page), systemImage: displaySymbol)
                        .conditionalLabelStyle(showIcon: settings.showTitleIcon(for: page))
                        .font(.system(size: settings.titleSize(for: page), weight: .bold))
                        .foregroundColor(Color(settings.titleColor(for: page)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
            }
    
