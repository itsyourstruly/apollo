import SwiftUI
import AppKit

// MARK: - Clip Tile Views

extension UnifiedNotchContainer {
    struct ClipboardPageContent: View, Equatable {
        let chunkedRows: [[ClipboardEntry]]
        let width: CGFloat
        let height: CGFloat
        let columnCount: Int
        let plainTextSize: CGFloat
        let fileLabelSize: CGFloat
        let accentColor: Color
        let highlightedID: UUID?
        let feedbackProgress: CGFloat
        let onTap: (ClipboardEntry) -> Void

        static func == (lhs: ClipboardPageContent, rhs: ClipboardPageContent) -> Bool {
            lhs.columnCount == rhs.columnCount &&
            // Animated properties like width/height are removed to prevent re-renders during animations.
            lhs.accentColor == rhs.accentColor &&
            lhs.highlightedID == rhs.highlightedID &&
            abs(lhs.feedbackProgress - rhs.feedbackProgress) < 0.01 &&
            lhs.chunkedRows.count == rhs.chunkedRows.count &&
            lhs.chunkedRows.first?.first?.id == rhs.chunkedRows.first?.first?.id
        }

        var body: some View {
            VStack(spacing: 0) {
                if chunkedRows.isEmpty {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white.opacity(0.48))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    let horizontalPadding: CGFloat = 8
                    let spacing: CGFloat = 4
                    let totalSpacing = spacing * CGFloat(columnCount - 1)
                    let wd = max(1, width)
                    let tileSize = max(1, (wd - horizontalPadding * 2 - totalSpacing) / CGFloat(columnCount))
                    
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: spacing) {
                            ForEach(chunkedRows, id: \.first?.id) { row in
                                ClipboardRowView(
                                    items: row,
                                    columnCount: columnCount,
                                    tileSize: tileSize,
                                    spacing: spacing,
                                    plainTextSize: plainTextSize,
                                    fileLabelSize: fileLabelSize,
                                    accentColor: accentColor,
                                    highlightedID: highlightedID,
                                    feedbackProgress: feedbackProgress,
                                    onTap: onTap
                                )
                                .equatable()
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                    .frame(width: wd, alignment: .center)
                }
            }
            .frame(width: width, height: height, alignment: .top)
        }
    }

    struct ClipboardRowView: View, Equatable {
        let items: [ClipboardEntry]
        let columnCount: Int
        let tileSize: CGFloat
        let spacing: CGFloat
        let plainTextSize: CGFloat
        let fileLabelSize: CGFloat
        let accentColor: Color
        let highlightedID: UUID?
        let feedbackProgress: CGFloat
        let onTap: (ClipboardEntry) -> Void

        static func == (lhs: ClipboardRowView, rhs: ClipboardRowView) -> Bool {
            guard lhs.items.count == rhs.items.count,
                  lhs.columnCount == rhs.columnCount,
                  // Size properties are derived and animated, so we skip them for Equatable.
                  lhs.items.first?.id == rhs.items.first?.id,
                  lhs.items.last?.id == rhs.items.last?.id else {
                return false
            }

            let lhsHasHighlight = lhs.items.contains { $0.id == lhs.highlightedID }
            let rhsHasHighlight = rhs.items.contains { $0.id == rhs.highlightedID }

            if lhsHasHighlight != rhsHasHighlight { return false }
            if lhsHasHighlight {
                return lhs.highlightedID == rhs.highlightedID &&
                       abs(lhs.feedbackProgress - rhs.feedbackProgress) < 0.01
            }
            return true
        }

        var body: some View {
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    ClipboardTile(
                        item: item,
                        size: tileSize,
                        plainTextSize: plainTextSize,
                        fileLabelSize: fileLabelSize,
                        accentColor: accentColor,
                        isHighlighted: highlightedID == item.id,
                        tapFeedbackProgress: highlightedID == item.id ? feedbackProgress : 0,
                        onTap: onTap
                    )
                    .equatable()
                }
                
                if items.count < columnCount {
                    ForEach(0..<(columnCount - items.count), id: \.self) { _ in
                        Color.clear
                            .frame(width: tileSize, height: tileSize)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// Flat, allocation-light tile. Multi-item clipboard entries render a
    /// single SF Symbol plus a count instead of per-file thumbnails, so a
    /// grouped copy costs the same as a single item.
    struct ClipboardTile: View, Equatable {
        let item: ClipboardEntry
        let size: CGFloat
        let plainTextSize: CGFloat
        let fileLabelSize: CGFloat
        let accentColor: Color
        let isHighlighted: Bool
        let tapFeedbackProgress: CGFloat
        let onTap: (ClipboardEntry) -> Void

        @State private var loadedPreview: NSImage? = nil
        @State private var isLoadingPreview = false

        static func == (lhs: ClipboardTile, rhs: ClipboardTile) -> Bool {
            lhs.item.id == rhs.item.id &&
            lhs.size == rhs.size &&
            lhs.plainTextSize == rhs.plainTextSize &&
            lhs.fileLabelSize == rhs.fileLabelSize &&
            lhs.isHighlighted == rhs.isHighlighted &&
            lhs.tapFeedbackProgress == rhs.tapFeedbackProgress
        }

        var body: some View {
            let isText = item.isTextOnly
            ZStack {
                if isText {
                    Text(item.cachedDisplayTitle ?? (item.normalizedText.isEmpty ? "Text" : item.normalizedText))
                        .font(.system(size: max(8, plainTextSize)))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .frame(width: size, height: size, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(accentColor.opacity(0.8), lineWidth: 1)
                        )
                } else {
                    VStack(spacing: 4) {
                        Group {
                            if let preview = loadedPreview, shouldShowSingleFilePreview {
                                Image(nsImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: size * 0.72, height: size * 0.72)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            } else {
                                Image(systemName: item.cachedGlyph ?? glyph)
                                    .font(.system(size: size * 0.50, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }

                        Text(item.cachedDisplayTitle ?? item.fileSummaryText())
                            .font(.system(size: max(8, fileLabelSize), weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: size, height: size, alignment: .center)
                }

                if isHighlighted {
                    UnifiedNotchContainer.ClipboardTapFeedbackGlyph(
                        color: .green,
                        progress: tapFeedbackProgress
                    )
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .overlay {
                UnifiedNotchContainer.ClipDragSurface(entry: item, onTap: { onTap(item) })
            }
            .onAppear {
                loadPreviewIfNeeded()
            }
            .onChange(of: item.id) { _, _ in
                loadedPreview = nil
                isLoadingPreview = false
                loadPreviewIfNeeded()
            }
            .onDisappear {
                loadedPreview = nil
                isLoadingPreview = false
            }
        }

        private var glyph: String {
            if let cached = item.cachedGlyph { return cached }
            if item.filePaths.count > 1 { return "doc.on.doc" }
            if item.hasFiles { return item.fileSymbol(at: 0) }
            return "doc.text"
        }

        private var previewURL: URL? {
            guard shouldShowSingleFilePreview,
                  let firstPath = item.filePaths.first else {
                return nil
            }
            return URL(fileURLWithPath: firstPath)
        }

        private var shouldShowSingleFilePreview: Bool {
            guard item.filePaths.count == 1,
                  let firstPath = item.filePaths.first else {
                return false
            }
            return !item.isDirectory(firstPath)
        }

        private func loadPreviewIfNeeded() {
            guard shouldShowSingleFilePreview,
                  let url = previewURL else { return }
            let targetSize = max(64, size * 0.9)

            if let cached = BoxIconCache.shared.cachedPreview(for: url, targetSize: targetSize) {
                loadedPreview = cached
                isLoadingPreview = false
                return
            }

            guard !isLoadingPreview else { return }
            isLoadingPreview = true
            BoxIconCache.shared.requestDisplayImage(for: url, targetSize: targetSize) { image in
                isLoadingPreview = false
                loadedPreview = image
            }
        }
    }

    struct ClipboardTapFeedbackGlyph: View {
        let color: Color
        let progress: CGFloat

        var body: some View {
            let p = max(0, min(1, progress))
            ZStack {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color.opacity(0.98))
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: max(1, 18 * p))
                    }
                    .opacity(0.6 + 0.4 * p)
            }
            .frame(width: 30, height: 30)
            .scaleEffect(0.85 + 0.15 * p)
        }
    }

    struct ClipDragSurface: NSViewRepresentable {
        let entry: ClipboardEntry
        let onTap: () -> Void

        func makeNSView(context: Context) -> DragView {
            let view = DragView()
            view.entry = entry
            view.onTap = onTap
            return view
        }

        func updateNSView(_ nsView: DragView, context: Context) {
            nsView.entry = entry
            nsView.onTap = onTap
        }

        final class DragView: NSView, NSDraggingSource {
            var entry: ClipboardEntry?
            var onTap: (() -> Void)?
            private var mouseDownPoint: NSPoint = .zero
            private var mouseDownActive = false
            private var didStartDrag = false

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
                return true
            }

            override func mouseDown(with event: NSEvent) {
                mouseDownPoint = convert(event.locationInWindow, from: nil)
                mouseDownActive = true
                didStartDrag = false
            }

            override func mouseDragged(with event: NSEvent) {
                guard mouseDownActive, !didStartDrag, entry != nil else { return }
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
                onTap?()
            }

            private func beginDrag(with event: NSEvent) {
                guard let entry else { return }
                
                var draggingItems: [NSDraggingItem] = []
                
                if entry.hasFiles {
                    draggingItems = entry.fileURLs.map { url in
                        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                        let icon = NSWorkspace.shared.icon(forFile: url.path)
                        icon.size = NSSize(width: 32, height: 32)
                        draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: icon)
                        return draggingItem
                    }
                } else if entry.hasText {
                    let textWriter = entry.normalizedText as NSString
                    let draggingItem = NSDraggingItem(pasteboardWriter: textWriter)
                    
                    let image = NSImage(size: NSSize(width: 120, height: 32), flipped: false) { rect in
                        let string = textWriter as String
                        let font = NSFont.systemFont(ofSize: 10)
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: NSColor.white
                        ]
                        let size = string.size(withAttributes: attributes)
                        let textRect = NSRect(
                            x: (rect.width - size.width) / 2,
                            y: (rect.height - size.height) / 2,
                            width: size.width,
                            height: size.height
                        )
                        NSColor.black.withAlphaComponent(0.6).setFill()
                        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                        path.fill()
                        string.draw(in: textRect, withAttributes: attributes)
                        return true
                    }
                    draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 120, height: 32), contents: image)
                    draggingItems = [draggingItem]
                }
                
                guard !draggingItems.isEmpty else { return }
                beginDraggingSession(with: draggingItems, event: event, source: self)
            }

            func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
                [.copy]
            }
        }
    }

}
