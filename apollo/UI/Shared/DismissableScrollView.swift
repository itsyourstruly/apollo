import SwiftUI
import AppKit

// MARK: - Shared Dismissable Scroll View

extension UnifiedNotchContainer {
    final class OverscrollDismissScrollView: NSScrollView {
        var onBottomOverscroll: (() -> Void)?
        var onOverscrollProgress: ((CGFloat, Bool) -> Void)?
        var onMetricsChange: ((CGFloat, CGFloat, CGFloat) -> Void)?
        var closeSensitivity: CGFloat = 1.0
        private var accumulatedOverscroll: CGFloat = 0
        private var didTriggerClose = false
        private var lastOverscrollProgress: CGFloat = 0
        private let baseTriggerThreshold: CGFloat = 110
        private let bottomTolerance: CGFloat = 20
        private var observationTokens: [NSObjectProtocol] = []
        private var lastReportedScrollOffset: CGFloat = .nan
        private var lastReportedContentHeight: CGFloat = .nan
        private var lastReportedViewportHeight: CGFloat = .nan

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureMetricsObservationIfNeeded()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureMetricsObservationIfNeeded()
        }

        deinit {
            observationTokens.forEach(NotificationCenter.default.removeObserver)
        }

        private func configureMetricsObservationIfNeeded() {
            guard observationTokens.isEmpty else { return }
            contentView.postsBoundsChangedNotifications = true
            documentView?.postsFrameChangedNotifications = true

            let center = NotificationCenter.default
            observationTokens.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
                self?.reportMetricsIfPossible()
            })
            if let documentView {
                observationTokens.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: documentView, queue: .main) { [weak self] _ in
                    self?.reportMetricsIfPossible()
                })
            }

            reportMetricsIfPossible()
        }

        func reportMetricsIfPossible() {
            let viewportHeight = contentView.bounds.height
            let scrollOffset = contentView.bounds.origin.y
            let contentHeight = documentView?.frame.height ?? viewportHeight
            if !lastReportedScrollOffset.isNaN,
               abs(lastReportedScrollOffset - scrollOffset) < 0.5,
               abs(lastReportedContentHeight - contentHeight) < 0.5,
               abs(lastReportedViewportHeight - viewportHeight) < 0.5 {
                return
            }
            lastReportedScrollOffset = scrollOffset
            lastReportedContentHeight = contentHeight
            lastReportedViewportHeight = viewportHeight
            self.onMetricsChange?(scrollOffset, contentHeight, viewportHeight)
        }

        override func scrollWheel(with event: NSEvent) {
            guard let documentView else {
                super.scrollWheel(with: event)
                return
            }

            if didTriggerClose {
                if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                    didTriggerClose = false
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                }
                return
            }

            let fingerDeltaY = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            let viewportHeight = contentView.bounds.height
            let contentHeight = documentView.bounds.height
            let atBottom = contentHeight <= viewportHeight + bottomTolerance || contentView.bounds.maxY >= contentHeight - bottomTolerance
            let triggerThreshold = baseTriggerThreshold / max(0.2, closeSensitivity)

            if fingerDeltaY > 0 && atBottom {
                accumulatedOverscroll += fingerDeltaY
                let progress = min(1, accumulatedOverscroll / max(1, triggerThreshold))
                lastOverscrollProgress = progress
                self.onOverscrollProgress?(progress, false)
                if progress >= 1 {
                    accumulatedOverscroll = 0
                    didTriggerClose = true
                    lastOverscrollProgress = 1
                    self.onOverscrollProgress?(1, true)
                    self.onBottomOverscroll?()
                    return
                }
            } else {
                if accumulatedOverscroll > 0 {
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                } else if lastOverscrollProgress > 0 {
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                }
            }

            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .began || event.momentumPhase == .ended {
                if accumulatedOverscroll > 0 {
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                } else if lastOverscrollProgress > 0 {
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                }
            }

            super.scrollWheel(with: event)
            reportMetricsIfPossible()
        }
    }

    struct DismissableScrollView<Content: View> : NSViewRepresentable {
        let closeSensitivity: CGFloat
        let onOverscrollProgress: (CGFloat, Bool) -> Void
        let onBottomOverscroll: () -> Void
        let onMetricsChange: (CGFloat, CGFloat, CGFloat) -> Void
        let content: Content

        init(
            closeSensitivity: CGFloat,
            onOverscrollProgress: @escaping (CGFloat, Bool) -> Void,
            onBottomOverscroll: @escaping () -> Void,
            onMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
            @ViewBuilder content: () -> Content
        ) {
            self.closeSensitivity = closeSensitivity
            self.onOverscrollProgress = onOverscrollProgress
            self.onBottomOverscroll = onBottomOverscroll
            self.onMetricsChange = onMetricsChange
            self.content = content()
        }

        func makeNSView(context: Context) -> OverscrollDismissScrollView {
            let scrollView = OverscrollDismissScrollView()
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
            scrollView.usesPredominantAxisScrolling = true
            scrollView.onBottomOverscroll = onBottomOverscroll
            scrollView.onOverscrollProgress = onOverscrollProgress
            scrollView.onMetricsChange = onMetricsChange
            scrollView.closeSensitivity = closeSensitivity

            let hostingView = NSHostingView(rootView: content)
            hostingView.translatesAutoresizingMaskIntoConstraints = true
            hostingView.autoresizingMask = [.width]
            scrollView.documentView = hostingView
            scheduleHostingViewFrameUpdate(hostingView, in: scrollView)

            return scrollView
        }

        func updateNSView(_ nsView: OverscrollDismissScrollView, context: Context) {
            nsView.closeSensitivity = closeSensitivity
            nsView.onBottomOverscroll = onBottomOverscroll
            nsView.onOverscrollProgress = onOverscrollProgress
            nsView.onMetricsChange = onMetricsChange
            if let hostingView = nsView.documentView as? NSHostingView<Content> {
                hostingView.rootView = content
                scheduleHostingViewFrameUpdate(hostingView, in: nsView)
            }
        }

        private func scheduleHostingViewFrameUpdate(_ hostingView: NSHostingView<Content>, in scrollView: NSScrollView) {
            DispatchQueue.main.async {
                let hostingWidth = safeDimension(scrollView.contentSize.width, fallback: 1)
                let intrinsicHeight = hostingView.intrinsicContentSize.height
                let hostingHeight = safeDimension(intrinsicHeight, fallback: max(1, scrollView.contentSize.height))
                let currentSize = hostingView.frame.size
                if abs(currentSize.width - hostingWidth) < 0.5,
                   abs(currentSize.height - hostingHeight) < 0.5 {
                    return
                }
                hostingView.frame = NSRect(x: 0, y: 0, width: hostingWidth, height: hostingHeight)
            }
        }
    }


}
