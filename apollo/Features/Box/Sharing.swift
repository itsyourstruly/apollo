
import SwiftUI
import UniformTypeIdentifiers


struct BoxShareButton: View {
    let files: [BoxFile]
    let selectedIDs: Set<UUID>
    let accentColor: NSColor
    
    @State private var isShareTargeted = false
    @State private var targetedAppPath: String? = nil
    @State private var shareCoordinator: SharePickerCoordinator?

    private var urlsToShare: [URL] {
        let selected = files.filter { selectedIDs.contains($0.id) }.map(\.url)
        return selected.isEmpty ? files.map(\.url) : selected
    }

    var body: some View {
        HStack(spacing: 8) {
            if !AppSettings.shared.sharingTargetApps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(AppSettings.shared.sharingTargetApps, id: \.self) { appPath in
                        let appURL = URL(fileURLWithPath: appPath)
                        let appName = appURL.deletingPathExtension().lastPathComponent
                        let isHovered = targetedAppPath == appPath
                        
                        Button {
                            openFiles(urlsToShare, with: appPath)
                        } label: {
                            BoxControlsAppIconView(appPath: appPath, size: 20)
                                .padding(8)
                                .background(isHovered ? Color.white.opacity(0.3) : Color.black.opacity(0.4), in: Circle())
                                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("Open with \(appName)")
                        .onDrop(of: [.fileURL], isTargeted: Binding(
                            get: { self.targetedAppPath == appPath },
                            set: { isTargeted in
                                if isTargeted {
                                    self.targetedAppPath = appPath
                                } else if self.targetedAppPath == appPath {
                                    self.targetedAppPath = nil
                                }
                            }
                        )) { providers in
                            handleAppDrop(providers: providers, appPath: appPath)
                            return true
                        }
                    }
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)
            }

            Button {
                share(urls: urlsToShare)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(accentColor).gradient)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(isShareTargeted ? Color.white.opacity(0.3) : Color.black.opacity(0.4), in: Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: $isShareTargeted) { providers in
                handleShareDrop(providers: providers)
                return true
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.25), in: Capsule())
    }

    private func openFiles(_ urls: [URL], with appPath: String) {
        guard !urls.isEmpty else { return }
        let appURL = URL(fileURLWithPath: appPath)
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func handleAppDrop(providers: [NSItemProvider], appPath: String) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.slimBoxDidReceiveDropThisSession = true
        }
        var droppedURLs: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileUrl = url {
                    DispatchQueue.main.async {
                        droppedURLs.append(fileUrl)
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.openFiles(droppedURLs, with: appPath)
        }
    }

    private func share(urls: [URL]) {
        guard !urls.isEmpty else { return }
        // Issue 6: Set isAddSheetOpen so the island doesn't close while the picker is visible.
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.model.isAddSheetOpen = true
        }
        let picker = NSSharingServicePicker(items: urls)
        let coordinator = SharePickerCoordinator {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.model.isAddSheetOpen = false
            }
            DispatchQueue.main.async {
                self.shareCoordinator = nil
            }
        }
        self.shareCoordinator = coordinator
        picker.delegate = coordinator
        if let window = NSApp.keyWindow, let view = window.contentView {
            let rect = NSRect(x: view.bounds.width - 50, y: view.bounds.height - 20, width: 1, height: 1)
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        } else {
            // No window available; clear the flag immediately.
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.model.isAddSheetOpen = false
            }
            self.shareCoordinator = nil
        }
    }

    private func handleShareDrop(providers: [NSItemProvider]) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.slimBoxDidReceiveDropThisSession = true
        }
        var droppedURLs: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileUrl = url {
                    DispatchQueue.main.async {
                        droppedURLs.append(fileUrl)
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.share(urls: droppedURLs)
        }
    }
}


// MARK: - Box Share Feature
struct BoxControlsAppIconView: View {
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
