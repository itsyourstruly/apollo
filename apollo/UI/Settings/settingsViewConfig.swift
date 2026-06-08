
import SwiftUI

struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    private static var focusedWindowNumbers = Set<Int>()

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: nsView)
        }
    }

    private func configureWindowIfAvailable(from view: NSView) {
        guard let window = view.window else { return }
        let standardWindowMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        window.styleMask.formUnion(standardWindowMask)

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.toolbarButton)?.isHidden = true
        window.toolbar = nil
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        if !Self.focusedWindowNumbers.contains(window.windowNumber) {
            Self.focusedWindowNumbers.insert(window.windowNumber)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
