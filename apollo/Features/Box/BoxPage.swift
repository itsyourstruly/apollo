import SwiftUI
import AppKit

// MARK: - Reintegrated Box
import UniformTypeIdentifiers

extension UnifiedNotchContainer {
    // MARK: - Box Page
    var boxPage: some View {
        boxPageWithWidth(scaledPanelWidth(for: settings), height: scaledPanelHeight(for: settings) - settings.effectiveNotchHeight)
    }

    private func boxPageWithWidth(_ width: CGFloat, height: CGFloat) -> some View {
        let safeW = max(1, width)
        let safeH = max(1, height)
        return VStack(spacing: 10) {
            Group {
                if model.boxFiles.isEmpty {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: min(safeW, safeH) * 0.22, weight: .semibold))
                        .foregroundColor(.brown.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    let columnCount = max(1, settings.boxColumns)
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
                    let maxSize = max(1, min((safeW - 16) / CGFloat(columnCount), safeH * 0.38))
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(model.boxFiles) { file in
                                boxItemView(file: file, maxSize: maxSize)
                            }
                        }
                        .frame(width: width, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .padding(.top, pageTopContentInset)
        .frame(width: width, height: max(1, height - pageTopContentInset), alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $isBoxDropTargeted, perform: handleBoxDrop)
    }

    private func boxItemView(file: BoxFile, maxSize: CGFloat) -> some View {
        return SafeCachedBoxItemView(
            file: file,
            maxSize: maxSize,
            isSelected: selectedBoxFileIDs.contains(file.id),
            accentColor: settings.accentColor,
            showBoxFileNames: settings.showBoxFileNames,
            fileNameSize: settings.boxFileNameSize,
            onRemove: {
                DispatchQueue.main.async {
                    withAnimation {
                        model.boxFiles.removeAll { $0.id == file.id }
                        selectedBoxFileIDs.remove(file.id)
                    }
                }
            },
            urlsForDrag: {
                let selectedURLs = model.boxFiles.compactMap { selectedBoxFileIDs.contains($0.id) ? $0.url : nil }
                return selectedURLs.isEmpty ? [file.url] : selectedURLs
            },
            selectForDrag: {
                if !selectedBoxFileIDs.contains(file.id) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        _ = selectedBoxFileIDs.insert(file.id)
                    }
                }
            },
            toggleSelection: {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    if selectedBoxFileIDs.contains(file.id) {
                        selectedBoxFileIDs.remove(file.id)
                    } else {
                        selectedBoxFileIDs.insert(file.id)
                    }
                }
            }
        )
    }

    func fittedBoxPreviewSize(for image: NSImage, maxDimension: CGFloat) -> CGSize {
        let maxDim = max(1, maxDimension)
        let rawWidth = max(1, image.size.width)
        let rawHeight = max(1, image.size.height)
        let scale = maxDim / max(rawWidth, rawHeight)
        return CGSize(width: rawWidth * scale, height: rawHeight * scale)
    }

    func requestBoxPreviewIfNeeded(for url: URL, targetSize: CGFloat) {
        guard model.isExpanded, model.currentPage == IslandPage.box.rawValue else { return }
        guard visibleBoxPreviewURLs.contains(url) else { return }
        guard BoxIconCache.shared.shouldAttemptPreview(for: url) else { return }
        if boxPreviewImages[url] != nil {
            touchBoxPreviewURL(url)
            return
        }
        guard !boxPreviewLoadingURLs.contains(url) else { return }

        let requestSize = quantizedPreviewTargetSize(targetSize)
        boxPreviewLoadingURLs.insert(url)

        BoxIconCache.shared.requestDisplayImage(for: url, targetSize: requestSize) { image in
            boxPreviewLoadingURLs.remove(url)
            guard model.isExpanded, model.currentPage == IslandPage.box.rawValue else { return }
            guard model.boxFiles.contains(where: { $0.url == url }) else { return }
            boxPreviewImages[url] = image
            touchBoxPreviewURL(url)
        }
    }

    private func quantizedPreviewTargetSize(_ targetSize: CGFloat) -> CGFloat {
        let clamped = max(64, min(192, targetSize))
        return ceil(clamped / 24) * 24
    }

    func pruneBoxPreviewState(keeping urls: [URL]) {
        let keep = Set(urls)
        visibleBoxPreviewURLs = visibleBoxPreviewURLs.intersection(keep)
        boxPreviewImages = boxPreviewImages.filter { keep.contains($0.key) }
        boxPreviewLoadingURLs = Set(boxPreviewLoadingURLs.filter { keep.contains($0) })
        boxPreviewLRU = boxPreviewLRU.filter { keep.contains($0) }
        scheduleSharedPreviewTrim()
    }

}
