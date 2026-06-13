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
    let fileSize: Int64
    let dateModified: Date
    
    var placeholderSymbol: String {
        if isDirectory { return "folder.fill" }
        let ext = url.pathExtension.lowercased()
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
        case "swift", "js", "py", "java", "c", "cpp", "h", "json", "html", "css", "md", "txt", "xml", "yml", "yaml", "sh", "rb", "php":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }
}

enum FolderSlotDisplayItem: Identifiable, Hashable {
    case entity(FolderSlotEntity)
    case stackHeader(ext: String, count: Int, isExpanded: Bool, topEntities: [FolderSlotEntity])
    
    var id: String {
        switch self {
        case .entity(let e): return e.id
        case .stackHeader(let ext, _, _, _): return "stack_header_\(ext)"
        }
    }
}

struct FolderSlotGroup: Identifiable {
    let id: String
    let title: String
    let items: [FolderSlotDisplayItem]
}

final class FolderSlotsWorker: Sendable {
    static func fetchContents(of url: URL, withSecurityScope securityScope: Bool, sortOption: Int, foldersFirst: Bool) async -> [FolderSlotEntity] {
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
                let urls = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
                for u in urls {
                    let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    entities.append(FolderSlotEntity(url: u, isDirectory: isDir, name: u.lastPathComponent, fileSize: Int64(size), dateModified: date))
                }
            } catch {
                NSLog("FolderSlotsWorker Error: \(error.localizedDescription)")
            }
            return sortEntities(entities, option: sortOption, foldersFirst: foldersFirst)
        }.value
    }
    
    static func deepSearch(urls: [URL], query: String, onUpdate: @escaping @Sendable ([FolderSlotEntity]) -> Void) async {
        let task = Task.detached(priority: .userInitiated) {
            var exactMatches: [FolderSlotEntity] = []
            var fuzzyMatches: [FolderSlotEntity] = []
            var seenURLs = Set<URL>()
            let checkDuplicates = urls.count > 1
            let lowerQuery = query.lowercased()
            
            let isExtOnlySearch = lowerQuery.hasPrefix(".") && lowerQuery.count > 1
            let extOnly = isExtOnlySearch ? String(lowerQuery.dropFirst()) : ""
            let extOnlyChars = Array(extOnly)
            
            let parts = lowerQuery.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            let isNameAndExtSearch = !isExtOnlySearch && parts.count >= 2 && !parts.last!.isEmpty
            let searchExt = isNameAndExtSearch ? parts.last! : ""
            let searchName = isNameAndExtSearch ? parts.dropLast().joined(separator: ".") : ""
            let searchNameChars = Array(searchName)
            
            let queryChars = Array(lowerQuery)
            let fm = FileManager.default
            
            var lastYieldTime = ProcessInfo.processInfo.systemUptime
            var yieldCount = 0
            var scannedCount = 0

            for url in urls {
                if Task.isCancelled { break }
                
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                
                while let fileURL = enumerator.nextObject() as? URL {
                    if Task.isCancelled { break }
                    
                    scannedCount += 1
                    if scannedCount % 1000 == 0 {
                        await Task.yield()
                    }
                    
                    let name = fileURL.lastPathComponent
                    
                    // Skip massive unneeded folders to keep search instant
                    if name == "node_modules" || name == "Library" || name == "DerivedData" || name == "Pods" || name == ".git" || name == ".build" || name == ".Trash" || name == "build" || name == ".swiftpm" || name == "Carthage" {
                        enumerator.skipDescendants()
                        continue
                    }
                    
                    if checkDuplicates {
                        if !seenURLs.insert(fileURL).inserted { continue }
                    }
                    
                    let lowerName = name.lowercased()
                    let fileExt = fileURL.pathExtension.lowercased()
                    
                    var isExact = false
                    var isFuzzy = false
                    
                    if isExtOnlySearch {
                        if fileExt == extOnly {
                            isExact = true
                        } else if fileExt.contains(extOnly) || isFuzzyMatch(queryChars: extOnlyChars, target: fileExt) {
                            isFuzzy = true
                        }
                    } else if isNameAndExtSearch {
                        if fileExt == searchExt || fileExt.contains(searchExt) {
                            let baseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                            if baseName.contains(searchName) {
                                isExact = true
                            } else if isFuzzyMatch(queryChars: searchNameChars, target: baseName) {
                                isFuzzy = true
                            }
                        }
                    } else {
                        if lowerName.contains(lowerQuery) {
                            isExact = true
                        } else if isFuzzyMatch(queryChars: queryChars, target: lowerName) {
                            isFuzzy = true
                        }
                    }
                    
                    if isExact || isFuzzy {
                        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                        let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                        
                        let entity = FolderSlotEntity(url: fileURL, isDirectory: isDir, name: name, fileSize: Int64(size), dateModified: date)
                        if isExact {
                            exactMatches.append(entity)
                        } else {
                            fuzzyMatches.append(entity)
                        }
                        
                        let now = ProcessInfo.processInfo.systemUptime
                        if (now - lastYieldTime > 0.25) || (yieldCount == 0 && (exactMatches.count + fuzzyMatches.count) >= 15) {
                            if !Task.isCancelled {
                                let partial = sortSearchEntities(exact: exactMatches, fuzzy: fuzzyMatches, query: query)
                                onUpdate(partial)
                            }
                            lastYieldTime = now
                            yieldCount += 1
                        }
                    }
                    
                    if exactMatches.count + fuzzyMatches.count >= 200 { break }
                }
                if exactMatches.count + fuzzyMatches.count >= 200 { break }
            }
            
            if !Task.isCancelled {
                let final = sortSearchEntities(exact: exactMatches, fuzzy: fuzzyMatches, query: query)
                onUpdate(final)
            }
        }
        
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
    
    nonisolated static func sortEntities(_ entities: [FolderSlotEntity], option: Int, foldersFirst: Bool) -> [FolderSlotEntity] {
        return entities.sorted {
            if foldersFirst && $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            switch option {
            case 1: // Type
                let ext0 = $0.url.pathExtension.lowercased()
                let ext1 = $1.url.pathExtension.lowercased()
                if ext0 != ext1 { return ext0 < ext1 }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            case 2: // Size
                if $0.fileSize != $1.fileSize { return $0.fileSize > $1.fileSize }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            case 3: // Date
                if $0.dateModified != $1.dateModified { return $0.dateModified > $1.dateModified }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            default: // Name
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
    
    nonisolated static func sortSearchEntities(exact: [FolderSlotEntity], fuzzy: [FolderSlotEntity], query: String) -> [FolderSlotEntity] {
        let lowerQuery = query.lowercased()
        
        func rankAndCount(for entity: FolderSlotEntity, isExact: Bool) -> (Int, Int) {
            let name = entity.name.lowercased()
            let base = entity.url.deletingPathExtension().lastPathComponent.lowercased()
            
            let rank: Int
            if name == lowerQuery || base == lowerQuery { rank = 0 }
            else if name.hasPrefix(lowerQuery) || base.hasPrefix(lowerQuery) { rank = 1 }
            else { rank = isExact ? 2 : 3 }
            
            return (rank, entity.name.count)
        }
        
        let exactMapped = exact.map { ($0, rankAndCount(for: $0, isExact: true)) }
        let fuzzyMapped = fuzzy.map { ($0, rankAndCount(for: $0, isExact: false)) }
        
        var combined = exactMapped + fuzzyMapped
        
        combined.sort { lhs, rhs in
            let rank0 = lhs.1.0
            let rank1 = rhs.1.0
            if rank0 != rank1 { return rank0 < rank1 }
            
            let count0 = lhs.1.1
            let count1 = rhs.1.1
            if count0 != count1 { return count0 < count1 }
            
            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }
        
        return combined.map { $0.0 }
    }
    
    nonisolated private static func isFuzzyMatch(queryChars: [Character], target: String) -> Bool {
        var queryIndex = 0
        let queryCount = queryChars.count
        
        for char in target {
            if char == queryChars[queryIndex] {
                queryIndex += 1
                if queryIndex == queryCount {
                    return true
                }
            }
        }
        return false
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
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v" {
            let pboard = NSPasteboard.general
            if pboard.types?.contains(.fileURL) == true || pboard.types?.contains(.fileContents) == true {
                if FolderSlotsManager.shared.handlePaste() {
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
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
    private var currentSearchID: UUID?
    private var lastSearchQuery: String = ""
    @Published var searchResults: [FolderSlotEntity] = []
    @Published var isSearching: Bool = false
    @Published var showCurrentEntitiesDespiteSearch: Bool = false
    private var searchTask: Task<Void, Never>?
    private var activeRootURLs: [URL] = []
    @Published var expandedStacks = Set<String>()
    private weak var activeModel: NotchMenuModel?
    private var currentNavigationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        AppSettings.shared.$folderSlotsSortOption
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] newOption in
                guard let self = self else { return }
                let foldersFirst = AppSettings.shared.folderSlotsSortFoldersFirst
                self.currentEntities = FolderSlotsWorker.sortEntities(self.currentEntities, option: newOption, foldersFirst: foldersFirst)
                self.searchResults = FolderSlotsWorker.sortEntities(self.searchResults, option: newOption, foldersFirst: foldersFirst)
            }
            .store(in: &cancellables)
            
        AppSettings.shared.$folderSlotsSortFoldersFirst
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] newFoldersFirst in
                guard let self = self else { return }
                let option = AppSettings.shared.folderSlotsSortOption
                self.currentEntities = FolderSlotsWorker.sortEntities(self.currentEntities, option: option, foldersFirst: newFoldersFirst)
                self.searchResults = FolderSlotsWorker.sortEntities(self.searchResults, option: option, foldersFirst: newFoldersFirst)
            }
            .store(in: &cancellables)
    }
    
    var displayedEntities: [FolderSlotEntity] {
        if searchQuery.isEmpty { return currentEntities }
        if showCurrentEntitiesDespiteSearch { return currentEntities }
        return searchResults
    }
    
    var groupedItems: [FolderSlotGroup] {
        let source = displayedEntities
        
        if !searchQuery.isEmpty && !showCurrentEntitiesDespiteSearch {
            let items = source.map { FolderSlotDisplayItem.entity($0) }
            return [FolderSlotGroup(id: "Search Results", title: "", items: items)]
        }
        
        let settings = AppSettings.shared
        let groupByType = settings.folderSlotsGroupByType
        let enableStacks = settings.folderSlotsEnableStacks
        let threshold = settings.folderSlotsStackThreshold
        let stackFolders = settings.folderSlotsStackFolders
        
        let dirs = source.filter { $0.isDirectory }
        let files = source.filter { !$0.isDirectory }
        let dict = Dictionary(grouping: files, by: { $0.url.pathExtension.lowercased() })
        
        let numGroups = (dirs.isEmpty ? 0 : 1) + dict.keys.count
        let effectivelyEnableStacks = enableStacks && numGroups > 1
        
        if groupByType {
            var groups: [FolderSlotGroup] = []
            if !dirs.isEmpty {
                var items: [FolderSlotDisplayItem] = []
                if effectivelyEnableStacks && stackFolders && dirs.count >= threshold {
                    let isExpanded = expandedStacks.contains("folder")
                    let top3 = Array(dirs.prefix(3))
                    items.append(.stackHeader(ext: "folder", count: dirs.count, isExpanded: isExpanded, topEntities: top3))
                    if isExpanded {
                        items.append(contentsOf: dirs.map { .entity($0) })
                    }
                } else {
                    items.append(contentsOf: dirs.map { .entity($0) })
                }
                groups.append(FolderSlotGroup(id: "Folders", title: "Folders", items: items))
            }
            
            let sortedKeys = dict.keys.sorted()
            
            for key in sortedKeys {
                guard let groupFiles = dict[key] else { continue }
                var items: [FolderSlotDisplayItem] = []
                if effectivelyEnableStacks && groupFiles.count >= threshold {
                    let isExpanded = expandedStacks.contains(key)
                    let top3 = Array(groupFiles.prefix(3))
                    items.append(.stackHeader(ext: key, count: groupFiles.count, isExpanded: isExpanded, topEntities: top3))
                    if isExpanded {
                        items.append(contentsOf: groupFiles.map { .entity($0) })
                    }
                } else {
                    items.append(contentsOf: groupFiles.map { .entity($0) })
                }
                let title = key.isEmpty ? "Files" : key.uppercased()
                groups.append(FolderSlotGroup(id: key, title: title, items: items))
            }
            return groups
        } else {
            var items: [FolderSlotDisplayItem] = []
            
            if effectivelyEnableStacks && stackFolders && dirs.count >= threshold {
                let isExpanded = expandedStacks.contains("folder")
                let top3 = Array(dirs.prefix(3))
                items.append(.stackHeader(ext: "folder", count: dirs.count, isExpanded: isExpanded, topEntities: top3))
                if isExpanded {
                    items.append(contentsOf: dirs.map { .entity($0) })
                }
            } else {
                items.append(contentsOf: dirs.map { .entity($0) })
            }
            
            if effectivelyEnableStacks {
                var seenExts = Set<String>()
                var orderedExts = [String]()
                for f in files {
                    let ext = f.url.pathExtension.lowercased()
                    if !seenExts.contains(ext) {
                        seenExts.insert(ext)
                        orderedExts.append(ext)
                    }
                }
                
                let dict = Dictionary(grouping: files, by: { $0.url.pathExtension.lowercased() })
                for ext in orderedExts {
                    let groupFiles = dict[ext]!
                    if groupFiles.count >= threshold {
                        let isExpanded = expandedStacks.contains(ext)
                        let top3 = Array(groupFiles.prefix(3))
                        items.append(.stackHeader(ext: ext, count: groupFiles.count, isExpanded: isExpanded, topEntities: top3))
                        if isExpanded {
                            items.append(contentsOf: groupFiles.map { .entity($0) })
                        }
                    } else {
                        items.append(contentsOf: groupFiles.map { .entity($0) })
                    }
                }
            } else {
                items.append(contentsOf: files.map { .entity($0) })
            }
            
            return [FolderSlotGroup(id: "All", title: "", items: items)]
        }
    }
    
    var flatSmartItems: [FolderSlotDisplayItem] {
        groupedItems.flatMap { $0.items }
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
                entities.append(FolderSlotEntity(url: targetURL, isDirectory: isDir.boolValue, name: targetURL.lastPathComponent, fileSize: 0, dateModified: .distantPast))
            } else if isSecured {
                entities.append(FolderSlotEntity(url: targetURL, isDirectory: true, name: targetURL.lastPathComponent, fileSize: 0, dateModified: .distantPast))
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
    
    func resignSearchFocus() {
        panel?.makeFirstResponder(nil)
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
        expandedStacks.removeAll()
        searchQuery = ""
        currentSearchID = nil
        lastSearchQuery = ""
        searchResults.removeAll()
        isSearching = false
        showCurrentEntitiesDespiteSearch = false
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
    
    func navigate(to url: URL, keepSearchFocus: Bool = false, keepSearchQuery: Bool = false) {
        if !keepSearchFocus {
            resignSearchFocus()
        }
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
        loadContents(of: url, keepSearchQuery: keepSearchQuery)
    }
    
    func navigateBack(keepSearchFocus: Bool = false, keepSearchQuery: Bool = false) {
        if !keepSearchFocus {
            resignSearchFocus()
        }
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        
        if let lastURL = navigationStack.last {
            // Re-fetch the parent directory
            loadContents(of: lastURL, keepSearchQuery: keepSearchQuery)
        } else {
            currentNavigationTask?.cancel()
            self.currentEntities = self.baseEntities
            self.isNavigating = false
            if !keepSearchQuery {
                self.searchQuery = ""
                self.currentSearchID = nil
                self.lastSearchQuery = ""
                self.searchResults.removeAll()
                self.showCurrentEntitiesDespiteSearch = false
            } else {
                if !self.searchQuery.isEmpty && !self.searchQuery.hasSuffix("/") {
                    self.performSearch(query: self.searchQuery)
                }
            }
        }
    }
    
    func navigateToRoot() {
        resignSearchFocus()
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeAll()
        selectedIDs.removeAll()
        lastSelectedID = nil
        expandedStacks.removeAll()
        searchQuery = ""
        currentSearchID = nil
        lastSearchQuery = ""
        searchResults.removeAll()
        isSearching = false
        showCurrentEntitiesDespiteSearch = false
        searchTask?.cancel()
        searchTask = nil
        currentNavigationTask?.cancel()
        self.currentEntities = self.baseEntities
        self.isNavigating = false
    }
    
    func navigateToStackIndex(_ index: Int) {
        resignSearchFocus()
        guard index >= 0 && index < navigationStack.count - 1 else { return }
        let targetURL = navigationStack[index]
        navigationStack = Array(navigationStack.prefix(index + 1))
        selectedIDs.removeAll()
        lastSelectedID = nil
        expandedStacks.removeAll()
        loadContents(of: targetURL)
    }
    
    private func loadContents(of url: URL, keepSearchQuery: Bool = false) {
        isNavigating = true
        if !keepSearchQuery {
            searchQuery = ""
            lastSearchQuery = ""
            currentSearchID = nil
            showCurrentEntitiesDespiteSearch = false
        }
        searchResults.removeAll()
        expandedStacks.removeAll()
        isSearching = false
        searchTask?.cancel()
        searchTask = nil
        currentNavigationTask?.cancel()
        let option = AppSettings.shared.folderSlotsSortOption
        let foldersFirst = AppSettings.shared.folderSlotsSortFoldersFirst
        currentNavigationTask = Task {
            let fetched = await FolderSlotsWorker.fetchContents(of: url, withSecurityScope: false, sortOption: option, foldersFirst: foldersFirst)
            if !Task.isCancelled {
                await MainActor.run {
                    self.currentEntities = fetched
                    self.isNavigating = false
                    
                    if keepSearchQuery && !self.searchQuery.isEmpty && !self.searchQuery.hasSuffix("/") {
                        self.performSearch(query: self.searchQuery)
                    }
                }
            }
        }
    }
    
    func performSearch(query: String) {
        let isAddingSlash = query.hasSuffix("/") && !lastSearchQuery.hasSuffix("/") && query.count > lastSearchQuery.count
        let isDeletingSlash = lastSearchQuery.hasSuffix("/") && !query.hasSuffix("/") && query.count < lastSearchQuery.count
        
        if isDeletingSlash {
            let deletedFolderName = lastSearchQuery.dropLast().components(separatedBy: "/").last ?? ""
            if let currentURL = navigationStack.last, currentURL.lastPathComponent.lowercased() == deletedFolderName.lowercased() {
                lastSearchQuery = query
                searchTask?.cancel()
                navigateBack(keepSearchFocus: true, keepSearchQuery: true)
                return
            }
        }
        
        lastSearchQuery = query
        
        searchTask?.cancel()
        showCurrentEntitiesDespiteSearch = false
        
        if isAddingSlash {
            let parts = query.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.count >= 2 {
                let folderName = parts[parts.count - 2]
                
                var bestMatch: FolderSlotEntity? = nil
                
                if let topResult = searchResults.first(where: { $0.isDirectory && $0.name.lowercased().hasPrefix(folderName.lowercased()) }) {
                    bestMatch = topResult
                } else if let topResult = searchResults.first(where: { $0.isDirectory }) {
                    bestMatch = topResult
                }
                
                if bestMatch == nil {
                    bestMatch = currentEntities.first(where: { $0.isDirectory && $0.name.lowercased() == folderName.lowercased() })
                        ?? currentEntities.first(where: { $0.isDirectory && $0.name.lowercased().hasPrefix(folderName.lowercased()) })
                        ?? currentEntities.first(where: { $0.isDirectory && $0.name.lowercased().contains(folderName.lowercased()) })
                }
                
                if let match = bestMatch {
                    showCurrentEntitiesDespiteSearch = true
                    navigate(to: match.url, keepSearchFocus: true, keepSearchQuery: true)
                    return
                }
            }
        }
        
        let effectiveQuery = query.components(separatedBy: "/").last ?? query
        
        if effectiveQuery.isEmpty {
            isSearching = false
            searchResults = []
            currentSearchID = nil
            expandedStacks.removeAll()
            if query.hasSuffix("/") {
                showCurrentEntitiesDespiteSearch = true
            }
            return
        }
        
        isSearching = true
        let targetURLs = navigationStack.isEmpty ? activeRootURLs : [navigationStack.last!]
        
        let searchID = UUID()
        currentSearchID = searchID
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, currentSearchID == searchID else { return }
            
            await FolderSlotsWorker.deepSearch(urls: targetURLs, query: effectiveQuery) { [weak self] partialResults in
                DispatchQueue.main.async {
                    guard let self = self, self.currentSearchID == searchID else { return }
                    self.searchResults = partialResults
                }
            }
            
            if !Task.isCancelled {
                await MainActor.run {
                    guard self.currentSearchID == searchID else { return }
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
        
        let newEntity = FolderSlotEntity(url: url, isDirectory: true, name: url.lastPathComponent, fileSize: 0, dateModified: .distantPast)
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
    
    func handlePaste() -> Bool {
        guard !navigationStack.isEmpty, let targetURL = navigationStack.last else { return false }
        let pboard = NSPasteboard.general
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else { return false }
        
        let fm = FileManager.default
        var pasted = false
        for url in urls {
            let destURL = uniqueURL(for: url, in: targetURL)
            do {
                try fm.copyItem(at: url, to: destURL)
                pasted = true
            } catch {
                NSLog("Paste error: \(error.localizedDescription)")
            }
        }
        
        if pasted {
            refreshCurrentDirectory()
        }
        return pasted
    }
    
    func refreshCurrentDirectory() {
        if let targetURL = navigationStack.last {
            loadContents(of: targetURL)
        }
    }
    
    nonisolated func uniqueURL(for url: URL, in directory: URL) -> URL {
        var destURL = directory.appendingPathComponent(url.lastPathComponent)
        var counter = 1
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        while FileManager.default.fileExists(atPath: destURL.path) {
            let newName = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            destURL = directory.appendingPathComponent(newName)
            counter += 1
        }
        return destURL
    }
}

// MARK: - Quick Look Panel Source & Delegate

@MainActor extension FolderSlotsManager: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
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

final class BreadcrumbScrollManager: ObservableObject {
    private var monitor: Any?
    
    @Published var isHovering = false {
        didSet {
            if isHovering {
                if monitor == nil {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                        if event.scrollingDeltaY != 0 && event.scrollingDeltaX == 0 {
                            if let cgEvent = event.cgEvent?.copy() {
                                let deltaY = cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                                let pointDeltaY = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                                let fixedPtDeltaY = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                                
                                cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
                                cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: deltaY)
                                
                                cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
                                cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaY)
                                
                                cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
                                cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedPtDeltaY)
                                
                                if let newEvent = NSEvent(cgEvent: cgEvent) {
                                    return newEvent
                                }
                            }
                        }
                        return event
                    }
                }
            } else {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
        }
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

struct FolderSlotsRootView: View {
    @ObservedObject var manager: FolderSlotsManager
    let columns: Int
    let accentColor: Color
    
    @State private var isDropTargeted = false
    @StateObject private var breadcrumbScrollManager = BreadcrumbScrollManager()
    
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
                    .onHover { hovering in
                        breadcrumbScrollManager.isHovering = hovering
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
                    .contentShape(Rectangle())
                    .onTapGesture { manager.resignSearchFocus() }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns), spacing: 8) {
                        ForEach(manager.groupedItems) { group in
                            Section(header: groupHeader(title: group.title)) {
                                ForEach(group.items) { item in
                                    switch item {
                                    case .entity(let entity):
                                        FolderSlotItemView(
                                            entity: entity,
                                            isSelected: manager.selectedIDs.contains(entity.id),
                                            onSingleClick: { isShiftPressed in
                                                handleSingleClick(on: entity, isShiftPressed: isShiftPressed)
                                            },
                                            onDoubleClick: { handleDoubleClick(on: entity) }
                                        )
                                    case .stackHeader(let ext, let count, let isExpanded, let topEntities):
                                        FolderSlotStackHeaderView(
                                            ext: ext,
                                            count: count,
                                            isExpanded: isExpanded,
                                            topEntities: topEntities,
                                            onToggle: {
                                            manager.resignSearchFocus()
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if isExpanded { manager.expandedStacks.remove(ext) }
                                                else { manager.expandedStacks.insert(ext) }
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { manager.resignSearchFocus() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .overlay(
            Group {
                if isDropTargeted {
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
            if manager.navigationStack.isEmpty {
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
            } else {
                guard let targetURL = manager.navigationStack.last else { return false }
                var handled = false
                for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                    handled = true
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let fileURL = url else { return }
                        let destURL = manager.uniqueURL(for: fileURL, in: targetURL)
                        do {
                            try FileManager.default.copyItem(at: fileURL, to: destURL)
                            DispatchQueue.main.async {
                                manager.refreshCurrentDirectory()
                            }
                        } catch {
                            NSLog("Drop copy error: \(error.localizedDescription)")
                        }
                    }
                }
                return handled
            }
        }
    }
    
    @ViewBuilder
    private func groupHeader(title: String) -> some View {
        if !title.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .padding(.leading, 4)
        } else {
            EmptyView()
        }
    }
    
    private func handleSingleClick(on entity: FolderSlotEntity, isShiftPressed: Bool) {
        manager.resignSearchFocus()
        
        if isShiftPressed, let lastID = manager.lastSelectedID,
           let startIndex = manager.flatSmartItems.firstIndex(where: { $0.id == lastID }),
           let endIndex = manager.flatSmartItems.firstIndex(where: { $0.id == entity.id }) {
            let lower = min(startIndex, endIndex)
            let upper = max(startIndex, endIndex)
            for i in lower...upper {
                if case .entity(let e) = manager.flatSmartItems[i] {
                    manager.selectedIDs.insert(e.id)
                }
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
    
    final class AutoFocusSearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if self.window != nil {
                DispatchQueue.main.async {
                    self.window?.makeFirstResponder(self)
                    if let fieldEditor = self.window?.fieldEditor(true, for: self) as? NSTextView {
                        fieldEditor.setSelectedRange(NSRange(location: self.stringValue.count, length: 0))
                    }
                }
            }
        }
    }
    
    func makeNSView(context: Context) -> NSSearchField {
        let searchField = AutoFocusSearchField()
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

// MARK: - Stack Header View

struct FolderSlotStackHeaderView: View {
    let ext: String
    let count: Int
    let isExpanded: Bool
    let topEntities: [FolderSlotEntity]
    let onToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                ForEach(Array(topEntities.enumerated().reversed()), id: \.element.id) { index, entity in
                    let offset = CGFloat(index) * 4.0
                    let scale = 1.0 - CGFloat(index) * 0.08
                    
                    FolderSlotThumbnailView(entity: entity, size: 60)
                        .frame(width: 60, height: 60)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: -2, y: 2)
                        .scaleEffect(scale)
                        .offset(x: offset, y: -offset)
                }
                
                if isExpanded {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 60, height: 60)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(6)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .frame(width: 72, height: 72)
            .background(isExpanded ? Color.white.opacity(0.15) : Color.clear)
            .cornerRadius(12)
            
            let extString = ext.isEmpty ? "FILE" : ext.uppercased()
            Text(isExpanded ? "Close Stack" : "\(count) \(extString)s")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isExpanded ? .blue : .white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(4)
        .frame(width: 100, height: 100)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Async Thumbnail View

struct FolderSlotThumbnailView: View {
    let entity: FolderSlotEntity
    let size: CGFloat
    
    @State private var loadedImage: NSImage? = nil
    @State private var isLoading = false
    @State private var imageRequestID: UUID?
    @State private var imageLoadTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: entity.placeholderSymbol)
                    .font(.system(size: size * 0.8))
                    .foregroundColor(entity.isDirectory ? .blue : .white.opacity(0.8))
                    .frame(width: size, height: size)
            }
        }
        .onAppear { loadImage() }
        .onDisappear { cancelImageLoad(); loadedImage = nil }
        .onChange(of: entity.id) { _, _ in reloadImage() }
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
    
    private func loadImage() {
        let targetSize = size * 2
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

// MARK: - Interactive Tile Items

struct FolderSlotItemView: View {
    let entity: FolderSlotEntity
    let isSelected: Bool
    let onSingleClick: (Bool) -> Void
    let onDoubleClick: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            FolderSlotThumbnailView(entity: entity, size: 60)
                .padding(6)
                .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
                .cornerRadius(12)
            
            Text(entity.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(isSelected ? nil : 2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(4)
        .frame(width: 100)
        .frame(minHeight: 100, alignment: .top)
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
