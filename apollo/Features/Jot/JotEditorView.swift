import SwiftUI
import AppKit

// MARK: - Jot Editor View

extension UnifiedNotchContainer {

    final class JotNSTextView: NSTextView {
        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            if let window = self.window {
                if !window.isKeyWindow {
                    window.makeKey()
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    struct JotTextEditorView: NSViewRepresentable {
        @Binding var text: String
        var isFocused: Binding<Bool>
        let textSize: CGFloat
        let closeSensitivity: CGFloat
        let onOverscrollProgressLegacy: (CGFloat, Bool) -> Void
        let onBottomOverscroll: () -> Void
        let onScrollMetricsChange: (CGFloat, CGFloat, CGFloat) -> Void

        init(text: Binding<String>, isFocused: Binding<Bool>, textSize: CGFloat, closeSensitivity: CGFloat, onOverscrollProgress: @escaping (CGFloat, Bool) -> Void, onBottomOverscroll: @escaping () -> Void, onScrollMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
            self._text = text
            self.isFocused = isFocused
            self.textSize = textSize
            self.closeSensitivity = closeSensitivity
            self.onOverscrollProgressLegacy = onOverscrollProgress
            self.onBottomOverscroll = onBottomOverscroll
            self.onScrollMetricsChange = onScrollMetricsChange
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, isFocused: isFocused, onScrollMetricsChange: onScrollMetricsChange)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = OverscrollDismissScrollView()
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
            scrollView.onOverscrollProgress = onOverscrollProgressLegacy
            scrollView.onBottomOverscroll = onBottomOverscroll
            scrollView.closeSensitivity = closeSensitivity

            let textView = JotNSTextView()
            textView.delegate = context.coordinator
            textView.string = text
            textView.drawsBackground = false
            textView.backgroundColor = .clear
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.isEditable = true
            textView.isSelectable = true
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.textContainerInset = NSSize(width: 0, height: 6)
            textView.textColor = .white
            textView.insertionPointColor = .white
            textView.font = .systemFont(ofSize: max(11, textSize))
            
            // Set minSize to match scroll view viewport height so the entire area is clickable from the start
            textView.minSize = NSSize(width: 0.0, height: scrollView.contentSize.height)

            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            }

            scrollView.documentView = textView
            context.coordinator.attach(textView: textView, scrollView: scrollView)
            DispatchQueue.main.async {
                context.coordinator.updateMetrics()
            }
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            if let overscrollView = scrollView as? OverscrollDismissScrollView {
                overscrollView.onOverscrollProgress = onOverscrollProgressLegacy
                overscrollView.onBottomOverscroll = onBottomOverscroll
                overscrollView.closeSensitivity = closeSensitivity
            }

            let resolvedSize = max(11, textSize)
            if textView.font?.pointSize != resolvedSize {
                textView.font = .systemFont(ofSize: resolvedSize)
            }

            if textView.string != text {
                let selection = textView.selectedRange()
                textView.string = text
                textView.selectedRange = selection
            }

            if let textContainer = textView.textContainer {
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            }

            // Keep minSize in sync with the viewport height so clicks anywhere in the scroll area hit the text view
            let viewportHeight = scrollView.contentSize.height
            if textView.minSize.height != viewportHeight {
                textView.minSize = NSSize(width: 0.0, height: viewportHeight)
            }

            let currentFocus = isFocused.wrappedValue
            if currentFocus {
                if let window = scrollView.window {
                    if window.firstResponder !== textView {
                        window.makeFirstResponder(textView)
                    }
                    if !window.isKeyWindow {
                        window.makeKey()
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                if let window = scrollView.window, window.firstResponder === textView {
                    window.makeFirstResponder(nil)
                }
            }

            DispatchQueue.main.async {
                context.coordinator.updateMetrics()
            }
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            @Binding var text: String
            var isFocused: Binding<Bool>
            var onScrollMetricsChange: (CGFloat, CGFloat, CGFloat) -> Void
            weak var textView: NSTextView?
            weak var scrollView: NSScrollView?

            init(text: Binding<String>, isFocused: Binding<Bool>, onScrollMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
                _text = text
                self.isFocused = isFocused
                self.onScrollMetricsChange = onScrollMetricsChange
            }

            func attach(textView: NSTextView, scrollView: NSScrollView) {
                self.textView = textView
                self.scrollView = scrollView
                scrollView.contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange(_:)), name: NSView.frameDidChangeNotification, object: textView)
                scrollView.documentView?.postsFrameChangedNotifications = true
            }

            deinit {
                NotificationCenter.default.removeObserver(self)
            }

            func textDidChange(_ notification: Notification) {
                text = textView?.string ?? text
                updateMetrics()
            }

            func textDidBeginEditing(_ notification: Notification) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if !self.isFocused.wrappedValue {
                        self.isFocused.wrappedValue = true
                    }
                }
            }

            func textDidEndEditing(_ notification: Notification) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.isFocused.wrappedValue {
                        self.isFocused.wrappedValue = false
                    }
                }
            }

            @objc private func boundsDidChange(_ notification: Notification) {
                updateMetrics()
            }

            @objc private func frameDidChange(_ notification: Notification) {
                updateMetrics()
            }

            func updateMetrics() {
                guard let textView, let scrollView else { return }
                let visibleHeight = scrollView.contentView.bounds.height
                let visibleOriginY = scrollView.contentView.bounds.origin.y
                let layoutHeight: CGFloat
                if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                    layoutHeight = layoutManager.usedRect(for: textContainer).height + (textView.textContainerInset.height * 2)
                } else {
                    layoutHeight = textView.bounds.height
                }
                let contentHeight = max(visibleHeight, ceil(layoutHeight))
                onScrollMetricsChange(visibleOriginY, contentHeight, visibleHeight)
            }
        }
    }

}
