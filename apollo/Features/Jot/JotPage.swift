import SwiftUI
import AppKit

// MARK: - Reintegrated Jot

extension UnifiedNotchContainer {
    // MARK: - Jot Page
    var sidebarPage: some View {
        jotPage
    }

    @ViewBuilder
    private func jotPageContent(width: CGFloat, height: CGFloat) -> some View {
        if let activeID = model.activeJotID {
            jotEditor(activeID: activeID, width: width, height: height)
        } else if model.jotNotes.isEmpty {
            emptyDismissableScrollView(
                onMetricsChange: { _, _, _ in }
            ) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: max(120, height * 0.6))
            }
        } else {
            let columnCount = max(1, min(settings.jotColumns, model.jotNotes.count))
            let columns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8), count: columnCount)
            let cellWidth = max(1, (width - CGFloat(max(0, columnCount - 1)) * 8) / CGFloat(columnCount))
            DismissableScrollView(
                closeSensitivity: settings.clampedCloseSensitivity,
                onOverscrollProgress: { progress, animate in
                    updateCloseProgress(progress, animate: animate)
                },
                onBottomOverscroll: { closeNotchFromSwipe() },
                onMetricsChange: { _, _, _ in }
            ) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.jotNotes) { note in
                        jotCard(note, cellWidth: cellWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
            }
        }
    }

    private var jotPage: some View {
        jotPageWithWidth(scaledPanelWidth(for: settings), height: scaledPanelHeight(for: settings) - settings.effectiveNotchHeight)
    }

    private func jotPageWithWidth(_ width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            jotPageContent(width: width, height: height)
            Spacer(minLength: 0)
        }
        .padding(.top, pageTopContentInset)
        .padding(.horizontal, 8)
        .frame(width: max(1, width), height: max(1, height - pageTopContentInset), alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func createJot() {
        let note = JotNote()
        var notes = model.jotNotes
        notes.insert(note, at: 0)
        model.jotNotes = notes
        model.activeJotID = note.id
        isJotEditorFocused = true
    }

    func closeActiveJot() {
        model.activeJotID = nil
        isJotEditorFocused = false
    }

    private func jotBinding(for noteID: UUID) -> Binding<String> {
        Binding(
            get: {
                model.jotNotes.first(where: { $0.id == noteID })?.text ?? ""
            },
            set: { newValue in
                guard let index = model.jotNotes.firstIndex(where: { $0.id == noteID }) else { return }
                var notes = model.jotNotes
                notes[index].text = newValue
                notes[index].updatedAt = Date()
                model.jotNotes = notes
            }
        )
    }

    private func jotNotePreview(_ note: JotNote) -> String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Tap to start writing" }
        return trimmed
    }

    private func jotCard(_ note: JotNote, cellWidth: CGFloat) -> some View {
        let accentColor = Color(settings.accentColor)
        return JotNoteCardView(
            note: note,
            accentColor: accentColor,
            previewText: jotNotePreview(note),
            textSize: settings.jotTextSize,
            isEmpty: note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onOpen: {
                model.activeJotID = note.id
            },
            onDelete: {
                withAnimation {
                    model.jotNotes.removeAll { $0.id == note.id }
                    if model.activeJotID == note.id {
                        model.activeJotID = nil
                    }
                }
            }
        )
    }

    private func jotEditor(activeID: UUID, width: CGFloat, height: CGFloat) -> some View {
        JotTextEditorView(
            text: jotBinding(for: activeID),
            isFocused: $isJotEditorFocused,
            textSize: settings.jotTextSize,
            closeSensitivity: settings.clampedCloseSensitivity,
            onOverscrollProgress: { progress, animate in
                updateCloseProgress(progress, animate: animate)
            },
            onBottomOverscroll: { closeNotchFromSwipe() },
            onScrollMetricsChange: { _, _, _ in }
        )
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(
            width: safeDimension(width - 16, fallback: 1),
            height: max(120, safeDimension(height - 16, fallback: 120)),
            alignment: .top
        )
        .onAppear {
            isJotEditorFocused = true
        }
    }

}
