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
    let itemSize: CGFloat
    
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
                        CustomAppIconView(appPath: app.path, size: itemSize)
                    }
                    .buttonStyle(.plain)
                    .help("Launch \(app.name)")
                }
            }
            
            if showApps && showBookmarks && !pinnedApps.isEmpty && !pinnedBookmarks.isEmpty {
                Divider()
                    .frame(height: max(6, itemSize * 0.7))
                    .background(Color.white.opacity(0.18))
            }
            
            if showBookmarks {
                ForEach(pinnedBookmarks) { bookmark in
                    Button {
                        launchBookmark(bookmark)
                    } label: {
                        BookmarkIconView(bookmark: bookmark, size: itemSize, accentColor: accentColor)
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
