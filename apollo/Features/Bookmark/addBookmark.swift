
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Add Bookmark Sheet View
struct AddBookmarkSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (BookmarkItem) -> Void
    
    @State private var name = ""
    @State private var urlString = ""
    @State private var customBrowserPath = ""
    @State private var isPickingFile = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Bookmark")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Name")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                TextField("Website Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("URL")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                TextField("example.com", text: $urlString)
                    .textFieldStyle(.plain)
                    .padding(5)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Browser Path (Optional)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                HStack(spacing: 6) {
                    TextField("/Applications/Safari.app", text: $customBrowserPath)
                        .textFieldStyle(.plain)
                        .padding(5)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundColor(.white)
                    
                    Button("Pick...") {
                        isPickingFile = true
                        let openPanel = NSOpenPanel()
                        openPanel.allowedContentTypes = [.application]
                        openPanel.canChooseFiles = true
                        openPanel.canChooseDirectories = false
                        DispatchQueue.main.async {
                            if openPanel.runModal() == .OK, let url = openPanel.url {
                                customBrowserPath = url.path
                            }
                            isPickingFile = false
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Add") {
                    guard !name.isEmpty, !urlString.isEmpty else { return }
                    let item = BookmarkItem(name: name, urlString: urlString, customBrowserPath: customBrowserPath.isEmpty ? nil : customBrowserPath)
                    onAdd(item)
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(10)
        .frame(width: 260)
        .background(Color.black.opacity(0.9))
        .interactiveDismissDisabled(isPickingFile)
    }
}
