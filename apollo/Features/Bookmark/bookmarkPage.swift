import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Bookmark Page View
struct BookmarksPageContent: View, Equatable {
    let bookmarks: [BookmarkItem]
    let currentFolderID: UUID?
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
    let onOpenFolder: (BookmarkItem) -> Void
    let onDropBookmark: (UUID, BookmarkItem) -> Void
    let onMoveBookmarkOut: (BookmarkItem) -> Void
    let onRenameFolder: (BookmarkItem, String) -> Void
    
    static func == (lhs: BookmarksPageContent, rhs: BookmarksPageContent) -> Bool {
        lhs.bookmarks == rhs.bookmarks &&
        lhs.currentFolderID == rhs.currentFolderID &&
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
    @State private var isRenamePresented = false
    @State private var folderToRename: BookmarkItem? = nil
    @State private var renameName = ""
    
    var body: some View {
        let visibleBookmarks = bookmarks.filter { $0.parentId == currentFolderID }
        let resolvedIconSize = currentFolderID != nil ? iconSize * 1.25 : iconSize
        let resolvedListIconSize: CGFloat = currentFolderID != nil ? 20 : 16
        
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
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
            }
            
            if visibleBookmarks.isEmpty {
                VStack {
                    Spacer()
                    Text(currentFolderID == nil ? "No Bookmarks Added" : "Folder is Empty")
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
                            ForEach(visibleBookmarks) { bookmark in
                                Button {
                                    if bookmark.isFolder == true {
                                        onOpenFolder(bookmark)
                                    } else {
                                        launchBookmark(bookmark)
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        if bookmark.isFolder == true {
                                            let folderBookmarks = bookmarks.filter { $0.parentId == bookmark.id }
                                            BookmarkFolderIconView(bookmarks: folderBookmarks, size: resolvedIconSize, accentColor: accentColor)
                                        } else {
                                            BookmarkIconView(bookmark: bookmark, size: resolvedIconSize, accentColor: accentColor)
                                        }
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
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if bookmark.isFolder == true {
                                        Button("Rename...") {
                                            folderToRename = bookmark
                                            renameName = bookmark.name
                                            isRenamePresented = true
                                        }
                                        Divider()
                                    }
                                    if bookmark.parentId != nil {
                                        Button("Move out of Folder") {
                                            onMoveBookmarkOut(bookmark)
                                        }
                                        Divider()
                                    }
                                    if bookmark.isFolder != true {
                                        Button(bookmark.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                            onTogglePin(bookmark)
                                        }
                                        Divider()
                                    }
                                    Button("Remove", role: .destructive) {
                                        onRemove(bookmark)
                                    }
                                }
                                .onDrag {
                                    guard bookmark.isFolder != true else { return NSItemProvider() }
                                    return NSItemProvider(object: "bookmark:\(bookmark.id.uuidString)" as NSString)
                                }
                                .onDrop(of: [.text], isTargeted: nil) { providers in
                                    if let provider = providers.first {
                                        provider.loadObject(ofClass: NSString.self) { nsString, error in
                                            guard let str = nsString as? String else { return }
                                            if str.hasPrefix("bookmark:") {
                                                let idStr = String(str.dropFirst(9))
                                                if let uuid = UUID(uuidString: idStr) {
                                                    DispatchQueue.main.async {
                                                        onDropBookmark(uuid, bookmark)
                                                    }
                                                }
                                            }
                                        }
                                        return true
                                    }
                                    return false
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    } else {
                        // List Mode
                        LazyVStack(spacing: 4) {
                            ForEach(visibleBookmarks) { bookmark in
                                Button {
                                    if bookmark.isFolder == true {
                                        onOpenFolder(bookmark)
                                    } else {
                                        launchBookmark(bookmark)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if bookmark.isFolder == true {
                                            let folderBookmarks = bookmarks.filter { $0.parentId == bookmark.id }
                                            BookmarkFolderIconView(bookmarks: folderBookmarks, size: resolvedListIconSize, accentColor: accentColor)
                                        } else {
                                            BookmarkIconView(bookmark: bookmark, size: resolvedListIconSize, accentColor: accentColor)
                                        }
                                        Text(bookmark.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Button {
                                            onRemove(bookmark)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white.opacity(0.3))
                                                .padding(6)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(6)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if bookmark.isFolder == true {
                                        Button("Rename...") {
                                            folderToRename = bookmark
                                            renameName = bookmark.name
                                            isRenamePresented = true
                                        }
                                        Divider()
                                    }
                                    if bookmark.parentId != nil {
                                        Button("Move out of Folder") {
                                            onMoveBookmarkOut(bookmark)
                                        }
                                        Divider()
                                    }
                                    if bookmark.isFolder != true {
                                        Button(bookmark.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                            onTogglePin(bookmark)
                                        }
                                        Divider()
                                    }
                                    Button("Remove", role: .destructive) {
                                        onRemove(bookmark)
                                    }
                                }
                                .onDrag {
                                    guard bookmark.isFolder != true else { return NSItemProvider() }
                                    return NSItemProvider(object: "bookmark:\(bookmark.id.uuidString)" as NSString)
                                }
                                .onDrop(of: [.text], isTargeted: nil) { providers in
                                    if let provider = providers.first {
                                        provider.loadObject(ofClass: NSString.self) { nsString, error in
                                            guard let str = nsString as? String else { return }
                                            if str.hasPrefix("bookmark:") {
                                                let idStr = String(str.dropFirst(9))
                                                if let uuid = UUID(uuidString: idStr) {
                                                    DispatchQueue.main.async {
                                                        onDropBookmark(uuid, bookmark)
                                                    }
                                                }
                                            }
                                        }
                                        return true
                                    }
                                    return false
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .frame(width: width, height: showHeader ? max(1, height - 26) : height, alignment: .center)
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
        .alert("Rename Folder", isPresented: $isRenamePresented) {
            TextField("Folder Name", text: $renameName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let folder = folderToRename {
                    onRenameFolder(folder, renameName)
                }
            }
        }
    }
}
