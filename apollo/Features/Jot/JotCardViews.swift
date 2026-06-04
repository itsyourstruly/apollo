import SwiftUI
import AppKit

// MARK: - Jot Card Views

extension UnifiedNotchContainer {
    struct JotNoteCardView: View, Equatable {
        let note: JotNote
        let accentColor: Color
        let previewText: String
        let textSize: CGFloat
        let isEmpty: Bool
        let onOpen: () -> Void
        let onDelete: () -> Void

        static func == (lhs: JotNoteCardView, rhs: JotNoteCardView) -> Bool {
            lhs.note.id == rhs.note.id &&
            lhs.note.updatedAt == rhs.note.updatedAt &&
            lhs.accentColor == rhs.accentColor &&
            lhs.textSize == rhs.textSize &&
            lhs.isEmpty == rhs.isEmpty
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(previewText)
                            .font(.system(size: max(11, textSize)))
                            .fontWeight(isEmpty ? .regular : .semibold)
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentColor.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
    }

}
