import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Reintegrated Jot

struct JotPageContent: View, Equatable {
    let notes: [JotNote]
    let activeID: UUID?
    let width: CGFloat
    let height: CGFloat
    let columnCount: Int
    let textSize: CGFloat
    let accentColor: NSColor
    let closeSensitivity: CGFloat

    let onOpen: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let jotBinding: (UUID) -> Binding<String>
    let onCloseNotchFromSwipe: () -> Void
    let onUpdateCloseProgress: (CGFloat, Bool) -> Void
    var isJotEditorFocused: FocusState<Bool>.Binding

    static func == (lhs: JotPageContent, rhs: JotPageContent) -> Bool {
        lhs.notes == rhs.notes &&
        lhs.activeID == rhs.activeID &&
        lhs.columnCount == rhs.columnCount &&
        lhs.accentColor == rhs.accentColor &&
        lhs.closeSensitivity == rhs.closeSensitivity
    }

    private var chunkedNotes: [[JotNote]] {
        var chunks: [[JotNote]] = []
        let cols = max(1, min(columnCount, notes.count))
        guard cols > 0 else { return [] }
        for i in stride(from: 0, to: notes.count, by: cols) {
            let end = min(i + cols, notes.count)
            chunks.append(Array(notes[i..<end]))
        }
        return chunks
    }

    var body: some View {
        VStack(spacing: 8) {
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: max(1, width), height: max(1, height), alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if let activeID = activeID {
            UnifiedNotchContainer.JotTextEditorView(
                text: jotBinding(activeID),
                isFocused: isJotEditorFocused,
                textSize: textSize,
                closeSensitivity: closeSensitivity,
                onOverscrollProgress: onUpdateCloseProgress,
                onBottomOverscroll: onCloseNotchFromSwipe,
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
                DispatchQueue.main.async {
                    isJotEditorFocused.wrappedValue = true
                }
            }
        } else if notes.isEmpty {
            UnifiedNotchContainer.DismissableScrollView(
                closeSensitivity: closeSensitivity,
                onOverscrollProgress: onUpdateCloseProgress,
                onBottomOverscroll: onCloseNotchFromSwipe,
                onMetricsChange: { _, _, _ in }
            ) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: max(120, height * 0.6))
            }
        } else {
            let cols = max(1, min(columnCount, notes.count))
            let horizontalPadding: CGFloat = 16
            let cellWidth = max(1, ((width - horizontalPadding) - CGFloat(max(0, cols - 1)) * 8) / CGFloat(cols))
            UnifiedNotchContainer.DismissableScrollView(
                closeSensitivity: closeSensitivity,
                onOverscrollProgress: onUpdateCloseProgress,
                onBottomOverscroll: onCloseNotchFromSwipe,
                onMetricsChange: { _, _, _ in }
            ) {
                noteGrid(cols: cols, cellWidth: cellWidth)
            }
        }
    }

    private func noteGrid(cols: Int, cellWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            ForEach(chunkedNotes, id: \.first?.id) { row in
                HStack(spacing: 8) {
                    ForEach(row) { note in
                        UnifiedNotchContainer.JotNoteCardView(
                            note: note,
                            accentColor: Color(accentColor),
                            previewText: jotNotePreview(note),
                            textSize: textSize,
                            isEmpty: note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            onOpen: { onOpen(note.id) },
                            onDelete: { onDelete(note.id) }
                        )
                        .frame(width: cellWidth)
                    }
                    if row.count < cols {
                        ForEach(0..<(cols - row.count), id: \.self) { _ in
                            Color.clear.frame(width: cellWidth)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    private func jotNotePreview(_ note: JotNote) -> String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Tap to start writing" }
        return trimmed
    }
}

extension UnifiedNotchContainer {
    // MARK: - Jot Page
    func sidebarPage(contentAreaHeight: CGFloat) -> some View {
        JotPageContent(
            notes: model.jotNotes,
            activeID: model.activeJotID,
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            columnCount: settings.jotColumns,
            textSize: settings.jotTextSize,
            accentColor: settings.accentColor,
            closeSensitivity: settings.clampedCloseSensitivity,
            onOpen: { model.activeJotID = $0 },
            onDelete: { id in
                withAnimation {
                    model.jotNotes.removeAll { $0.id == id }
                    if model.activeJotID == id {
                        model.activeJotID = nil
                    }
                }
            },
            jotBinding: jotBinding(for:),
            onCloseNotchFromSwipe: closeNotchFromSwipe,
            onUpdateCloseProgress: { p, a in updateCloseProgress(p, animate: a) },
            isJotEditorFocused: $isJotEditorFocused
        )
        .equatable()
        .padding(.top, pageTopContentInset)
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

    func exportActiveJot() {
        guard let activeID = model.activeJotID,
              let note = model.jotNotes.first(where: { $0.id == activeID }) else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "Note-\(note.id.uuidString.prefix(6)).txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try note.text.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save note: \(error)")
                }
            }
        }
    }

}
