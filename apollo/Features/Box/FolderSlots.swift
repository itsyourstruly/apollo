import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine
import Quartz

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
    
    static func search(urls: [URL], query: String) async -> [FolderSlotEntity] {
        return await Task.detached(priority: .userInitiated) {
            var results: [FolderSlotEntity] = []
            let fm = FileManager.default
            let lowerQuery = query.lowercased()

            for url in urls {
                if Task.isCancelled { break }
                
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                
                for case let fileURL as URL in enumerator {
                    if Task.isCancelled { break }
                    let name = fileURL.lastPathComponent
                    if name.lowercased().contains(lowerQuery) {
                        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        results.append(FolderSlotEntity(url: fileURL, isDirectory: isDir, name: name))
                    }
                    if results.count >= 250 { break }
                }
                if results.count >= 250 { break }
            }
            return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar
            FolderSlotsManager.shared.toggleQuickLook()
        } else {
            super.keyDown(with: event)
        }
    }
    
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
    @Published var selectedIDs = Set<String>()
    @Published var lastSelectedID: String?
    @Published var searchQuery: String = ""
    @Published var searchResults: [FolderSlotEntity] = []
    @Published var isSearching: Bool = false
    private var searchTask: Task<Void, Never>?
    private var activeRootURLs: [URL] = []
    private weak var activeModel: NotchMenuModel?
    private var currentNavigationTask: Task<Void, Never>?
    
    var displayedEntities: [FolderSlotEntity] {
        return searchQuery.isEmpty ? currentEntities : searchResults
    }
    
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
        if let window = notification.object as? NSWindow {
            if window === self.panel {
                self.close(updateModel: true)
            } else if QLPreviewPanel.sharedPreviewPanelExists(), window === QLPreviewPanel.shared() {
                QLPreviewPanel.shared().dataSource = nil
                QLPreviewPanel.shared().delegate = nil
            }
        }
    }
    
    func toggleQuickLook() {
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            let selectedURLs = currentEntities.filter { selectedIDs.contains($0.id) }.map(\.url)
            guard !selectedURLs.isEmpty else { return }
            
            let panel = QLPreviewPanel.shared()
            panel?.dataSource = self
            panel?.delegate = self
            panel?.reloadData()
            panel?.makeKeyAndOrderFront(nil)
        }
    }
    
    func close(updateModel: Bool = true) {
        if let currentSize = panel?.frame.size {
            UserDefaults.standard.set(Double(currentSize.width), forKey: "folderSlotsWindowWidth")
            UserDefaults.standard.set(Double(currentSize.height), forKey: "folderSlotsWindowHeight")
        }
        
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().dataSource === self {
            QLPreviewPanel.shared().orderOut(nil)
            QLPreviewPanel.shared().dataSource = nil
            QLPreviewPanel.shared().delegate = nil
        }
        
        panel?.delegate = nil
        panel?.close()
        panel = nil
        baseEntities.removeAll()
        currentEntities.removeAll()
        navigationStack.removeAll()
        isNavigating = false
        selectedIDs.removeAll()
        lastSelectedID = nil
        searchQuery = ""
        searchResults.removeAll()
        isSearching = false
        searchTask?.cancel()
        searchTask = nil
        currentNavigationTask?.cancel()
        currentNavigationTask = nil
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
        if navigationStack.isEmpty {
            var hierarchy: [URL] = []
            let components = url.pathComponents
            var current = URL(fileURLWithPath: "/")
            
            if components.first == "/" {
                hierarchy.append(current)
                for component in components.dropFirst() {
                    current = current.appendingPathComponent(component)
                    hierarchy.append(current)
                }
            } else {
                hierarchy.append(url)
            }
            navigationStack = hierarchy
        } else {
            if navigationStack.last != url {
                navigationStack.append(url)
            }
        }
        loadContents(of: url)
    }
    
    func navigateBack() {
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        
        if let lastURL = navigationStack.last {
            // Re-fetch the parent directory
            loadContents(of: lastURL)
        } else {
            currentNavigationTask?.cancel()
            self.currentEntities = self.baseEntities
            self.isNavigating = false
        }
    }
    
    func navigateToRoot() {
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeAll()
        selectedIDs.removeAll()
        lastSelectedID = nil
        searchQuery = ""
        searchResults.removeAll()
        isSearching = false
        searchTask?.cancel()
        searchTask = nil
        currentNavigationTask?.cancel()
        self.currentEntities = self.baseEntities
        self.isNavigating = false
    }
    
    func navigateToStackIndex(_ index: Int) {
        guard index >= 0 && index < navigationStack.count - 1 else { return }
        let targetURL = navigationStack[index]
        navigationStack = Array(navigationStack.prefix(index + 1))
        selectedIDs.removeAll()
        lastSelectedID = nil
        loadContents(of: targetURL)
    }
    
    private func loadContents(of url: URL) {
        isNavigating = true
        searchQuery = ""
        searchResults.removeAll()
        isSearching = false
        searchTask?.cancel()
        searchTask = nil
        currentNavigationTask?.cancel()
        currentNavigationTask = Task {
            let fetched = await FolderSlotsWorker.fetchContents(of: url, withSecurityScope: false)
            if !Task.isCancelled {
                await MainActor.run {
                    self.currentEntities = fetched
                    self.isNavigating = false
                }
            }
        }
    }
    
    func performSearch(query: String) {
        searchTask?.cancel()
        if query.isEmpty {
            isSearching = false
            searchResults = []
            return
        }
        
        let targetURLs = navigationStack.isEmpty ? activeRootURLs : [navigationStack.last!]
        
        isSearching = true
        searchTask = Task {
            // Debounce briefly for smooth typing without firing on every single keystroke
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            
            let results = await FolderSlotsWorker.search(urls: targetURLs, query: query)
            if !Task.isCancelled {
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            }
        }
    }
    
    func addRootFolder(url: URL) {
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "folder_bookmark_\(url.path)")
        }
        
        let settings = AppSettings.shared
        if !settings.folderSlotsPaths.contains(url.path) {
            settings.folderSlotsPaths.append(url.path)
        }
        
        let newEntity = FolderSlotEntity(url: url, isDirectory: true, name: url.lastPathComponent)
        if !baseEntities.contains(where: { $0.url == url }) {
            baseEntities.append(newEntity)
            baseEntities.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        
        if navigationStack.isEmpty {
            if !currentEntities.contains(where: { $0.url == url }) {
                currentEntities.append(newEntity)
                currentEntities.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
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
            originX = islandFrame.minX - width - 48
            originY = screenRect.maxY - height - 40
        } else if settings.folderSlotsDirection == 1 { // Right
            originX = islandFrame.maxX + 48
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

// MARK: - Quick Look Panel Source & Delegate

extension FolderSlotsManager: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return displayedEntities.filter { selectedIDs.contains($0.id) }.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let selectedURLs = displayedEntities.filter { selectedIDs.contains($0.id) }.map(\.url)
        guard index >= 0 && index < selectedURLs.count else { return nil }
        return selectedURLs[index] as NSURL
    }
}

// MARK: - Grid View

struct FolderSlotsRootView: View {
    @ObservedObject var manager: FolderSlotsManager
    let columns: Int
    let accentColor: Color
    
    @State private var isDropTargeted = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.15), in: Circle())
                    .overlay { WindowControlSurface { manager.close() } }
                
                if !manager.navigationStack.isEmpty {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.15), in: Circle())
                        .overlay {
                            WindowControlSurface {
                                manager.navigateBack()
                            manager.selectedIDs.removeAll()
                            manager.lastSelectedID = nil
                            }
                        }
                }
                
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Button {
                                manager.navigateToRoot()
                            } label: {
                                Text("Folder Slots")
                                    .foregroundColor(manager.navigationStack.isEmpty ? accentColor : .white.opacity(0.8))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .buttonStyle(.plain)
                            .id(-1)
                            
                            ForEach(Array(manager.navigationStack.enumerated()), id: \.offset) { index, url in
                                Text("/")
                                    .foregroundColor(.white.opacity(0.4))
                                
                                Button {
                                    manager.navigateToStackIndex(index)
                                } label: {
                                    Text(url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
                                        .foregroundColor(index == manager.navigationStack.count - 1 ? accentColor : .white.opacity(0.8))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: 160)
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: manager.navigationStack.count) { _, count in
                        withAnimation {
                            scrollProxy.scrollTo(count - 1, anchor: .trailing)
                        }
                    }
                }
                
                Spacer()
                
                NativeSearchBar(text: $manager.searchQuery)
                    .frame(width: 180)
                    .onChange(of: manager.searchQuery) { _, newValue in
                        manager.performSearch(query: newValue)
                    }
            }
            .frame(height: 28)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            if manager.isNavigating {
                ProgressView().controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.isSearching && manager.searchResults.isEmpty {
                ProgressView().controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.displayedEntities.isEmpty {
                Text(manager.searchQuery.isEmpty ? (manager.navigationStack.isEmpty ? "No folders configured.\nAdd them in Settings." : "Folder is empty.") : "No results found.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                        ForEach(manager.displayedEntities) { entity in
                            FolderSlotItemView(
                                entity: entity,
                            isSelected: manager.selectedIDs.contains(entity.id),
                                onSingleClick: { isShiftPressed in
                                    handleSingleClick(on: entity, isShiftPressed: isShiftPressed)
                                },
                                onDoubleClick: {
                                    handleDoubleClick(on: entity)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .overlay(
            Group {
                if isDropTargeted && manager.navigationStack.isEmpty {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        )
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard manager.navigationStack.isEmpty else { return false }
            var handled = false
            for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let fileURL = url else { return }
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                        DispatchQueue.main.async {
                            manager.addRootFolder(url: fileURL)
                        }
                    }
                }
            }
            return handled
        }
    }
    
    private func handleSingleClick(on entity: FolderSlotEntity, isShiftPressed: Bool) {
        if isShiftPressed, let lastID = manager.lastSelectedID,
           let startIndex = manager.displayedEntities.firstIndex(where: { $0.id == lastID }),
           let endIndex = manager.displayedEntities.firstIndex(where: { $0.id == entity.id }) {
            let lower = min(startIndex, endIndex)
            let upper = max(startIndex, endIndex)
            for i in lower...upper {
                manager.selectedIDs.insert(manager.displayedEntities[i].id)
            }
        } else {
            if manager.selectedIDs.contains(entity.id) && manager.selectedIDs.count == 1 {
                manager.selectedIDs.remove(entity.id)
            } else {
                manager.selectedIDs.removeAll()
                manager.selectedIDs.insert(entity.id)
            }
        }
        manager.lastSelectedID = entity.id
        
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }
    
    private func handleDoubleClick(on entity: FolderSlotEntity) {
        if entity.isDirectory {
            manager.selectedIDs.removeAll()
            manager.lastSelectedID = nil
            manager.navigate(to: entity.url)
        } else {
            NSWorkspace.shared.open(entity.url)
        }
    }
}

// MARK: - Native Search Bar

struct NativeSearchBar: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.controlSize = .regular
        searchField.bezelStyle = .roundedBezel
        searchField.delegate = context.coordinator
        return searchField
    }
    
    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                text.wrappedValue = field.stringValue
            }
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