
import SwiftUI
import AppKit

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
