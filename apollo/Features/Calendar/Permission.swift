
import SwiftUI

// MARK: - Calendar Permission helper View
struct CalendarPermissionStatusView: View {
    @ObservedObject private var manager = CalendarManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if manager.permissionGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Calendar permission is granted.")
                        .font(.body)
                } else if manager.permissionChecked {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar access is denied.")
                            .font(.body)
                            .fontWeight(.semibold)
                        Text("Please enable Calendar permissions for Apollo in System Settings -> Privacy & Security -> Calendars.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.gray)
                    Text("Calendar permission has not been requested yet.")
                        .font(.body)
                }
            }
            
            if !manager.permissionGranted {
                Button("Request Calendar Access") {
                    manager.requestPermission { granted in
                        manager.checkPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            manager.checkPermission()
        }
    }
}
