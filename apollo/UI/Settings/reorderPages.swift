
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ReorderablePageList for Settings Layout Customization
struct ReorderablePageList: View {
    @ObservedObject var settings: AppSettings
    @State private var draggedItem: Int?
    @State private var localOrder: [Int] = []

    var body: some View {
        VStack(spacing: 6) {
            ForEach(localOrder, id: \.self) { rawValue in
                if shouldShowPageInLayout(rawValue) {
                    rowView(for: rawValue)
                }
            }
        }
        .onAppear {
            localOrder = settings.pageOrder
        }
        .onChange(of: settings.pageOrder) { _, newOrder in
            if localOrder != newOrder {
                localOrder = newOrder
            }
        }
    }

    private func shouldShowPageInLayout(_ rawValue: Int) -> Bool {
        if rawValue == 6 {
            // Bookmarks is only shown separately in layout if customActionsLayoutOption is Separated (1).
            // In Combined mode (0), Launcher (5) represents "Launcher & Bookmarks", and rawValue 6 is hidden/unused.
            return settings.customActionsLayoutOption == 1
        }
        return true
    }

    private func pageName(for rawValue: Int) -> String {
        switch rawValue {
        case 0: return "Clipboard"
        case 1: return "Jot"
        case 2: return "Box"
        case 3: return "Chrono"
        case 4: return "Calendar"
        case 5:
            return settings.customActionsLayoutOption == 0 ? "Launcher & Bookmarks" : "Launcher"
        case 6: return "Bookmarks"
        default: return "Unknown"
        }
    }

    private func pageIcon(for rawValue: Int) -> String {
        switch rawValue {
        case 0: return "doc.on.clipboard"
        case 1: return "note.text"
        case 2: return "shippingbox.fill"
        case 3: return "timer"
        case 4: return "calendar"
        case 5: return "app.fill"
        case 6: return "globe"
        default: return "square.grid.2x2"
        }
    }

    private func isEnabledBinding(for rawValue: Int) -> Binding<Bool> {
        switch rawValue {
        case 0: return $settings.clipEnabled
        case 1: return $settings.jotEnabled
        case 2: return $settings.boxEnabled
        case 3: return $settings.chronoEnabled
        case 4: return $settings.calendarEnabled
        case 5: return $settings.launcherEnabled
        case 6: return $settings.bookmarksEnabled
        default:
            return .constant(false)
        }
    }

    private func rowView(for rawValue: Int) -> some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 4)

            // Icon
            Image(systemName: pageIcon(for: rawValue))
                .foregroundColor(isEnabledBinding(for: rawValue).wrappedValue ? Color(settings.accentColor) : .secondary)
                .frame(width: 18)

            // Name
            Text(pageName(for: rawValue))
                .font(.body)
                .foregroundColor(isEnabledBinding(for: rawValue).wrappedValue ? .primary : .secondary)

            Spacer()

            // Toggle switch
            Toggle("", isOn: isEnabledBinding(for: rawValue))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(draggedItem == rawValue ? 0.08 : 0.02))
        )
        .contentShape(Rectangle())
        .onDrag {
            self.draggedItem = rawValue
            return NSItemProvider(object: String(rawValue) as NSString)
        }
        .onDrop(of: [.text], delegate: PageDropDelegate(item: rawValue, list: $localOrder, draggedItem: $draggedItem) {
            settings.pageOrder = localOrder
        })
    }
}

// MARK: - Drop Delegate for Reordering Layout Items
struct PageDropDelegate: DropDelegate {
    let item: Int
    @Binding var list: [Int]
    @Binding var draggedItem: Int?
    var onCommit: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        onCommit()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        if draggedItem != item {
            guard let from = list.firstIndex(of: draggedItem),
                  let to = list.firstIndex(of: item) else { return }
            if list[to] != draggedItem {
                withAnimation(.easeInOut(duration: 0.2)) {
                    list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
}
