import SwiftUI
import AppKit
import Combine

struct CopyPopupView: View {
    @ObservedObject var manager = CopyPopupManager.shared
    @State private var activeEntry: ClipboardEntry?
    
    var body: some View {
        let isVisible = manager.isVisible
        let notchH = AppSettings.shared.effectiveNotchHeight
        let notchW = AppSettings.shared.effectiveNotchWidth
        let targetW = notchW
        let windowW = max(360, notchW + 40)
        
        ZStack(alignment: .top) {
            Color.clear
            
            if let entry = activeEntry {
                VStack(spacing: 0) {
                    Spacer().frame(height: notchH)
                    
                    HStack(spacing: 0) {
                        if isVisible {
                            Text(formatEntry(entry))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(width: targetW, height: 32)
                }
                .frame(width: targetW, height: notchH + 32, alignment: .bottom)
                .background(
                    BottomRoundedRectangle(cornerRadius: AppSettings.shared.cornerRadius)
                        .fill(Color(AppSettings.shared.backgroundColor))
                        .shadow(color: Color.black.opacity(isVisible ? 0.3 : 0.0), radius: 8, x: 0, y: 4)
                )
                .offset(y: isVisible ? 0 : -32)
            }
        }
        .frame(width: windowW, height: notchH + 32, alignment: .top)
        .onReceive(manager.$currentEntry) { newEntry in
            if let newEntry = newEntry {
                activeEntry = newEntry
            }
        }
    }
    
    private func formatEntry(_ entry: ClipboardEntry) -> String {
        let notchW = AppSettings.shared.effectiveNotchWidth
        let maxLen = max(15, Int(notchW / 8) - 10)
        
        if !entry.filePaths.isEmpty {
            let names = entry.fileNames ?? []
            if names.isEmpty {
                return "copied file"
            } else if names.count == 1 {
                let name = names[0]
                if name.count > maxLen {
                    return "copied \(name.prefix(maxLen))..."
                }
                return "copied \(name)"
            } else {
                let name = names[0]
                let suffix = " and \(names.count - 1) others"
                let remainingSpace = maxLen - suffix.count
                if name.count > remainingSpace && remainingSpace > 5 {
                    return "copied \(name.prefix(remainingSpace))...\(suffix)"
                }
                return "copied \(name)\(suffix)"
            }
        } else if let text = entry.text {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.count > maxLen {
                return "copied \(clean.prefix(maxLen))..."
            } else {
                return "copied \(clean)"
            }
        }
        return "copied content"
    }
}

@MainActor
class CopyPopupManager: ObservableObject {
    static let shared = CopyPopupManager()
    
    @Published var isVisible: Bool = false
    @Published var currentEntry: ClipboardEntry? = nil
    
    private var dismissalTask: Task<Void, Never>?
    private var popupWindow: NSPanel?
    
    private init() {}
    
    func show(for entry: ClipboardEntry) {
        guard AppSettings.shared.enableCopyPopup else { return }
        
        dismissalTask?.cancel()
        setupPopupWindowIfNeeded()
        
        self.currentEntry = entry
        
        withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
            self.isVisible = true
        }
        
        dismissalTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }
    
    func dismiss() {
        dismissalTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.isVisible = false
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, !self.isVisible else { return }
            self.popupWindow?.orderOut(nil)
        }
    }
    
    private func setupPopupWindowIfNeeded() {
        let notchW = AppSettings.shared.effectiveNotchWidth
        let windowW = max(360, notchW + 40)
        let notchH = AppSettings.shared.effectiveNotchHeight
        let windowH = notchH + 32
        
        if popupWindow == nil {
            let rect = NSRect(x: 0, y: 0, width: windowW, height: windowH)
            let panel = NSPanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .statusBar + 3
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let hostingView = NSHostingView(rootView: CopyPopupView())
            hostingView.autoresizingMask = [.width, .height]
            hostingView.sizingOptions = []
            if #available(macOS 11.0, *) { hostingView.safeAreaRegions = [] }
            panel.contentView = hostingView
            popupWindow = panel
        }
        
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.screens.first {
            let notchX = AppSettings.shared.hardwareNotchX
            let windowX = notchX - (windowW - notchW) / 2
            let windowY = screen.frame.maxY - windowH
            
            popupWindow?.setFrame(NSRect(x: windowX, y: windowY, width: windowW, height: windowH), display: true)
        }
        popupWindow?.orderFrontRegardless()
    }
}
