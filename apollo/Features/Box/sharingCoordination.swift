
import SwiftUI
import AppKit

// MARK: Share Picker Coordinator
final class SharePickerCoordinator: NSObject, NSSharingServicePickerDelegate {
    private let onDismiss: () -> Void

    init(_ onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onDismiss()
    }
}
