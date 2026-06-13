
import SwiftUI
import UniformTypeIdentifiers


struct BoxShareButton: View {
    let files: [BoxFile]
    let selectedIDs: Set<UUID>
    let accentColor: NSColor
    let isBoxTargeted: Bool
    
    @State private var isShareTargeted = false
    @State private var targetedAppPath: String? = nil
    @State private var shareCoordinator: SharePickerCoordinator?
    @State private var isHovering = false

    private var urlsToShare: [URL] {
        let selected = files.filter { selectedIDs.contains($0.id) }.map(\.url)
        return selected.isEmpty ? files.map(\.url) : selected
    }

    private var isExpanded: Bool {
        isHovering || isShareTargeted || targetedAppPath != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            if isExpanded {
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
                                    .contentShape(Circle())
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .help("Open with \(appName)")
                            .onDrop(of: [.fileURL], isTargeted: Binding(
                                get: { self.targetedAppPath == appPath },
                                set: { isTargeted in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if isTargeted {
                                            self.targetedAppPath = appPath
                                        } else if self.targetedAppPath == appPath {
                                            self.targetedAppPath = nil
                                        }
                                    }
                                }
                            )) { providers in
                                handleAppDrop(providers: providers, appPath: appPath)
                                return true
                            }
                        }
                    }
                }
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
                    .contentShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .help("Share")
            .onDrop(of: [.fileURL], isTargeted: Binding(
                get: { isShareTargeted },
                set: { isTargeted in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isShareTargeted = isTargeted
                    }
                }
            )) { providers in
                handleShareDrop(providers: providers)
                return true
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.25), in: Capsule())
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
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
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.model.isAddSheetOpen = true
        }
        
        let menu = NSMenu(title: "Share")
        
        if !AppSettings.shared.sharingTargetApps.isEmpty {
            for appPath in AppSettings.shared.sharingTargetApps {
                let appURL = URL(fileURLWithPath: appPath)
                let appName = appURL.deletingPathExtension().lastPathComponent
                let item = NSMenuItem(title: "Open with \(appName)", action: #selector(ShareMenuActionTarget.openApp(_:)), keyEquivalent: "")
                item.target = ShareMenuActionTarget.shared
                item.representedObject = ["urls": urls, "appPath": appPath]
                if let icon = AppIconCache.shared.icon(forPath: appPath)?.copy() as? NSImage {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        
        let airdropService = NSSharingService(named: .sendViaAirDrop)
        if let airdropService = airdropService {
            let item = NSMenuItem(title: "AirDrop", action: #selector(ShareMenuActionTarget.performService(_:)), keyEquivalent: "")
            item.target = ShareMenuActionTarget.shared
            item.representedObject = ["urls": urls, "service": airdropService]
            if let icon = airdropService.image.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        
        let messageService = NSSharingService(named: .composeMessage)
        if let messageService = messageService {
            let item = NSMenuItem(title: "Messages", action: #selector(ShareMenuActionTarget.performService(_:)), keyEquivalent: "")
            item.target = ShareMenuActionTarget.shared
            item.representedObject = ["urls": urls, "service": messageService]
            if let icon = messageService.image.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        
        let mailService = NSSharingService(named: .composeEmail)
        if let mailService = mailService {
            let item = NSMenuItem(title: "Mail", action: #selector(ShareMenuActionTarget.performService(_:)), keyEquivalent: "")
            item.target = ShareMenuActionTarget.shared
            item.representedObject = ["urls": urls, "service": mailService]
            if let icon = mailService.image.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
        
        let services: [NSSharingService]
        let selector = NSSelectorFromString("sharingServicesForItems:")
        if let classObject = NSClassFromString("NSSharingService") as AnyObject?,
           classObject.responds(to: selector),
           let result = classObject.perform(selector, with: urls)?.takeUnretainedValue() as? [NSSharingService] {
            services = result
        } else {
            services = []
        }
        let airdropTitle = airdropService?.title ?? "AirDrop"
        let messageTitle = messageService?.title ?? "Messages"
        let mailTitle = mailService?.title ?? "Mail"
        let otherServices = services.filter { $0.title != airdropTitle && $0.title != messageTitle && $0.title != mailTitle }
        if !otherServices.isEmpty {
            menu.addItem(.separator())
            for service in otherServices {
                let item = NSMenuItem(title: service.title, action: #selector(ShareMenuActionTarget.performService(_:)), keyEquivalent: "")
                item.target = ShareMenuActionTarget.shared
                item.representedObject = ["urls": urls, "service": service]
                if let icon = service.image.copy() as? NSImage {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
                menu.addItem(item)
            }
        }
        
        menu.delegate = ShareMenuDelegate.shared
        
        var targetView: NSView? = nil
        if let window = NSApp.keyWindow {
            targetView = window.contentView
        } else if let delegate = NSApp.delegate as? AppDelegate {
            if delegate.model.boxSlimModeActive {
                targetView = delegate.slimBoxWindow?.contentView
            } else {
                targetView = delegate.islandWindow?.contentView
            }
        }
        
        if let view = targetView ?? NSApp.windows.first(where: { $0.isVisible })?.contentView {
            let location = view.window?.mouseLocationOutsideOfEventStream ?? NSEvent.mouseLocation
            menu.popUp(positioning: nil, at: location, in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
