import SwiftUI
import AppKit

// MARK: - Box Item Views

extension UnifiedNotchContainer {
    struct BoxPreviewPlaceholder: View {
        let isLoading: Bool
        let symbol: String

        var body: some View {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Image(systemName: symbol)
                        .font(.system(size: max(18, side * 0.56), weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.7))
                            .scaleEffect(0.75)
                            .offset(y: side * 0.28)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
    struct HoverRemoveButton: View {
        var action: () -> Void
        var body: some View {
            Button {
                action()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .font(.caption)
                    .padding(6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    struct BoxSelectableDragSurface: NSViewRepresentable {
        let file: BoxFile
        let isSelected: Bool
        let urlsForDrag: () -> [URL]
        let selectForDrag: () -> Void
        let toggleSelection: () -> Void
        let removeHotSpotSize: CGFloat

        func makeNSView(context: Context) -> DragView {
            let view = DragView()
            view.urlsForDrag = urlsForDrag
            view.selectForDrag = selectForDrag
            view.toggleSelection = toggleSelection
            view.removeHotSpotSize = removeHotSpotSize
            view.isSelected = isSelected
            view.fileURL = file.url
            return view
        }

        func updateNSView(_ nsView: DragView, context: Context) {
            nsView.urlsForDrag = urlsForDrag
            nsView.selectForDrag = selectForDrag
            nsView.toggleSelection = toggleSelection
            nsView.removeHotSpotSize = removeHotSpotSize
            nsView.isSelected = isSelected
            nsView.fileURL = file.url
        }

        final class DragView: NSView, NSDraggingSource {
            var urlsForDrag: (() -> [URL])?
            var selectForDrag: (() -> Void)?
            var toggleSelection: (() -> Void)?
            var removeHotSpotSize: CGFloat = 22
            var isSelected: Bool = false
            var fileURL: URL?
            private var mouseDownPoint: NSPoint = .zero
            private var mouseDownActive = false
            private var didStartDrag = false
            private var didSelectOnMouseDown = false

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                self.setAccessibilityElement(false)
                self.setAccessibilityRole(.none)
            }

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
                return true
            }

            override func hitTest(_ point: NSPoint) -> NSView? {
                let removeRect = NSRect(x: 0, y: bounds.height - removeHotSpotSize, width: removeHotSpotSize, height: removeHotSpotSize)
                if removeRect.contains(point) {
                    return nil
                }
                return self
            }

            override func mouseDown(with event: NSEvent) {
                mouseDownPoint = convert(event.locationInWindow, from: nil)
                mouseDownActive = true
                didStartDrag = false
                if !isSelected {
                    selectForDrag?()
                    didSelectOnMouseDown = true
                } else {
                    didSelectOnMouseDown = false
                }
            }

            override func mouseDragged(with event: NSEvent) {
                guard mouseDownActive, !didStartDrag else { return }
                let currentPoint = convert(event.locationInWindow, from: nil)
                let deltaX = currentPoint.x - mouseDownPoint.x
                let deltaY = currentPoint.y - mouseDownPoint.y
                if hypot(deltaX, deltaY) > 12 {
                    beginDrag(with: event)
                    didStartDrag = true
                }
            }

            override func mouseUp(with event: NSEvent) {
                defer {
                    mouseDownActive = false
                    didStartDrag = false
                }

                guard mouseDownActive, !didStartDrag else { return }
                if event.clickCount == 2, let url = fileURL {
                    NSWorkspace.shared.open(url)
                    return
                }
                if didSelectOnMouseDown { return }
                toggleSelection?()
            }

            private func beginDrag(with event: NSEvent) {
                guard let urls = urlsForDrag?(), !urls.isEmpty else { return }

                let draggingItems: [NSDraggingItem] = urls.map { url in
                    let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                    let icon = BoxIconCache.shared.icon(for: url)
                    icon.size = NSSize(width: 32, height: 32)
                    draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: icon)
                    return draggingItem
                }

                beginDraggingSession(with: draggingItems, event: event, source: self)
            }

            func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
                [.copy, .move]
            }
        }
    }

}

struct SafeCachedBoxItemView: View {
    let file: BoxFile
    let maxSize: CGFloat
    let isSelected: Bool
    let accentColor: NSColor
    let showBoxFileNames: Bool
    let fileNameSize: CGFloat
    let onRemove: () -> Void
    let urlsForDrag: () -> [URL]
    let selectForDrag: () -> Void
    let toggleSelection: () -> Void

    @State private var loadedImage: NSImage? = nil
    @State private var isLoading = false
    @State private var imageRequestID: UUID?
    @State private var imageLoadTask: Task<Void, Never>?

    var body: some View {
        let size = max(1, maxSize)
        let previewSize = loadedImage.map { fittedSize(for: $0, maxDimension: size) } ?? CGSize(width: size, height: size)

        ZStack(alignment: .topLeading) {
            VStack(spacing: 6) {
                Group {
                    if let image = loadedImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        UnifiedNotchContainer.BoxPreviewPlaceholder(isLoading: isLoading, symbol: placeholderSymbol)
                    }
                }
                .frame(width: previewSize.width, height: previewSize.height)

                if showBoxFileNames {
                    VStack(spacing: 4) {
                        Text(file.url.lastPathComponent)
                            .font(.system(size: max(9, fileNameSize)))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)



                        if isSelected {
                            Capsule()
                                .fill(Color(accentColor))
                                .frame(width: max(12, previewSize.width * 0.7), height: 2)
                        }
                    }
                    .frame(width: previewSize.width + 6)
                }
            }

            UnifiedNotchContainer.HoverRemoveButton {
                onRemove()
            }

            UnifiedNotchContainer.BoxSelectableDragSurface(
                file: file,
                isSelected: isSelected,
                urlsForDrag: urlsForDrag,
                selectForDrag: selectForDrag,
                toggleSelection: toggleSelection,
                removeHotSpotSize: 22
            )
        }
        .contextMenu {
            if !AppSettings.shared.sharingTargetApps.isEmpty {
                ForEach(AppSettings.shared.sharingTargetApps, id: \.self) { appPath in
                    let appURL = URL(fileURLWithPath: appPath)
                    let appName = appURL.deletingPathExtension().lastPathComponent
                    Button {
                        NSWorkspace.shared.open([file.url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    } label: {
                        Text("Open with \(appName)")
                    }
                }
                Divider()
            }
            
            Button("AirDrop") {
                if let service = NSSharingService(named: .sendViaAirDrop) {
                    service.perform(withItems: [file.url])
                }
            }
            
            Button("Messages") {
                if let service = NSSharingService(named: .composeMessage) {
                    service.perform(withItems: [file.url])
                }
            }
            
            Button("Mail") {
                if let service = NSSharingService(named: .composeEmail) {
                    service.perform(withItems: [file.url])
                }
            }

            Button("Open") {
                NSWorkspace.shared.open(file.url)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
            }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.lastPathComponent, forType: .string)
            }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
            Button("Remove", role: .destructive) {
                onRemove()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: file.url) { _, _ in
            reloadImage()
        }
        .onDisappear {
            cancelImageLoad()
            loadedImage = nil // Instantly free RAM when scrolled out of view
        }
        .frame(
            width: previewSize.width + 8,
            height: showBoxFileNames ? previewSize.height + 36 : previewSize.height,
            alignment: .center
        )
    }

    private func cancelImageLoad() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        if let id = imageRequestID {
            BoxIconCache.shared.cancelRequest(id)
            imageRequestID = nil
        }
    }

    private func reloadImage() {
        cancelImageLoad()
        loadedImage = nil
        isLoading = false
        loadImage()
    }

    private func loadImage() {
        let targetSize = max(1, maxSize)
        if let cached = BoxIconCache.shared.cachedPreview(for: file.url, targetSize: targetSize) {
            self.loadedImage = cached
            self.isLoading = false
            return
        }
        guard BoxIconCache.shared.shouldAttemptPreview(for: file.url) else {
            self.isLoading = false
            return
        }
        
        imageLoadTask?.cancel()
        imageLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self.isLoading = true
            self.imageRequestID = BoxIconCache.shared.requestDisplayImage(for: file.url, targetSize: targetSize) { image in
                if !Task.isCancelled {
                    self.loadedImage = image
                    self.isLoading = false
                }
            }
        }
    }

    private func fittedSize(for image: NSImage, maxDimension: CGFloat) -> CGSize {
        let maxDim = max(1, maxDimension)
        let rawWidth = max(1, image.size.width)
        let rawHeight = max(1, image.size.height)
        let scale = maxDim / max(rawWidth, rawHeight)
        return CGSize(width: rawWidth * scale, height: rawHeight * scale)
    }

    private var placeholderSymbol: String {
        if isDirectory(file.url) {
            return "folder.fill"
        }

        let ext = file.url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "bmp", "webp", "svg":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return "archivebox.fill"
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            return "waveform"
        case "mp4", "mov", "mkv", "avi", "webm":
            return "film.fill"
        case "swift", "js", "ts", "tsx", "jsx", "py", "java", "c", "cpp", "h", "hpp", "go", "rs", "rb", "php", "json", "yaml", "yml", "xml", "html", "css", "scss", "md", "txt":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDir = values.isDirectory {
            return isDir
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }
}

fileprivate struct BoxAppIconView: View {
    let appPath: String
    let size: CGFloat

    var body: some View {
        if FileManager.default.fileExists(atPath: appPath) {
            if let icon = AppIconCache.shared.icon(forPath: appPath) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundColor(.gray.opacity(0.5))
        }
    }
}
