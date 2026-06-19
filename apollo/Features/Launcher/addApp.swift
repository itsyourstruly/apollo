
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add App Sheet View
struct AddAppSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (LauncherApp) -> Void
    
    @State private var searchPattern = ""
    @State private var scannedApps: [LauncherApp] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Add Application")
                .font(.headline)
                .foregroundColor(.white)
            
            TextField("Search Applications...", text: $searchPattern)
                .textFieldStyle(.plain)
                .padding(6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .foregroundColor(.white)
            
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxHeight: .infinity)
            } else {
                let filtered = scannedApps.filter {
                    searchPattern.isEmpty ? true : $0.name.lowercased().contains(searchPattern.lowercased())
                }
                
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { app in
                            Button {
                                onAdd(app)
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    CustomAppIconView(appPath: app.path, size: 18)
                                    Text(app.name)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(5)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 160)
            }
            
            HStack {
                Button("Browse File...") {
                    let openPanel = NSOpenPanel()
                    openPanel.allowedContentTypes = [.application]
                    openPanel.canChooseFiles = true
                    openPanel.canChooseDirectories = false
                    openPanel.allowsMultipleSelection = false
                    if openPanel.runModal() == .OK, let url = openPanel.url {
                        let app = LauncherApp(name: url.deletingPathExtension().lastPathComponent, path: url.path, bundleIdentifier: Bundle(url: url)?.bundleIdentifier)
                        onAdd(app)
                        isPresented = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(10)
        .frame(width: 250)
        .background(Color.black.opacity(0.9))
        .onAppear {
            scanAppsBackground()
        }
    }
    
    private func scanAppsBackground() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = getInstalledApplications()
            DispatchQueue.main.async {
                self.scannedApps = apps
                self.isLoading = false
            }
        }
    }
}

