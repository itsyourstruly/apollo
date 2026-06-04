import SwiftUI
import AppKit

// MARK: - Reintegrated Clip

extension UnifiedNotchContainer {
    // MARK: - Clipboard Page
    var clipboardPage: some View {
        clipboardPageWithWidth(scaledPanelWidth(for: settings), height: scaledPanelHeight(for: settings) - settings.effectiveNotchHeight)
    }

    private func clipboardPageWithWidth(_ width: CGFloat, height: CGFloat) -> some View {
        ClipboardPageContent(
            chunkedRows: model.chunkedClipboardRows,
            width: width,
            height: max(1, height - pageTopContentInset),
            columnCount: settings.clipboardColumns,
            plainTextSize: settings.clipTextSize,
            fileLabelSize: settings.clipFileLabelSize,
            accentColor: Color(nsColor: settings.accentColor),
            highlightedID: highlightedClipboardID,
            feedbackProgress: clipboardTapFeedbackProgress,
            onTap: copyClipboard
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }
    @ViewBuilder
    private func clipboardCellContent(_ item: ClipboardEntry) -> some View {
        if item.hasFiles {
            let urls = item.fileURLs
            if urls.count == 1, let fileURL = urls.first {
                clipboardSingleFileContent(fileURL)
            } else {
                clipboardMultiFileContent(item)
            }
        } else {
            Text(item.normalizedText)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clipboardSingleFileContent(_ fileURL: URL) -> some View {
        let preview = clipboardFilePreviews[fileURL.path]
        let fileName = fileURL.lastPathComponent

        return VStack(alignment: .leading, spacing: 8) {
            clipboardSingleVisual(for: fileURL, preview: preview)
            .onAppear {
                requestClipboardFilePreviewIfNeeded(for: fileURL)
            }

            Text(fileName)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func clipboardMultiFileContent(_ item: ClipboardEntry) -> some View {
        let summary = clipboardMultiItemSummary(for: item.fileURLs)
        let previewURLs = Array(item.fileURLs.prefix(4))
        let folderNamesLine = clipboardJoinedFolderNames(for: item.fileURLs)
        let showFolderNames = !folderNamesLine.isEmpty
        let compactFolderStyle = summary == "Multiple folders"
        return VStack(alignment: .leading, spacing: compactFolderStyle ? 4 : 8) {
            clipboardMultiVisualGrid(urls: previewURLs)
                .onAppear {
                    for url in previewURLs {
                        requestClipboardFilePreviewIfNeeded(for: url)
                    }
                }

            Text(summary)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            if showFolderNames {
                Text(folderNamesLine)
                    .font(compactFolderStyle ? .system(size: 10, weight: .regular) : .caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func clipboardJoinedFolderNames(for urls: [URL]) -> String {
        let names = urls.filter(isDirectoryURL(_:)).map { url in
            let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? url.path : name
        }
        return names.joined(separator: ", ")
    }

    @ViewBuilder
    private func clipboardSingleVisual(for url: URL, preview: NSImage?) -> some View {
        if let preview {
            let fitted = fittedBoxPreviewSize(for: preview, maxDimension: 84)
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: fitted.width, height: fitted.height)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Image(systemName: clipboardFileSymbol(for: url))
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
        }
    }

    private func clipboardMultiVisualGrid(urls: [URL]) -> some View {
        let columns = [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 4),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 4)
        ]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                if index < urls.count {
                    clipboardMultiVisualCell(url: urls[index])
                } else {
                    Color.clear
                        .frame(height: 34)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func clipboardMultiVisualCell(url: URL) -> some View {
        if let preview = clipboardFilePreviews[url.path] {
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: clipboardFileSymbol(for: url))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        }
    }

    private func clipboardMultiItemSummary(for urls: [URL]) -> String {
        var folderCount = 0
        var fileCount = 0
        for url in urls {
            if isDirectoryURL(url) {
                folderCount += 1
            } else {
                fileCount += 1
            }
        }

        if folderCount > 0 && fileCount > 0 {
            return "Multiple folders and files"
        }
        if folderCount > 1 {
            return "Multiple folders"
        }
        if fileCount > 1 {
            return "Multiple files"
        }
        if folderCount == 1 {
            return "Folder"
        }
        if fileCount == 1 {
            return "File"
        }
        return "Multiple items"
    }

    private func clipboardTypeDescription(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey])
        if let desc = values?.localizedTypeDescription, !desc.isEmpty {
            return desc
        }
        let ext = url.pathExtension
        return ext.isEmpty ? "File" : ext.uppercased()
    }

    private func clipboardFileSymbol(for url: URL) -> String {
        if isDirectoryURL(url) {
            return "folder"
        }
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif":
            return "photo"
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "webm", "mpeg", "mpg", "3gp", "ts", "m2ts":
            return "video"
        case "pdf":
            return "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox"
        default:
            return "doc"
        }
    }

    private func isDirectoryURL(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func requestClipboardFilePreviewIfNeeded(for url: URL) {
        guard BoxIconCache.shared.shouldAttemptPreview(for: url) else { return }
        guard clipboardFilePreviews[url.path] == nil else { return }
        guard !clipboardFilePreviewLoadingPaths.contains(url.path) else { return }

        clipboardFilePreviewLoadingPaths.insert(url.path)
        DispatchQueue.global(qos: .utility).async {
            let preview = BoxIconCache.shared.displayImage(for: url, targetSize: 180)
            DispatchQueue.main.async {
                clipboardFilePreviewLoadingPaths.remove(url.path)
                clipboardFilePreviews[url.path] = preview
            }
        }
    }

    func pruneClipboardPreviewState(keeping items: [ClipboardEntry]) {
        let keepPaths = Set(items.flatMap { $0.filePaths })
        clipboardFilePreviews = clipboardFilePreviews.filter { keepPaths.contains($0.key) }
        clipboardFilePreviewLoadingPaths = Set(clipboardFilePreviewLoadingPaths.filter { keepPaths.contains($0) })
    }
}
