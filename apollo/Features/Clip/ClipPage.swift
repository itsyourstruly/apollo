import SwiftUI
import AppKit

// MARK: - Reintegrated Clip

extension UnifiedNotchContainer {
    // MARK: - Clipboard Page
    var clipboardPage: some View {
        ClipboardPageContent(
            chunkedRows: model.chunkedClipboardRows,
            width: scaledPanelWidth(for: settings),
            height: max(1, scaledPanelHeight(for: settings) - settings.effectiveNotchHeight - pageTopContentInset),
            columnCount: settings.clipboardColumns,
            plainTextSize: settings.clipTextSize,
            fileLabelSize: settings.clipFileLabelSize,
            accentColor: Color(settings.accentColor),
            highlightedID: highlightedClipboardID,
            feedbackProgress: clipboardTapFeedbackProgress,
            onTap: copyClipboard
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

}
