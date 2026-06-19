import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Launcher Page View
struct LauncherPageContent: View, Equatable {
    let apps: [LauncherApp]
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
    
    let onRemove: (LauncherApp) -> Void
    let onAdd: (LauncherApp) -> Void
    let onTogglePin: (LauncherApp) -> Void
    let onOpenFolder: (LauncherApp) -> Void
    let onDropApp: (UUID, LauncherApp) -> Void
    let onMoveAppOut: (LauncherApp) -> Void
    let onRenameFolder: (LauncherApp, String) -> Void
    
    static func == (lhs: LauncherPageContent, rhs: LauncherPageContent) -> Bool {
        lhs.apps == rhs.apps &&
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
    @State private var folderToRename: LauncherApp? = nil
    @State private var renameName = ""
    
    var body: some View {
        let visibleApps = apps.filter { $0.parentId == currentFolderID }
        let resolvedIconSize = currentFolderID != nil ? iconSize * 1.25 : iconSize
        let resolvedListIconSize: CGFloat = currentFolderID != nil ? 22 : 18
        
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
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
            }
            
            if visibleApps.isEmpty {
                VStack {
                    Spacer()
                    Text(currentFolderID == nil ? "No Apps Added" : "Folder is Empty")
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
                            ForEach(visibleApps) { app in
                                Button {
                                    if app.isFolder == true {
                                        onOpenFolder(app)
                                    } else {
                                        launchApp(app)
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        if app.isFolder == true {
                                            let folderApps = apps.filter { $0.parentId == app.id }
                                            AppFolderIconView(apps: folderApps, size: resolvedIconSize)
                                        } else {
                                            CustomAppIconView(appPath: app.path, size: resolvedIconSize)
                                        }
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
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if app.isFolder == true {
                                        Button("Rename...") {
                                            folderToRename = app
                                            renameName = app.name
                                            isRenamePresented = true
                                        }
                                        Divider()
                                    }
                                    if app.parentId != nil {
                                        Button("Move out of Folder") {
                                            onMoveAppOut(app)
                                        }
                                        Divider()
                                    }
                                    if app.isFolder != true {
                                        Button(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                            onTogglePin(app)
                                        }
                                        Divider()
                                    }
                                    Button("Remove", role: .destructive) {
                                        onRemove(app)
                                    }
                                }
                                .onDrag {
                                    guard app.isFolder != true else { return NSItemProvider() }
                                    return NSItemProvider(object: "app:\(app.id.uuidString)" as NSString)
                                }
                                .onDrop(of: [.text], isTargeted: nil) { providers in
                                    if let provider = providers.first {
                                        provider.loadObject(ofClass: NSString.self) { nsString, error in
                                            guard let str = nsString as? String else { return }
                                            if str.hasPrefix("app:") {
                                                let idStr = String(str.dropFirst(4))
                                                if let uuid = UUID(uuidString: idStr) {
                                                    DispatchQueue.main.async {
                                                        onDropApp(uuid, app)
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
                            ForEach(visibleApps) { app in
                                Button {
                                    if app.isFolder == true {
                                        onOpenFolder(app)
                                    } else {
                                        launchApp(app)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if app.isFolder == true {
                                            let folderApps = apps.filter { $0.parentId == app.id }
                                            AppFolderIconView(apps: folderApps, size: resolvedListIconSize)
                                        } else {
                                            CustomAppIconView(appPath: app.path, size: resolvedListIconSize)
                                        }
                                        Text(app.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Button {
                                            onRemove(app)
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
                                    if app.isFolder == true {
                                        Button("Rename...") {
                                            folderToRename = app
                                            renameName = app.name
                                            isRenamePresented = true
                                        }
                                        Divider()
                                    }
                                    if app.parentId != nil {
                                        Button("Move out of Folder") {
                                            onMoveAppOut(app)
                                        }
                                        Divider()
                                    }
                                    if app.isFolder != true {
                                        Button(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                            onTogglePin(app)
                                        }
                                        Divider()
                                    }
                                    Button("Remove", role: .destructive) {
                                        onRemove(app)
                                    }
                                }
                                .onDrag {
                                    guard app.isFolder != true else { return NSItemProvider() }
                                    return NSItemProvider(object: "app:\(app.id.uuidString)" as NSString)
                                }
                                .onDrop(of: [.text], isTargeted: nil) { providers in
                                    if let provider = providers.first {
                                        provider.loadObject(ofClass: NSString.self) { nsString, error in
                                            guard let str = nsString as? String else { return }
                                            if str.hasPrefix("app:") {
                                                let idStr = String(str.dropFirst(4))
                                                if let uuid = UUID(uuidString: idStr) {
                                                    DispatchQueue.main.async {
                                                        onDropApp(uuid, app)
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
            Button("Add Application") {
                isAddPresented = true
            }
        }
        .popover(isPresented: $isAddPresented, arrowEdge: .bottom) {
            AddAppSheet(isPresented: $isAddPresented, onAdd: onAdd)
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
