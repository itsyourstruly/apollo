
import SwiftUI

struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    class Coordinator {
        var hasConfigured = false
        var observers: [NSObjectProtocol] = []
        
        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if !context.coordinator.hasConfigured, nsView.window?.titleVisibility != .hidden {
            context.coordinator.hasConfigured = true
            DispatchQueue.main.async {
                self.configureWindowIfAvailable(from: nsView, context: context)
            }
        }
    }

    private func configureWindowIfAvailable(from view: NSView, context: Context) {
        guard let window = view.window else { return }
        guard window.titleVisibility != .hidden else { return }
        
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
        
        let closeToken = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("apolloSettingsClosed"), object: nil)
        }
        let openToken = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("apolloSettingsOpened"), object: nil)
        }
        
        context.coordinator.observers.append(closeToken)
        context.coordinator.observers.append(openToken)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
