
import SwiftUI

extension UnifiedNotchContainer {
    func calendarPage(contentAreaHeight: CGFloat) -> some View {
        CalendarPageContent(
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            calendarViewOption: settings.calendarViewOption
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    func launcherPage(contentAreaHeight: CGFloat) -> some View {
        LauncherPageContent(
            apps: model.launcherApps,
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
                    model.launcherApps.remove(at: idx)
                    persistLauncherApps(model.launcherApps)
                }
            },
            onAdd: { app in
                model.launcherApps.append(app)
                persistLauncherApps(model.launcherApps)
            },
            onTogglePin: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated[idx].isPinned.toggle()
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
                    model.bookmarkItems.remove(at: idx)
                    persistBookmarkItems(model.bookmarkItems)
                }
            },
            onAdd: { bookmark in
                model.bookmarkItems.append(bookmark)
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
                    model.launcherApps.remove(at: idx)
                    persistLauncherApps(model.launcherApps)
                }
            },
            onAddApp: { app in
                model.launcherApps.append(app)
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
            onRemoveBookmark: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    model.bookmarkItems.remove(at: idx)
                    persistBookmarkItems(model.bookmarkItems)
                }
            },
            onAddBookmark: { bookmark in
                model.bookmarkItems.append(bookmark)
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
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }
}
