import SwiftUI
import AppKit

// MARK: - Box Toast Views

extension UnifiedNotchContainer {
    struct ObservedFileToastView: View {
        let toast: ObservedFileToast
        let progress: CGFloat
        let onClose: () -> Void
        let baseWidth: CGFloat
        let baseHeight: CGFloat
        let expandedHeight: CGFloat
        let backgroundColor: Color
        let cornerRadius: CGFloat
        @State private var isSelected = false
        @State private var contentHeight: CGFloat = 0

        private struct ContentHeightKey: PreferenceKey {
            static var defaultValue: CGFloat = 0
            static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
                value = max(value, nextValue())
            }
        }

        private var locationName: String {
            let name = toast.folderURL.lastPathComponent
            return name.isEmpty ? "location" : name
        }

        var body: some View {
            let clampedProgress = progress.isFinite ? max(0, min(1, progress)) : 0
            let easedProgress = clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
            let measuredHeight = contentHeight > 0 ? contentHeight : expandedHeight
            let targetHeight = min(max(baseHeight, measuredHeight), expandedHeight)
            let contentScale = measuredHeight > expandedHeight ? expandedHeight / measuredHeight : 1
            let panelHeight = baseHeight + (targetHeight - baseHeight) * easedProgress
            let icon = NSImage(contentsOf: toast.fileURL) ?? NSWorkspace.shared.icon(forFile: toast.fileURL.path)
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 10) {
                    VStack(spacing: 8) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(toast.fileURL.lastPathComponent)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .overlay(
                        ToastDragSurface(
                            url: toast.fileURL,
                            onClick: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    isSelected.toggle()
                                }
                            },
                            onDoubleClick: {
                                NSWorkspace.shared.open(toast.fileURL)
                                onClose()
                            }
                        )
                    )

                    HStack {
                        Text("in \(locationName)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                            .onTapGesture {
                                NSWorkspace.shared.activateFileViewerSelecting([toast.fileURL])
                                onClose()
                            }
                        Spacer()
                    }
                }
                .padding(12)
                .scaleEffect(contentScale, anchor: .top)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .frame(width: baseWidth, height: panelHeight, alignment: .top)
            .background(backgroundColor)
            .clipShape(BottomRoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
            .onPreferenceChange(ContentHeightKey.self) { value in
                if value.isFinite && contentHeight != value {
                    contentHeight = value
                }
            }
        }
    }

    private struct ToastDragSurface: NSViewRepresentable {
        let url: URL
        let onClick: () -> Void
        let onDoubleClick: () -> Void

        func makeNSView(context: Context) -> DragSurfaceView {
            let view = DragSurfaceView()
            view.url = url
            view.onClick = onClick
            view.onDoubleClick = onDoubleClick
            return view
        }

        func updateNSView(_ nsView: DragSurfaceView, context: Context) {
            nsView.url = url
            nsView.onClick = onClick
            nsView.onDoubleClick = onDoubleClick
        }

        final class DragSurfaceView: NSView, NSDraggingSource {
            var url: URL?
            var onClick: (() -> Void)?
            var onDoubleClick: (() -> Void)?
            private var mouseDownPoint: NSPoint = .zero
            private var didStartDrag = false

            override func mouseDown(with event: NSEvent) {
                mouseDownPoint = convert(event.locationInWindow, from: nil)
                didStartDrag = false
            }

            override func mouseDragged(with event: NSEvent) {
                guard !didStartDrag, let url else { return }
                let currentPoint = convert(event.locationInWindow, from: nil)
                let deltaX = currentPoint.x - mouseDownPoint.x
                let deltaY = currentPoint.y - mouseDownPoint.y
                if hypot(deltaX, deltaY) > 3 {
                    beginDrag(url: url, event: event)
                    didStartDrag = true
                }
            }

            override func mouseUp(with event: NSEvent) {
                guard !didStartDrag else { return }
                if event.clickCount > 1 {
                    onDoubleClick?()
                } else {
                    onClick?()
                }
            }

            private func beginDrag(url: URL, event: NSEvent) {
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 48, height: 48)
                draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48), contents: icon)
                beginDraggingSession(with: [draggingItem], event: event, source: self)
            }

            func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
                [.copy, .move]
            }
        }
    }

}
