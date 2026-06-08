
import SwiftUI
import AppKit

// MARK: - Launcher Page View
struct LauncherPageContent: View, Equatable {
    let apps: [LauncherApp]
    let displayMode: Int
    let columnsCount: Int
    let iconSize: CGFloat
    let textSize: CGFloat
    let showName: Bool
    let width: CGFloat
    let height: CGFloat
    let accentColor: Color
    let showHeader: Bool
    
    let onRemove: (LauncherApp) -> Void
    let onAdd: (LauncherApp) -> Void
    let onTogglePin: (LauncherApp) -> Void
    
    static func == (lhs: LauncherPageContent, rhs: LauncherPageContent) -> Bool {
        lhs.apps == rhs.apps &&
        lhs.displayMode == rhs.displayMode &&
        lhs.columnsCount == rhs.columnsCount &&
        lhs.iconSize == rhs.iconSize &&
        lhs.textSize == rhs.textSize &&
        lhs.showName == rhs.showName &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.accentColor == rhs.accentColor &&
        lhs.showHeader == rhs.showHeader
    }
    
    @State private var isAddPresented = false
    
    var body: some View {
        VStack(spacing: 6) {
            if showHeader {
                HStack {
                    Text("Launcher")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button {
                        isAddPresented = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
            }
            
            if apps.isEmpty {
                VStack {
                    Spacer()
                    Text("No Apps Added")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    if displayMode == 0 {
                        // Grid Mode
                        let cols = max(1, columnsCount)
                        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 6), count: cols)
                        
                        LazyVGrid(columns: gridItems, spacing: 6) {
                            ForEach(apps) { app in
                                Button {
                                    launchApp(app)
                                } label: {
                                    VStack(spacing: 4) {
                                        CustomAppIconView(appPath: app.path, size: iconSize)
                                        if showName {
                                            Text(app.name)
                                                .font(.system(size: max(8, textSize)))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(4)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                        onTogglePin(app)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        onRemove(app)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    } else {
                        // List Mode
                        LazyVStack(spacing: 4) {
                            ForEach(apps) { app in
                                Button {
                                    launchApp(app)
                                } label: {
                                    HStack(spacing: 8) {
                                        CustomAppIconView(appPath: app.path, size: 18)
                                        Text(app.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Button {
                                            onRemove(app)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white.opacity(0.3))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(6)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker") {
                                        onTogglePin(app)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        onRemove(app)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.top, showHeader ? 0 : 16)
            }
        }
        .frame(width: width, height: height)
        .contextMenu {
            Button("Add Application") {
                isAddPresented = true
            }
        }
        .popover(isPresented: $isAddPresented, arrowEdge: .bottom) {
            AddAppSheet(isPresented: $isAddPresented, onAdd: onAdd)
        }
    }
}
