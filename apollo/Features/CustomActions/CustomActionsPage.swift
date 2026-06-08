import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Helper Views
struct CustomAppIconView: View {
    let appPath: String
    let size: CGFloat

    var body: some View {
        if let cachedImage = AppIconCache.shared.icon(forPath: appPath) {
            Image(nsImage: cachedImage)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundColor(.white.opacity(0.4))
        }
    }
}

struct BookmarkIconView: View {
    let bookmark: BookmarkItem
    let size: CGFloat
    let accentColor: Color
    
    var body: some View {
        if let base64 = bookmark.iconBase64,
           let image = BookmarkIconCache.shared.image(forBase64: base64) {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            let char = bookmark.name.first?.uppercased() ?? "B"
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(accentColor.opacity(0.2))
                Text(char)
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundColor(accentColor)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Launcher Actions
func launchApp(_ app: LauncherApp) {
    if let bundleId = app.bundleIdentifier,
       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
}

func launchBookmark(_ bookmark: BookmarkItem) {
    var urlStr = bookmark.urlString
    if !urlStr.lowercased().hasPrefix("http://") && !urlStr.lowercased().hasPrefix("https://") {
        urlStr = "https://" + urlStr
    }
    guard let url = URL(string: urlStr) else { return }
    
    if let customBrowserPath = bookmark.customBrowserPath, !customBrowserPath.isEmpty {
        let appURL = URL(fileURLWithPath: customBrowserPath)
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    } else {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - App Scraper
func getInstalledApplications() -> [LauncherApp] {
    let fileManager = FileManager.default
    let appDirs = ["/Applications", "/System/Applications"]
    var apps: [LauncherApp] = []
    
    for dir in appDirs {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
        for file in contents {
            if file.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(file)
                let name = (file as NSString).deletingPathExtension
                let bundle = Bundle(path: path)
                let bundleId = bundle?.bundleIdentifier
                apps.append(LauncherApp(name: name, path: path, bundleIdentifier: bundleId))
            }
        }
    }
    return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
}

// MARK: - Favicon Downloader
func fetchFaviconBase64(for urlString: String, completion: @escaping (String?) -> Void) {
    var cleanURL = urlString
    if !cleanURL.lowercased().hasPrefix("http://") && !cleanURL.lowercased().hasPrefix("https://") {
        cleanURL = "https://" + cleanURL
    }
    guard let url = URL(string: cleanURL), let host = url.host else {
        completion(nil)
        return
    }
    
    let serviceURLStr = "https://www.google.com/s2/favicons?domain=\(host)&sz=128"
    guard let serviceURL = URL(string: serviceURLStr) else {
        completion(nil)
        return
    }
    
    let task = URLSession.shared.dataTask(with: serviceURL) { data, _, error in
        guard let data = data, error == nil,
              let image = NSImage(data: data) else {
            completion(nil)
            return
        }
        
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            completion(pngData.base64EncodedString())
        } else {
            completion(nil)
        }
    }
    task.resume()
}

// MARK: - Peeker Widget View
struct PeekerWidgetView: View {
    let apps: [LauncherApp]
    let bookmarks: [BookmarkItem]
    let showApps: Bool
    let showBookmarks: Bool
    let accentColor: Color
    
    private var pinnedApps: [LauncherApp] {
        apps.filter { $0.isPinned }
    }
    
    private var pinnedBookmarks: [BookmarkItem] {
        bookmarks.filter { $0.isPinned }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if showApps {
                ForEach(pinnedApps) { app in
                    Button {
                        launchApp(app)
                    } label: {
                        CustomAppIconView(appPath: app.path, size: 14)
                    }
                    .buttonStyle(.plain)
                    .help("Launch \(app.name)")
                }
            }
            
            if showApps && showBookmarks && !pinnedApps.isEmpty && !pinnedBookmarks.isEmpty {
                Divider()
                    .frame(height: 10)
                    .background(Color.white.opacity(0.18))
            }
            
            if showBookmarks {
                ForEach(pinnedBookmarks) { bookmark in
                    Button {
                        launchBookmark(bookmark)
                    } label: {
                        BookmarkIconView(bookmark: bookmark, size: 14, accentColor: accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(bookmark.name)")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.04), in: Capsule())
    }
}

// MARK: - Add App Sheet View
struct AddAppSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (LauncherApp) -> Void
    
    @State private var searchPattern = ""
    @State private var scannedApps: [LauncherApp] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Add Application")
                .font(.headline)
                .foregroundColor(.white)
            
            TextField("Search Applications...", text: $searchPattern)
                .textFieldStyle(.plain)
                .padding(6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .foregroundColor(.white)
            
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxHeight: .infinity)
            } else {
                let filtered = scannedApps.filter {
                    searchPattern.isEmpty ? true : $0.name.lowercased().contains(searchPattern.lowercased())
                }
                
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filtered) { app in
                            Button {
                                onAdd(app)
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    CustomAppIconView(appPath: app.path, size: 18)
                                    Text(app.name)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(5)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 160)
            }
            
            HStack {
                Button("Browse File...") {
                    let openPanel = NSOpenPanel()
                    openPanel.allowedContentTypes = [.application]
                    openPanel.canChooseFiles = true
                    openPanel.canChooseDirectories = false
                    openPanel.allowsMultipleSelection = false
                    if openPanel.runModal() == .OK, let url = openPanel.url {
                        let app = LauncherApp(name: url.deletingPathExtension().lastPathComponent, path: url.path, bundleIdentifier: Bundle(url: url)?.bundleIdentifier)
                        onAdd(app)
                        isPresented = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(10)
        .frame(width: 250)
        .background(Color.black.opacity(0.9))
        .onAppear {
            scanAppsBackground()
        }
    }
    
    private func scanAppsBackground() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = getInstalledApplications()
            DispatchQueue.main.async {
                self.scannedApps = apps
                self.isLoading = false
            }
        }
    }
}

// MARK: - Add Bookmark Sheet View
struct AddBookmarkSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (BookmarkItem) -> Void
    
    @State private var name = ""
    @State private var urlString = ""
    @State private var customBrowserPath = ""
    @State private var isPickingFile = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Bookmark")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Name")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                TextField("Website Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("URL")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                TextField("example.com", text: $urlString)
                    .textFieldStyle(.plain)
                    .padding(5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Browser Path (Optional)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                HStack(spacing: 6) {
                    TextField("/Applications/Safari.app", text: $customBrowserPath)
                        .textFieldStyle(.plain)
                        .padding(5)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundColor(.white)
                    
                    Button("Pick...") {
                        isPickingFile = true
                        let openPanel = NSOpenPanel()
                        openPanel.allowedContentTypes = [.application]
                        openPanel.canChooseFiles = true
                        openPanel.canChooseDirectories = false
                        DispatchQueue.main.async {
                            if openPanel.runModal() == .OK, let url = openPanel.url {
                                customBrowserPath = url.path
                            }
                            isPickingFile = false
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Add") {
                    guard !name.isEmpty, !urlString.isEmpty else { return }
                    let item = BookmarkItem(name: name, urlString: urlString, customBrowserPath: customBrowserPath.isEmpty ? nil : customBrowserPath)
                    onAdd(item)
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(10)
        .frame(width: 260)
        .background(Color.black.opacity(0.9))
        .interactiveDismissDisabled(isPickingFile)
    }
}

// MARK: - Launcher Page View
// MARK: - Launcher Page View
struct LauncherPageContent: View, Equatable {
    let apps: [LauncherApp]
    let displayMode: Int
    let columnsCount: Int
    let iconSize: CGFloat
    let textSize: CGFloat
    let showName: Bool
    let width: CGFloat
    let height: CGFloat
    let accentColor: Color
    let showHeader: Bool
    
    let onRemove: (LauncherApp) -> Void
    let onAdd: (LauncherApp) -> Void
    let onTogglePin: (LauncherApp) -> Void
    
    static func == (lhs: LauncherPageContent, rhs: LauncherPageContent) -> Bool {
        lhs.apps == rhs.apps &&
        lhs.displayMode == rhs.displayMode &&
        lhs.columnsCount == rhs.columnsCount &&
        lhs.iconSize == rhs.iconSize &&
        lhs.textSize == rhs.textSize &&
        lhs.showName == rhs.showName &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.accentColor == rhs.accentColor &&
        lhs.showHeader == rhs.showHeader
    }
    
    @State private var isAddPresented = false
    
    var body: some View {
        VStack(spacing: 6) {
            if showHeader {
                HStack {
                    Text("Launcher")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button {
                        isAddPresented = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
            }
            
            if apps.isEmpty {
                VStack {
                    Spacer()
                    Text("No Apps Added")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    if displayMode == 0 {
                        // Grid Mode
                        let cols = max(1, columnsCount)
                        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 6), count: cols)
                        
                        LazyVGrid(columns: gridItems, spacing: 6) {
                            ForEach(apps) { app in
                                Button {
                                    launchApp(app)
                                } label: {
                                    VStack(spacing: 4) {
                                        CustomAppIconView(appPath: app.path, size: iconSize)
                                        if showName {
                                            Text(app.name)
                                                .font(.system(size: max(8, textSize)))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(4)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                        onTogglePin(app)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        onRemove(app)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    } else {
                        // List Mode
                        LazyVStack(spacing: 4) {
                            ForEach(apps) { app in
                                Button {
                                    launchApp(app)
                                } label: {
                                    HStack(spacing: 8) {
                                        CustomAppIconView(appPath: app.path, size: 18)
                                        Text(app.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Button {
                                            onRemove(app)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white.opacity(0.3))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(6)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                        onTogglePin(app)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        onRemove(app)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.top, showHeader ? 0 : 16)
            }
        }
        .frame(width: width, height: height)
        .contextMenu {
            Button("Add Application") {
                isAddPresented = true
            }
        }
        .popover(isPresented: $isAddPresented, arrowEdge: .bottom) {
            AddAppSheet(isPresented: $isAddPresented, onAdd: onAdd)
        }
    }
}

// MARK: - Bookmark Page View
struct BookmarksPageContent: View, Equatable {
    let bookmarks: [BookmarkItem]
    let displayMode: Int
    let columnsCount: Int
    let iconSize: CGFloat
    let textSize: CGFloat
    let showName: Bool
    let width: CGFloat
    let height: CGFloat
    let accentColor: Color
    let showHeader: Bool
    
    let onRemove: (BookmarkItem) -> Void
    let onAdd: (BookmarkItem) -> Void
    let onTogglePin: (BookmarkItem) -> Void
    
    static func == (lhs: BookmarksPageContent, rhs: BookmarksPageContent) -> Bool {
        lhs.bookmarks == rhs.bookmarks &&
        lhs.displayMode == rhs.displayMode &&
        lhs.columnsCount == rhs.columnsCount &&
        lhs.iconSize == rhs.iconSize &&
        lhs.textSize == rhs.textSize &&
        lhs.showName == rhs.showName &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.accentColor == rhs.accentColor &&
        lhs.showHeader == rhs.showHeader
    }
    
    @State private var isAddPresented = false
    
    var body: some View {
        VStack(spacing: 6) {
            if showHeader {
                HStack {
                    Text("Bookmarks")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button {
                        isAddPresented = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
            }
            
            if bookmarks.isEmpty {
                VStack {
                    Spacer()
                    Text("No Bookmarks Added")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    if displayMode == 0 {
                        // Grid Mode
                        let cols = max(1, columnsCount)
                        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 6), count: cols)
                        
                        LazyVGrid(columns: gridItems, spacing: 6) {
                            ForEach(bookmarks) { bookmark in
                                Button {
                                    launchBookmark(bookmark)
                                } label: {
                                    VStack(spacing: 4) {
                                        BookmarkIconView(bookmark: bookmark, size: iconSize, accentColor: accentColor)
                                        if showName {
                                            Text(bookmark.name)
                                                .font(.system(size: max(8, textSize)))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(bookmark.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                        onTogglePin(bookmark)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        onRemove(bookmark)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    } else {
                        // List Mode
                        LazyVStack(spacing: 4) {
                            ForEach(bookmarks) { bookmark in
                                Button {
                                    launchBookmark(bookmark)
                                } label: {
                                    HStack(spacing: 8) {
                                        BookmarkIconView(bookmark: bookmark, size: 16, accentColor: accentColor)
                                        Text(bookmark.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Button {
                                            onRemove(bookmark)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white.opacity(0.3))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(6)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(bookmark.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                        onTogglePin(bookmark)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        onRemove(bookmark)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.top, showHeader ? 0 : 16)
            }
        }
        .frame(width: width, height: height)
        .contextMenu {
            Button("Add Bookmark") {
                isAddPresented = true
            }
        }
        .popover(isPresented: $isAddPresented, arrowEdge: .bottom) {
            AddBookmarkSheet(isPresented: $isAddPresented, onAdd: onAdd)
        }
    }
}

// MARK: - Combined Custom Actions View
struct CombinedActionsPageContent: View, Equatable {
    @ObservedObject var model: NotchMenuModel
    let apps: [LauncherApp]
    let bookmarks: [BookmarkItem]
    let launcherMode: Int
    let bookmarkMode: Int
    let launcherColumns: Int
    let bookmarkColumns: Int
    let launcherIconSize: CGFloat
    let launcherTextSize: CGFloat
    let launcherShowName: Bool
    let bookmarkIconSize: CGFloat
    let bookmarkTextSize: CGFloat
    let bookmarkShowName: Bool
    let width: CGFloat
    let height: CGFloat
    let accentColor: Color
    
    let onRemoveApp: (LauncherApp) -> Void
    let onAddApp: (LauncherApp) -> Void
    let onTogglePinApp: (LauncherApp) -> Void
    let onRemoveBookmark: (BookmarkItem) -> Void
    let onAddBookmark: (BookmarkItem) -> Void
    let onTogglePinBookmark: (BookmarkItem) -> Void
    
    static func == (lhs: CombinedActionsPageContent, rhs: CombinedActionsPageContent) -> Bool {
        lhs.apps == rhs.apps &&
        lhs.bookmarks == rhs.bookmarks &&
        lhs.launcherMode == rhs.launcherMode &&
        lhs.bookmarkMode == rhs.bookmarkMode &&
        lhs.launcherColumns == rhs.launcherColumns &&
        lhs.bookmarkColumns == rhs.bookmarkColumns &&
        lhs.launcherIconSize == rhs.launcherIconSize &&
        lhs.launcherTextSize == rhs.launcherTextSize &&
        lhs.launcherShowName == rhs.launcherShowName &&
        lhs.bookmarkIconSize == rhs.bookmarkIconSize &&
        lhs.bookmarkTextSize == rhs.bookmarkTextSize &&
        lhs.bookmarkShowName == rhs.bookmarkShowName &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.accentColor == rhs.accentColor
    }
    
    var body: some View {
        let halfWidth = max(40, (width - 12) / 2)
        HStack(spacing: 0) {
            // Left Column (Apps/Launcher)
            LauncherPageContent(
                apps: apps,
                displayMode: launcherMode,
                columnsCount: max(1, launcherColumns / 2),
                iconSize: launcherIconSize,
                textSize: launcherTextSize,
                showName: launcherShowName,
                width: halfWidth,
                height: height,
                accentColor: accentColor,
                showHeader: false,
                onRemove: onRemoveApp,
                onAdd: onAddApp,
                onTogglePin: onTogglePinApp
            )
            .frame(width: halfWidth, height: height, alignment: .topLeading)
            
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)
            
            // Right Column (Bookmarks)
            BookmarksPageContent(
                bookmarks: bookmarks,
                displayMode: bookmarkMode,
                columnsCount: max(1, bookmarkColumns / 2),
                iconSize: bookmarkIconSize,
                textSize: bookmarkTextSize,
                showName: bookmarkShowName,
                width: halfWidth,
                height: height,
                accentColor: accentColor,
                showHeader: false,
                onRemove: onRemoveBookmark,
                onAdd: onAddBookmark,
                onTogglePin: onTogglePinBookmark
            )
            .frame(width: halfWidth, height: height, alignment: .topTrailing)
        }
        .frame(width: width, height: height, alignment: .center)
    }
}
