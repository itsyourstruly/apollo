import SwiftUI

extension UnifiedNotchContainer {
    func calendarPage(contentAreaHeight: CGFloat) -> some View {
        CalendarPageContent(
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            calendarViewOption: settings.calendarViewOption,
            calendarWeekStartsOn: settings.calendarWeekStartsOn
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    func launcherPage(contentAreaHeight: CGFloat) -> some View {
        LauncherPageContent(
            apps: model.launcherApps,
            currentFolderID: model.launcherCurrentFolderID,
            displayMode: settings.launcherDisplayMode,
            columnsCount: settings.launcherColumns,
            iconSize: settings.launcherIconSize,
            textSize: settings.launcherTextSize,
            showName: settings.launcherShowName,
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            showHeader: false,
            onRemove: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated.remove(at: idx)
                    if app.isFolder == true {
                        updated.removeAll { $0.parentId == app.id }
                    }
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            },
            onAdd: { app in
                var newApp = app
                newApp.parentId = model.launcherCurrentFolderID
                model.launcherApps.append(newApp)
                persistLauncherApps(model.launcherApps)
            },
            onTogglePin: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated[idx].isPinned.toggle()
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            },
            onOpenFolder: { app in
                withAnimation {
                    model.launcherCurrentFolderID = app.id
                }
            },
            onDropApp: { draggedId, targetApp in
                guard draggedId != targetApp.id else { return }
                var updated = model.launcherApps
                guard let draggedIdx = updated.firstIndex(where: { $0.id == draggedId }) else { return }
                
                if targetApp.isFolder == true {
                    updated[draggedIdx].parentId = targetApp.id
                } else {
                    let folderId = UUID()
                    let folderApp = LauncherApp(
                        id: folderId,
                        name: "New Folder",
                        path: "",
                        bundleIdentifier: nil,
                        isPeekerPinned: false,
                        isFolder: true,
                        parentId: model.launcherCurrentFolderID
                    )
                    updated[draggedIdx].parentId = folderId
                    if let targetIdx = updated.firstIndex(where: { $0.id == targetApp.id }) {
                        updated[targetIdx].parentId = folderId
                    }
                    updated.append(folderApp)
                }
                model.launcherApps = updated
                persistLauncherApps(updated)
            },
            onMoveAppOut: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated[idx].parentId = nil
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            },
            onRenameFolder: { folder, newName in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == folder.id }) {
                    var updated = model.launcherApps
                    updated[idx].name = newName
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    func bookmarksPage(contentAreaHeight: CGFloat) -> some View {
        BookmarksPageContent(
            bookmarks: model.bookmarkItems,
            currentFolderID: model.bookmarksCurrentFolderID,
            displayMode: settings.bookmarkDisplayMode,
            columnsCount: settings.bookmarkColumns,
            iconSize: settings.bookmarkIconSize,
            textSize: settings.bookmarkTextSize,
            showName: settings.bookmarkShowName,
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            showHeader: false,
            onRemove: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated.remove(at: idx)
                    if bookmark.isFolder == true {
                        updated.removeAll { $0.parentId == bookmark.id }
                    }
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            },
            onAdd: { bookmark in
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
            },
            onTogglePin: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].isPinned.toggle()
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            },
            onOpenFolder: { bookmark in
                withAnimation {
                    model.bookmarksCurrentFolderID = bookmark.id
                }
            },
            onDropBookmark: { draggedId, targetBookmark in
                guard draggedId != targetBookmark.id else { return }
                var updated = model.bookmarkItems
                guard let draggedIdx = updated.firstIndex(where: { $0.id == draggedId }) else { return }
                
                if targetBookmark.isFolder == true {
                    updated[draggedIdx].parentId = targetBookmark.id
                } else {
                    let folderId = UUID()
                    let folderBookmark = BookmarkItem(
                        id: folderId,
                        name: "New Folder",
                        urlString: "",
                        customBrowserPath: nil,
                        iconBase64: nil,
                        isPeekerPinned: false,
                        isFolder: true,
                        parentId: model.bookmarksCurrentFolderID
                    )
                    updated[draggedIdx].parentId = folderId
                    if let targetIdx = updated.firstIndex(where: { $0.id == targetBookmark.id }) {
                        updated[targetIdx].parentId = folderId
                    }
                    updated.append(folderBookmark)
                }
                model.bookmarkItems = updated
                persistBookmarkItems(updated)
            },
            onMoveBookmarkOut: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].parentId = nil
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            },
            onRenameFolder: { folder, newName in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == folder.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].name = newName
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    func customCombinedPage(contentAreaHeight: CGFloat) -> some View {
        CombinedActionsPageContent(
            model: model,
            apps: model.launcherApps,
            bookmarks: model.bookmarkItems,
            launcherCurrentFolderID: model.launcherCurrentFolderID,
            bookmarksCurrentFolderID: model.bookmarksCurrentFolderID,
            launcherMode: settings.launcherDisplayMode,
            bookmarkMode: settings.bookmarkDisplayMode,
            launcherColumns: settings.launcherColumns,
            bookmarkColumns: settings.bookmarkColumns,
            launcherIconSize: settings.launcherIconSize,
            launcherTextSize: settings.launcherTextSize,
            launcherShowName: settings.launcherShowName,
            bookmarkIconSize: settings.bookmarkIconSize,
            bookmarkTextSize: settings.bookmarkTextSize,
            bookmarkShowName: settings.bookmarkShowName,
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            onRemoveApp: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated.remove(at: idx)
                    if app.isFolder == true {
                        updated.removeAll { $0.parentId == app.id }
                    }
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            },
            onAddApp: { app in
                var newApp = app
                newApp.parentId = model.launcherCurrentFolderID
                model.launcherApps.append(newApp)
                persistLauncherApps(model.launcherApps)
            },
            onTogglePinApp: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated[idx].isPinned.toggle()
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            },
            onOpenLauncherFolder: { app in
                withAnimation {
                    model.launcherCurrentFolderID = app.id
                }
            },
            onDropApp: { draggedId, targetApp in
                guard draggedId != targetApp.id else { return }
                var updated = model.launcherApps
                guard let draggedIdx = updated.firstIndex(where: { $0.id == draggedId }) else { return }
                
                if targetApp.isFolder == true {
                    updated[draggedIdx].parentId = targetApp.id
                } else {
                    let folderId = UUID()
                    let folderApp = LauncherApp(
                        id: folderId,
                        name: "New Folder",
                        path: "",
                        bundleIdentifier: nil,
                        isPeekerPinned: false,
                        isFolder: true,
                        parentId: model.launcherCurrentFolderID
                    )
                    updated[draggedIdx].parentId = folderId
                    if let targetIdx = updated.firstIndex(where: { $0.id == targetApp.id }) {
                        updated[targetIdx].parentId = folderId
                    }
                    updated.append(folderApp)
                }
                model.launcherApps = updated
                persistLauncherApps(updated)
            },
            onMoveAppOut: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated[idx].parentId = nil
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            },
            onRenameLauncherFolder: { folder, newName in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == folder.id }) {
                    var updated = model.launcherApps
                    updated[idx].name = newName
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            }, onRemoveBookmark: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated.remove(at: idx)
                    if bookmark.isFolder == true {
                        updated.removeAll { $0.parentId == bookmark.id }
                    }
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            },
            onAddBookmark: { bookmark in
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
            },
            onTogglePinBookmark: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].isPinned.toggle()
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            },
            onOpenBookmarksFolder: { bookmark in
                withAnimation {
                    model.bookmarksCurrentFolderID = bookmark.id
                }
            },
            onDropBookmark: { draggedId, targetBookmark in
                guard draggedId != targetBookmark.id else { return }
                var updated = model.bookmarkItems
                guard let draggedIdx = updated.firstIndex(where: { $0.id == draggedId }) else { return }
                
                if targetBookmark.isFolder == true {
                    updated[draggedIdx].parentId = targetBookmark.id
                } else {
                    let folderId = UUID()
                    let folderBookmark = BookmarkItem(
                        id: folderId,
                        name: "New Folder",
                        urlString: "",
                        customBrowserPath: nil,
                        iconBase64: nil,
                        isPeekerPinned: false,
                        isFolder: true,
                        parentId: model.bookmarksCurrentFolderID
                    )
                    updated[draggedIdx].parentId = folderId
                    if let targetIdx = updated.firstIndex(where: { $0.id == targetBookmark.id }) {
                        updated[targetIdx].parentId = folderId
                    }
                    updated.append(folderBookmark)
                }
                model.bookmarkItems = updated
                persistBookmarkItems(updated)
            },
            onMoveBookmarkOut: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].parentId = nil
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            },
            onRenameBookmarksFolder: { folder, newName in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == folder.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].name = newName
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }
}
