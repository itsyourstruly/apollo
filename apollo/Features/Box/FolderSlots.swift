import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

// MARK: - Data Models & Workers

struct FolderSlotEntity: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    let url: URL
    let isDirectory: Bool
    let name: String
}

final class FolderSlotsWorker: Sendable {
    static func fetchContents(of url: URL, withSecurityScope securityScope: Bool) async -> [FolderSlotEntity] {
        return await Task.detached(priority: .userInitiated) {
            // Re-assert security scope inside the thread context if necessary
            let accessSecurity = securityScope
            if accessSecurity {
                _ = url.startAccessingSecurityScopedResource()
            }
            
            defer {
                if accessSecurity {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            var entities: [FolderSlotEntity] = []
            let fm = FileManager.default
            do {
                let urls = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                for u in urls {
                    let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    entities.append(FolderSlotEntity(url: u, isDirectory: isDir, name: u.lastPathComponent))
                }
            } catch {
                NSLog("FolderSlotsWorker Error: \(error.localizedDescription)")
            }
            return entities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }
}

// MARK: - Panel Configuration

final class FolderSlotsWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.minSize = NSSize(width: 200, height: 200)
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    deinit {
        NSLog("FolderSlotsWindow deinitialized - Memory released successfully.")
    }
}

final class FolderSlotsHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - Window Manager

@MainActor
final class FolderSlotsManager: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = FolderSlotsManager()
    
    private var panel: FolderSlotsWindow?
    @Published var currentEntities: [FolderSlotEntity] = []
    private var baseEntities: [FolderSlotEntity] = []
    @Published var navigationStack: [URL] = []
    @Published var isNavigating: Bool = false
    private var activeRootURLs: [URL] = []
    private weak var activeModel: NotchMenuModel?
    
    func open(anchor windowRect: CGRect, model: NotchMenuModel, settings: AppSettings) {
        self.activeModel = model
        if self.panel != nil {
            self.panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        var activeURLs: [URL] = []
        var entities: [FolderSlotEntity] = []
        
        for path in settings.folderSlotsPaths {
            var targetURL = URL(fileURLWithPath: path)
            var isSecured = false
            
            if let bookmarkData = UserDefaults.standard.data(forKey: "folder_bookmark_\(path)") {
                var isStale = false
                if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    targetURL = resolvedURL
                    if targetURL.startAccessingSecurityScopedResource() {
                        isSecured = true
                        activeURLs.append(targetURL)
                    }
                }
            }
            
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) {
                entities.append(FolderSlotEntity(url: targetURL, isDirectory: isDir.boolValue, name: targetURL.lastPathComponent))
            } else if isSecured {
                entities.append(FolderSlotEntity(url: targetURL, isDirectory: true, name: targetURL.lastPathComponent))
            }
        }
        
        self.activeRootURLs = activeURLs
        self.baseEntities = entities
        self.currentEntities = entities
        self.navigationStack = []
        self.isNavigating = false
        self.spawnDetachedPanel(settings: settings)
    }
    
    func windowWillClose(_ notification: Notification) {
        self.close(updateModel: true)
    }
    
    func close(updateModel: Bool = true) {
        if let currentSize = panel?.frame.size {
            UserDefaults.standard.set(Double(currentSize.width), forKey: "folderSlotsWindowWidth")
            UserDefaults.standard.set(Double(currentSize.height), forKey: "folderSlotsWindowHeight")
        }
        
        panel?.delegate = nil
        panel?.close()
        panel = nil
        baseEntities.removeAll()
        currentEntities.removeAll()
        navigationStack.removeAll()
        isNavigating = false
        for url in activeRootURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeRootURLs.removeAll()
        
        if updateModel {
            DispatchQueue.main.async {
                self.activeModel?.isFolderSlotsOpen = false
            }
        }
    }
    
    func navigate(to url: URL) {
        isNavigating = true
        navigationStack.append(url)
        Task {
            // Subdirectories of your authorized folder don't need additional Security Scope tokens
            let fetched = await FolderSlotsWorker.fetchContents(of: url, withSecurityScope: false)
            await MainActor.run {
                self.currentEntities = fetched
                self.isNavigating = false
            }
        }
    }
    
    func navigateBack() {
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        
        if let lastURL = navigationStack.last {
            // Re-fetch the parent directory
            navigate(to: lastURL)
        } else {
            self.currentEntities = self.baseEntities
            self.isNavigating = false
        }
    }
    
    private func spawnDetachedPanel(settings: AppSettings) {
        let savedWidth = UserDefaults.standard.double(forKey: "folderSlotsWindowWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "folderSlotsWindowHeight")
        
        let width: CGFloat = savedWidth >= 200 ? CGFloat(savedWidth) : 260
        let height: CGFloat = savedHeight >= 200 ? CGFloat(savedHeight) : 220
        
        // Calculate the Island's approximate frame to position the window
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen()
        let screenRect = screen.frame
        let islandWidth = scaledPanelWidth(for: settings)
        let islandHeight = scaledPanelHeight(for: settings)
        let notchX = settings.hardwareNotchX
        let notchWidth = settings.effectiveNotchWidth
        let islandX = notchX - (islandWidth - notchWidth) / 2
        let islandY = screenRect.maxY - islandHeight
        let islandFrame = CGRect(x: islandX, y: islandY, width: islandWidth, height: islandHeight)
        
        var originX: CGFloat = 0
        var originY: CGFloat = 0
        
        if settings.folderSlotsDirection == 0 { // Left
            originX = islandFrame.minX - width - 40
            originY = screenRect.maxY - height - 40
        } else if settings.folderSlotsDirection == 1 { // Right
            originX = islandFrame.maxX + 40
            originY = screenRect.maxY - height - 40
        } else { // Bottom
            originX = islandFrame.midX - (width / 2)
            originY = islandFrame.minY - height - 12
        }
        
        // Ensure the window stays strictly on-screen if the island is near the edge
        if originX < screenRect.minX + 16 { originX = screenRect.minX + 16 }
        if originX + width > screenRect.maxX - 16 { originX = screenRect.maxX - width - 16 }
        if originY < screenRect.minY + 16 { originY = screenRect.minY + 16 }
        
        let frame = NSRect(x: originX, y: originY, width: width, height: height)
        let newPanel = FolderSlotsWindow(contentRect: frame)
        newPanel.delegate = self
        
        let rootView = FolderSlotsRootView(
            manager: self,
            columns: settings.folderSlotsColumns,
            accentColor: Color(settings.accentColor)
        )
        
        let hostingView = FolderSlotsHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        newPanel.contentView = hostingView
        
        self.panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Grid View

struct FolderSlotsRootView: View {
    @ObservedObject var manager: FolderSlotsManager
    let columns: Int
    let accentColor: Color
    
    @State private var selectedIDs = Set<String>()
    @State private var lastSelectedID: String?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.15), in: Circle())
                    .overlay { WindowControlSurface { manager.close() } }
                
                if !manager.navigationStack.isEmpty {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.15), in: Circle())
                        .overlay {
                            WindowControlSurface {
                                manager.navigateBack()
                                selectedIDs.removeAll()
                                lastSelectedID = nil
                            }
                        }
                }
                
                Text(manager.navigationStack.last?.lastPathComponent ?? "Folder Slots")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accentColor)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            if manager.isNavigating {
                ProgressView().controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.currentEntities.isEmpty {
                Text(manager.navigationStack.isEmpty ? "No folders configured.\nAdd them in Settings." : "Folder is empty.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
                        ForEach(manager.currentEntities) { entity in
                            FolderSlotItemView(
                                entity: entity,
                                isSelected: selectedIDs.contains(entity.id),
                                onSingleClick: { isShiftPressed in
                                    handleSingleClick(on: entity, isShiftPressed: isShiftPressed)
                                },
                                onDoubleClick: {
                                    handleDoubleClick(on: entity)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
    
    private func handleSingleClick(on entity: FolderSlotEntity, isShiftPressed: Bool) {
        if isShiftPressed, let lastID = lastSelectedID,
           let startIndex = manager.currentEntities.firstIndex(where: { $0.id == lastID }),
           let endIndex = manager.currentEntities.firstIndex(where: { $0.id == entity.id }) {
            let lower = min(startIndex, endIndex)
            let upper = max(startIndex, endIndex)
            for i in lower...upper {
                selectedIDs.insert(manager.currentEntities[i].id)
            }
        } else {
            if selectedIDs.contains(entity.id) && selectedIDs.count == 1 {
                selectedIDs.remove(entity.id)
            } else {
                selectedIDs.removeAll()
                selectedIDs.insert(entity.id)
            }
        }
        lastSelectedID = entity.id
    }
    
    private func handleDoubleClick(on entity: FolderSlotEntity) {
        if entity.isDirectory {
            selectedIDs.removeAll()
            lastSelectedID = nil
            manager.navigate(to: entity.url)
        } else {
            NSWorkspace.shared.open(entity.url)
        }
    }
}

// MARK: - Interactive Tile Items

struct FolderSlotItemView: View {
    let entity: FolderSlotEntity
    let isSelected: Bool
    let onSingleClick: (Bool) -> Void
    let onDoubleClick: () -> Void
    
    @State private var loadedImage: NSImage? = nil
    @State private var isLoading = false
    @State private var imageRequestID: UUID?
    @State private var imageLoadTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 4) {
            thumbnailView
            
            Text(entity.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(4)
        .frame(width: 100, height: 100)
        .overlay {
            FolderSlotDragSurface(
                url: entity.url,
                onSingleClick: onSingleClick,
                onDoubleClick: onDoubleClick
            )
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(entity.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entity.url]) }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([entity.url as NSURL])
            }
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            cancelImageLoad()
            loadedImage = nil // Instantly free RAM when scrolled out of view
        }
        .onChange(of: entity.id) { _, _ in
            reloadImage()
        }
    }
    
    private var thumbnailView: some View {
        ZStack {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 48))
                    .foregroundColor(entity.isDirectory ? .blue : .white.opacity(0.8))
                    .frame(width: 60, height: 60)
        }
        }
        .padding(6)
        .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
        .cornerRadius(12)
    }
    
    private func cancelImageLoad() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        if let id = imageRequestID {
            BoxIconCache.shared.cancelRequest(id)
            imageRequestID = nil
        }
    }
    
    private func reloadImage() {
        cancelImageLoad()
        loadedImage = nil
        isLoading = false
        loadImage()
    }
    
    private var placeholderSymbol: String {
        if entity.isDirectory { return "folder.fill" }
        let ext = entity.url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif", "svg", "icns":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return "archivebox.fill"
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            return "waveform"
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "ts", "m2ts":
            return "film.fill"
        case "swift", "js", "ts", "py", "java", "c", "cpp", "h", "json", "html", "css", "md", "txt", "xml", "yml", "yaml", "sh", "rb", "php":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }
    
    private func loadImage() {
        let targetSize: CGFloat = 120
        if let cached = BoxIconCache.shared.cachedPreview(for: entity.url, targetSize: targetSize) {
            self.loadedImage = cached
            self.isLoading = false
            return
        }
        guard BoxIconCache.shared.shouldAttemptPreview(for: entity.url) else {
            self.isLoading = false
            return
        }
        
        imageLoadTask?.cancel()
        imageLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self.isLoading = true
            self.imageRequestID = BoxIconCache.shared.requestDisplayImage(for: entity.url, targetSize: targetSize) { image in
                if !Task.isCancelled {
                    self.loadedImage = image
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Native Window Controls

struct WindowControlSurface: NSViewRepresentable {
    let onClick: () -> Void
    
    func makeNSView(context: Context) -> ControlView {
        let view = ControlView()
        view.onClick = onClick
        return view
    }
    
    func updateNSView(_ nsView: ControlView, context: Context) {
        nsView.onClick = onClick
    }
    
    final class ControlView: NSView {
        var onClick: (() -> Void)?
        
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        
        override func mouseDown(with event: NSEvent) {
            // Intentionally empty to consume the click and prevent the window background from stealing it for a drag session
        }
        
        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if bounds.contains(point) { onClick?() }
        }
    }
}

// MARK: - Native Drag Surface

struct FolderSlotDragSurface: NSViewRepresentable {
    let url: URL
    let onSingleClick: (Bool) -> Void
    let onDoubleClick: () -> Void
    
    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.url = url
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }
    
    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.url = url
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
    
    final class DragView: NSView, NSDraggingSource {
        var url: URL?
        var onSingleClick: ((Bool) -> Void)?
        var onDoubleClick: (() -> Void)?
        private var mouseDownPoint: NSPoint = .zero
        private var isDragging = false
        
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }
        
        override var mouseDownCanMoveWindow: Bool {
            return false
        }
        
        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            isDragging = false
        }
        
        override func mouseDragged(with event: NSEvent) {
            guard let url = url, !isDragging else { return }
            let currentPoint = convert(event.locationInWindow, from: nil)
            if hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y) > 3 {
                isDragging = true
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)
                item.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: icon)
                beginDraggingSession(with: [item], event: event, source: self)
            }
        }
        
        override func mouseUp(with event: NSEvent) {
            guard !isDragging else { return }
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                let isShiftPressed = event.modifierFlags.contains(.shift)
                onSingleClick?(isShiftPressed)
            }
        }
        
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            return .copy
        }
    }
}