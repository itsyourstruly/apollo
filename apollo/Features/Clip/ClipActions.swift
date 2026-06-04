import SwiftUI
import AppKit

// MARK: - Clip Actions

extension UnifiedNotchContainer {
    func copyClipboard(_ item: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        if item.hasText {
            NSPasteboard.general.setString(item.normalizedText, forType: .string)
        }
        if item.hasFiles {
            _ = NSPasteboard.general.writeObjects(item.fileURLs as [NSURL])
        }
        if settings.clipboardActionOption == .paste, let delegate = NSApp.delegate as? AppDelegate {
            delegate.postPasteCommand()
        }
        highlightedClipboardID = item.id
        clipboardTapFeedbackProgress = 0

        withAnimation(.easeOut(duration: 0.16)) {
            clipboardTapFeedbackProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            guard highlightedClipboardID == item.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                clipboardTapFeedbackProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
                if highlightedClipboardID == item.id {
                    highlightedClipboardID = nil
                }
            }
        }
    }

    func clearClipboardHistory() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.clearClipboardHistory()
        } else {
            NSPasteboard.general.clearContents()
            model.clipboardItems.removeAll()
            model.chunkedClipboardRows.removeAll()
            persistClipboardHistory(model.clipboardItems)
        }
        highlightedClipboardID = nil
        clipboardTapFeedbackProgress = 0
    }

}
