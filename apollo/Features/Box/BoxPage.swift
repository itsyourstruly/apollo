import SwiftUI
import AppKit

// MARK: - Reintegrated Box
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

    let onRemove: (BoxFile) -> Void
    let onToggleSelect: (BoxFile) -> Void
    let onSelectForDrag: (BoxFile) -> Void
    let urlsForDrag: (BoxFile) -> [URL]
    let handleDrop: ([NSItemProvider]) -> Bool
    let setIsTargeted: (Bool) -> Void

    static func == (lhs: BoxPageContent, rhs: BoxPageContent) -> Bool {
        lhs.files.count == rhs.files.count &&
        lhs.files.first?.id == rhs.files.first?.id &&
        // Animated properties like width/height are removed to prevent re-renders during animations.
        lhs.selectedIDs == rhs.selectedIDs &&
        lhs.columnCount == rhs.columnCount &&
        lhs.accentColor == rhs.accentColor &&
        lhs.isTargeted == rhs.isTargeted
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
        VStack(spacing: 10) {
            Group {
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
        }
        .frame(width: width, height: safeH, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { isTargeted }, set: { setIsTargeted($0) }), perform: handleDrop)
        .overlay(alignment: .bottomTrailing) {
            if !files.isEmpty {
                BoxShareButton(files: files, accentColor: accentColor)
                    .padding([.bottom, .trailing], 16)
            }
        }
    }
}

extension UnifiedNotchContainer {
    // MARK: - Box Page
    var boxPage: some View {
        BoxPageContent(
            files: model.boxFiles,
            selectedIDs: selectedBoxFileIDs,
            width: scaledPanelWidth(for: settings),
            height: max(1, scaledPanelHeight(for: settings) - settings.effectiveNotchHeight - pageTopContentInset),
            columnCount: settings.boxColumns,
            accentColor: settings.accentColor,
            showNames: settings.showBoxFileNames,
            nameSize: settings.boxFileNameSize,
            isTargeted: isBoxDropTargeted,
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
            setIsTargeted: { isBoxDropTargeted = $0 }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }
}
