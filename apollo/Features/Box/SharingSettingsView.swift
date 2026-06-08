import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppIconView: View {
    let appPath: String
    let size: CGFloat

    var body: some View {
        if FileManager.default.fileExists(atPath: appPath) {
            if let icon = AppIconCache.shared.icon(forPath: appPath) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundColor(.gray.opacity(0.5))
        }
    }
}

struct SharingSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Box Custom Sharing Actions")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Register locally installed applications to quickly open stashed files. These applications will appear in the stashed item options and context menus.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
            
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Registered Applications")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if settings.sharingTargetApps.isEmpty {
                    Text("No applications registered yet. Click below to add one.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(settings.sharingTargetApps, id: \.self) { appPath in
                                HStack(spacing: 12) {
                                    AppIconView(appPath: appPath, size: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent)
                                            .font(.body)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(appPath)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        withAnimation {
                                            settings.sharingTargetApps.removeAll { $0 == appPath }
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            Button(action: addApplication) {
                Label("Add Application...", systemImage: "plus")
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding()
    }

    private func addApplication() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Application"
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            let path = url.path
            if !settings.sharingTargetApps.contains(path) {
                withAnimation {
                    settings.sharingTargetApps.append(path)
                }
            }
        }
    }
}
