import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BoxPageContent: View, Equatable {
    let files: [BoxFile]
    let selectedIDs: Set<UUID>
    let width: CGFloat
    let height: CGFloat
    let columnCount: Int
    let accentColor: NSColor
    let showNames: Bool
    let nameSize: CGFloat
    let isTargeted: Bool
    let isSlimMode: Bool
    let isCollapsed: Bool
    let showCollapseButton: Bool

    let onRemove: (BoxFile) -> Void
    let onToggleSelect: (BoxFile) -> Void
    let onSelectForDrag: (BoxFile) -> Void
    let urlsForDrag: (BoxFile) -> [URL]
    let handleDrop: ([NSItemProvider]) -> Bool
    let setIsTargeted: (Bool) -> Void
    let onToggleCollapse: () -> Void

    static func == (lhs: BoxPageContent, rhs: BoxPageContent) -> Bool {
        lhs.files == rhs.files &&
        lhs.selectedIDs == rhs.selectedIDs &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.columnCount == rhs.columnCount &&
        lhs.accentColor == rhs.accentColor &&
        lhs.showNames == rhs.showNames &&
        lhs.nameSize == rhs.nameSize &&
        lhs.isTargeted == rhs.isTargeted &&
        lhs.isSlimMode == rhs.isSlimMode &&
        lhs.isCollapsed == rhs.isCollapsed &&
        lhs.showCollapseButton == rhs.showCollapseButton
    }

    private var chunkedFiles: [[BoxFile]] {
        var chunks: [[BoxFile]] = []
        let cols = max(1, columnCount)
        for i in stride(from: 0, to: files.count, by: cols) {
            let end = min(i + cols, files.count)
            chunks.append(Array(files[i..<end]))
        }
        return chunks
    }

    var body: some View {
        let safeW = max(1, width)
        let safeH = max(1, height)
        let settings = AppSettings.shared
        
        Group {
            if isSlimMode {
                ZStack(alignment: .top) {
                    if files.isEmpty {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(isTargeted ? Color(accentColor) : Color.brown.opacity(0.7))
                            .frame(width: safeW, height: safeH, alignment: .center)
                    } else {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 40)
                            
                            Group {
                                let itemSize: CGFloat = min(CGFloat(settings.boxSlimModeItemWidth), CGFloat(settings.boxSlimModeItemHeight))
                                let direction = settings.boxSlimModeExpandDirection // 0 = Horizontal, 1 = Vertical
                                
                                let padding: CGFloat = 24
                                let spacing: CGFloat = 8
                                
                                if direction == 0 { // Horizontal
                                    let fits = !isCollapsed && files.count <= Int(settings.boxSlimModeMaxViewSize)
                                    
                                    if fits {
                                        HStack(spacing: spacing) {
                                            ForEach(files) { file in
                                                SafeCachedBoxItemView(
                                                    file: file,
                                                    maxSize: itemSize,
                                                    isSelected: selectedIDs.contains(file.id),
                                                    accentColor: accentColor,
                                                    showBoxFileNames: settings.showBoxFileNames,
                                                    fileNameSize: settings.boxFileNameSize,
                                                    onRemove: { onRemove(file) },
                                                    urlsForDrag: { urlsForDrag(file) },
                                                    selectForDrag: { onSelectForDrag(file) },
                                                    toggleSelection: { onToggleSelect(file) }
                                                )
                                            }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    } else {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: spacing) {
                                                ForEach(files) { file in
                                                    SafeCachedBoxItemView(
                                                        file: file,
                                                        maxSize: itemSize,
                                                        isSelected: selectedIDs.contains(file.id),
                                                        accentColor: accentColor,
                                                        showBoxFileNames: settings.showBoxFileNames,
                                                        fileNameSize: settings.boxFileNameSize,
                                                        onRemove: { onRemove(file) },
                                                        urlsForDrag: { urlsForDrag(file) },
                                                        selectForDrag: { onSelectForDrag(file) },
                                                        toggleSelection: { onToggleSelect(file) }
                                                    )
                                                }
                                            }
                                            .padding(.horizontal, padding)
                                            .frame(minWidth: safeW, minHeight: max(1, safeH - 40), alignment: .center)
                                        }
                                        .clipped()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                } else { // Vertical
                                    let fits = !isCollapsed && files.count <= Int(settings.boxSlimModeMaxViewSize)
                                    
                                    if fits {
                                        VStack(spacing: spacing) {
                                            ForEach(files) { file in
                                                SafeCachedBoxItemView(
                                                    file: file,
                                                    maxSize: itemSize,
                                                    isSelected: selectedIDs.contains(file.id),
                                                    accentColor: accentColor,
                                                    showBoxFileNames: settings.showBoxFileNames,
                                                    fileNameSize: settings.boxFileNameSize,
                                                    onRemove: { onRemove(file) },
                                                    urlsForDrag: { urlsForDrag(file) },
                                                    selectForDrag: { onSelectForDrag(file) },
                                                    toggleSelection: { onToggleSelect(file) }
                                                )
                                            }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    } else {
                                        ScrollView(.vertical, showsIndicators: false) {
                                            VStack(spacing: spacing) {
                                                ForEach(files) { file in
                                                    SafeCachedBoxItemView(
                                                        file: file,
                                                        maxSize: itemSize,
                                                        isSelected: selectedIDs.contains(file.id),
                                                        accentColor: accentColor,
                                                        showBoxFileNames: settings.showBoxFileNames,
                                                        fileNameSize: settings.boxFileNameSize,
                                                        onRemove: { onRemove(file) },
                                                        urlsForDrag: { urlsForDrag(file) },
                                                        selectForDrag: { onSelectForDrag(file) },
                                                        toggleSelection: { onToggleSelect(file) }
                                                    )
                                                }
                                            }
                                            .padding(.vertical, padding)
                                            .frame(minWidth: safeW, minHeight: max(1, safeH - 40), alignment: .center)
                                        }
                                        .clipped()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(width: safeW, height: safeH)
                    }
                    
                    if !files.isEmpty {
                        HStack(spacing: 4) {
                            Spacer()
                            
                            if showCollapseButton {
                                let direction = settings.boxSlimModeExpandDirection // 0 = Horizontal, 1 = Vertical
                                let iconName = direction == 0 
                                    ? (isCollapsed ? "chevron.right" : "chevron.left")
                                    : (isCollapsed ? "chevron.down" : "chevron.up")
                                    
                                Color.clear
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                                    .overlay {
                                        Image(systemName: iconName)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white.opacity(0.65))
                                    }
                                    .highPriorityGesture(
                                        TapGesture()
                                            .onEnded {
                                                onToggleCollapse()
                                            }
                                    )
                                    .padding(.top, 4)
                            }
                            
                            Color.clear
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                                .overlay {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.65))
                                    }
                                .highPriorityGesture(
                                    TapGesture()
                                        .onEnded {
                                            DispatchQueue.main.async {
                                                if let delegate = NSApp.delegate as? AppDelegate {
                                                    delegate.hideSlimBox()
                                                }
                                            }
                                        }
                                )
                                .padding(.top, 4)
                                .padding(.trailing, 4)
                        }
                        .frame(width: safeW)
                    }
                    
                    if !files.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                BoxShareButton(files: files, selectedIDs: selectedIDs, accentColor: accentColor)
                                    .padding(.bottom, 6)
                                    .padding(.trailing, 6)
                            }
                        }
                        .frame(width: safeW, height: safeH)
                    }
                }
                .frame(width: safeW, height: safeH, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    if files.isEmpty {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: min(safeW, safeH) * 0.22, weight: .semibold))
                            .foregroundColor(.brown.opacity(0.55))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        let cols = max(1, columnCount)
                        let maxSize = max(1, min((safeW - 16) / CGFloat(cols), safeH * 0.38))
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 2) {
                                ForEach(chunkedFiles, id: \.first?.id) { row in
                                    HStack(spacing: 2) {
                                        ForEach(row) { file in
                                            SafeCachedBoxItemView(
                                                file: file,
                                                maxSize: maxSize,
                                                isSelected: selectedIDs.contains(file.id),
                                                accentColor: accentColor,
                                                showBoxFileNames: showNames,
                                                fileNameSize: nameSize,
                                                onRemove: { onRemove(file) },
                                                urlsForDrag: { urlsForDrag(file) },
                                                selectForDrag: { onSelectForDrag(file) },
                                                toggleSelection: { onToggleSelect(file) }
                                            )
                                            .frame(maxWidth: .infinity)
                                        }
                                        if row.count < cols {
                                            ForEach(0..<(cols - row.count), id: \.self) { _ in
                                                Color.clear.frame(maxWidth: .infinity)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(width: width, alignment: .center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: width, height: safeH, alignment: .top)
                .overlay(alignment: .bottomTrailing) {
                    if !files.isEmpty {
                        BoxShareButton(files: files, selectedIDs: selectedIDs, accentColor: accentColor)
                            .padding(.trailing, 4)
                            .padding(.bottom, 2)
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { isTargeted }, set: { setIsTargeted($0) }), perform: handleDrop)
    }
}

extension UnifiedNotchContainer {
    // MARK: - Box Page
    func boxPage(contentAreaHeight: CGFloat) -> some View {
        let activeWidth: CGFloat
        if isSlimModeActive {
            activeWidth = model.slimBoxWidth
        } else {
            activeWidth = scaledPanelWidth(for: settings)
        }
        let displayedFiles = model.boxFiles
            
        return BoxPageContent(
            files: displayedFiles,
            selectedIDs: selectedBoxFileIDs,
            width: activeWidth,
            height: max(1, contentAreaHeight - pageTopContentInset),
            columnCount: isSlimModeActive ? 1 : settings.boxColumns,
            accentColor: settings.accentColor,
            showNames: isSlimModeActive ? false : settings.showBoxFileNames,
            nameSize: settings.boxFileNameSize,
            isTargeted: isBoxDropTargeted,
            isSlimMode: isSlimModeActive,
            isCollapsed: model.isSlimBoxCollapsed,
            showCollapseButton: isSlimModeActive && model.boxFiles.count > 1,
            onRemove: { file in
                DispatchQueue.main.async {
                    withAnimation {
                        model.boxFiles.removeAll { $0.id == file.id }
                        selectedBoxFileIDs.remove(file.id)
                    }
                }
            },
            onToggleSelect: { file in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    if selectedBoxFileIDs.contains(file.id) {
                        selectedBoxFileIDs.remove(file.id)
                    } else {
                        selectedBoxFileIDs.insert(file.id)
                    }
                }
            },
            onSelectForDrag: { file in
                if !selectedBoxFileIDs.contains(file.id) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        _ = selectedBoxFileIDs.insert(file.id)
                    }
                }
            },
            urlsForDrag: { file in
                let selectedURLs = model.boxFiles.compactMap { selectedBoxFileIDs.contains($0.id) ? $0.url : nil }
                return selectedURLs.isEmpty ? [file.url] : selectedURLs
            },
            handleDrop: handleBoxDrop,
            setIsTargeted: { isBoxDropTargeted = $0 },
            onToggleCollapse: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    model.isSlimBoxCollapsed.toggle()
                }
                DispatchQueue.main.async {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.updateSlimBoxWindowFrame()
                    }
                }
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }
}
