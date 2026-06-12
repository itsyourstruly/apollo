
import SwiftUI
import AppKit

// MARK: Share Picker Coordinator
final class SharePickerCoordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private let onDismiss: () -> Void

    init(_ onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onDismiss()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        onDismiss()
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        onDismiss()
    }
}

final class ShareMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = ShareMenuDelegate()
    
    func menuDidClose(_ menu: NSMenu) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.model.isAddSheetOpen = false
        }
    }
}

final class ShareMenuActionTarget: NSObject {
    static let shared = ShareMenuActionTarget()
    
    @objc func openApp(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let urls = dict["urls"] as? [URL],
              let appPath = dict["appPath"] as? String else { return }
        let appURL = URL(fileURLWithPath: appPath)
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    
    @objc func performService(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let urls = dict["urls"] as? [URL],
              let service = dict["service"] as? NSSharingService else { return }
        service.perform(withItems: urls)
    }
}
