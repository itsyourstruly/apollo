
import SwiftUI
import Sparkle

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    let updater: SPUUpdater

    @State private var selection: SettingsSection? = .general
    @State private var selectedTitlePage: IslandPage = .clipboard
    @State private var isSettingsAddAppPresented = false
    @State private var isSettingsAddBookmarkPresented = false
    @State private var showTitleOverrides = false
    @State private var showAdvancedAnimation = false
    @State private var launcherApps: [LauncherApp] = []
    @State private var bookmarkItems: [BookmarkItem] = []
    @State private var isWindowVisible = true
    @State private var isUninstallAlertPresented = false
    @AppStorage(AppStorageKey.devicePopupUseAccentSymbols) private var devicePopupUseAccentSymbols = true

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        let _ = formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 200
        return formatter
    }()

    var body: some View {
        let accent = Color(settings.accentColor)
        Group {
            if isWindowVisible {
                HSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        List(SettingsSection.allCases, selection: $selection) { section in
                            Label(section.rawValue, systemImage: section.symbolName)
                                .tag(section)
                        }
                        .listStyle(.sidebar)
                        
                        Button {
                            isUninstallAlertPresented = true
                        } label: {
                            Label("Uninstall Apollo", systemImage: "trash")
                                .foregroundColor(.red)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                    }
                    .frame(minWidth: 140, idealWidth: 210, maxWidth: 250)

                    Group {
                        switch selection ?? .general {
                        case .general:
                            generalSettings
                        case .appearance:
                            appearanceSettings
                        case .clip:
                            clipSettings
                        case .jot:
                            jotSettings
                        case .box:
                            boxSettings
                        case .chrono:
                            chronoSettings
                        case .calendar:
                            calendarSettings
                        case .launcherBookmarks:
                            launcherBookmarksSettings
                        case .sharing:
                            SharingSettingsView()
                        case .advanced:
                            advancedSettings
                        case .updates:
                            updatesSettings
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea(.container, edges: .top)
                }
                .frame(minWidth: 520, minHeight: 420)
                .tint(accent)
                .controlSize(.regular)
                .toggleStyle(.switch)
                .alert("Uninstall Apollo?", isPresented: $isUninstallAlertPresented) {
                    Button("Cancel", role: .cancel) { }
                    Button("Uninstall", role: .destructive) {
                        performUninstall()
                    }
                } message: {
                    Text("Are you sure? This will remove all settings and data. You will need to manually move the Apollo app to the Trash afterwards. This action cannot be undone.")
                }
            } else {
                Color.clear
                    .frame(minWidth: 520, minHeight: 420)
            }
        }
        .background(SettingsWindowChromeConfigurator())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear {
            settings.showHoverPreviews = true
            launcherApps = loadLauncherApps()
            bookmarkItems = loadBookmarkItems()
        }
        .onDisappear {
            settings.showHoverPreviews = false
            // Instantly clear memory when Settings is closed to prevent RAM creep
            AppIconCache.shared.clear()
            BookmarkIconCache.shared.clear()
            launcherApps.removeAll()
            bookmarkItems.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("apolloSettingsClosed"))) { _ in
            settings.showHoverPreviews = false
            AppIconCache.shared.clear()
            BookmarkIconCache.shared.clear()
            launcherApps.removeAll()
            bookmarkItems.removeAll()
            isWindowVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("apolloSettingsOpened"))) { _ in
            isWindowVisible = true
            settings.showHoverPreviews = true
            launcherApps = loadLauncherApps()
            bookmarkItems = loadBookmarkItems()
        }
    }

    private func saveApps() {
        persistLauncherApps(launcherApps)
        NotificationCenter.default.post(name: NSNotification.Name("apolloDataChanged"), object: nil)
    }

    private func saveBookmarks() {
        persistBookmarkItems(bookmarkItems)
        NotificationCenter.default.post(name: NSNotification.Name("apolloDataChanged"), object: nil)
    }

    private func performUninstall() {
        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
        
        let fm = FileManager.default
        
        // Remove Application Support directories
        if let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            if let bundleID = Bundle.main.bundleIdentifier {
                try? fm.removeItem(at: appSupportURL.appendingPathComponent(bundleID))
            }
            try? fm.removeItem(at: appSupportURL.appendingPathComponent("apollo"))
            try? fm.removeItem(at: appSupportURL.appendingPathComponent("Apollo"))
        }
        
        // Remove Caches directories
        if let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            if let bundleID = Bundle.main.bundleIdentifier {
                try? fm.removeItem(at: cachesURL.appendingPathComponent(bundleID))
            }
            try? fm.removeItem(at: cachesURL.appendingPathComponent("apollo"))
            try? fm.removeItem(at: cachesURL.appendingPathComponent("Apollo"))
        }

        // Remove Preferences explicitly
        if let prefsURL = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Preferences") {
            if let bundleID = Bundle.main.bundleIdentifier {
                try? fm.removeItem(at: prefsURL.appendingPathComponent("\(bundleID).plist"))
            }
        }
        
        // Terminate so the user can trash the app
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private func titleCustomizationSection(for page: IslandPage) -> some View {
        Section("Title Overrides") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Custom title text", text: pageCustomTitleBinding(page))
                    .textFieldStyle(.roundedBorder)
                Text("* for empty")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Toggle("Show title icon", isOn: pageShowTitleIconBinding(page))
            
            Picker("Alignment", selection: pageTitleAlignmentBinding(page)) {
                ForEach(TitleAlignmentOption.allCases, id: \.rawValue) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                Text("Size")
                Slider(value: pageTitleSizeBinding(page), in: settings.titleSizeRange, onEditingChanged: { isEditing in
                    setTitlePreviewFocus(isEditing: isEditing, page: page)
                })
                Text("\(Int(settings.titleSize(for: page)))")
                    .frame(width: 36, alignment: .trailing)
            }
            
            HStack {
                ColorPicker("Color", selection: pageTitleColorBinding(page))
                    .disabled(pageTitleUseAccentBinding(page).wrappedValue)
                Toggle("Use accent", isOn: pageTitleUseAccentBinding(page))
                    .toggleStyle(.switch)
            }
            
            HStack(spacing: 10) {
                TextField("SF Symbol", text: pageTitleSymbolBinding(page))
                    .textFieldStyle(.roundedBorder)
                Image(systemName: settings.titleSymbol(for: page, fallback: "textformat"))
                    .foregroundColor(Color(settings.titleColor(for: page)))
            }
            
            Button("Reset overrides") {
                resetTitleOverrides(for: page)
            }
            .buttonStyle(.bordered)
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Island Size") {
                HStack {
                    Text("Width")
                    Slider(value: $settings.notchWidth, in: settings.notchWidthRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.islandSize, isEditing: isEditing)
                    })

                    Text("\(Int(settings.clampedNotchWidth))")
                        .frame(width: 48, alignment: .trailing)
                }

                HStack {
                    Text("Height")
                    Slider(value: $settings.notchHeight, in: settings.notchHeightRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.islandSize, isEditing: isEditing)
                    })

                    Text("\(Int(settings.clampedNotchHeight))")
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section("Default Page") {
                Picker("Default page", selection: $settings.defaultPage) {
                    ForEach(IslandPage.allCases, id: \.rawValue) { page in
                        let label: String = {
                            switch page {
                            case .clipboard: return "Clip"
                            case .jot: return "Jot"
                            case .box: return "Box"
                            case .chrono: return "Chrono"
                            case .calendar: return "Calendar"
                            case .launcher: return "Launcher"
                            case .bookmarks: return "Bookmarks"
                            case .customCombined: return "Combined"
                            }
                        }()
                        Text(label)
                            .tag(page.rawValue)
                    }
                }
                .disabled(settings.reopenLastPage)

                Toggle("Reopen last page", isOn: $settings.reopenLastPage)
                    .help("Overrides Default Page when enabled")

                Toggle("Default to Box if it has items", isOn: $settings.defaultToBoxIfItems)
            }

            Section("Page Layout") {
                ReorderablePageList(settings: settings)
                    .padding(.vertical, 4)
            }

            Section("Open Method") {
                Picker("Open Method", selection: $settings.openMethod) {
                    Text("Hover to Open").tag(0)
                    Text("Tap to Open").tag(1)
                }
                .pickerStyle(.segmented)
                
                Text(settings.openMethod == 0 ? "Hover over the notch to expand the island." : "Tapping the notch opens the island.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Pager") {
                Picker("Pager Style", selection: $settings.pagerStyle) {
                    Text("Dots").tag(0)
                    Text("Circles").tag(1)
                }
                .pickerStyle(.segmented)
                
                Text(settings.pagerStyle == 0 ? "Displays simple dot indicators on the left side of the notch." : "Displays glassmorphic floating circle indicators below the notch with page icons.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settings.pagerStyle == 1 {
                    Picker("Alignment", selection: $settings.pagerAlignment) {
                        Text("Center").tag(0)
                        Text("Left").tag(1)
                        Text("Right").tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("Size")
                        Slider(value: $settings.pagerSize, in: 24...64)
                        Text("\(Int(settings.pagerSize)) pt")
                            .frame(width: 48, alignment: .trailing)
                    }
                    
                    HStack {
                        Text("Spacing")
                        Slider(value: $settings.pagerSpacing, in: 0...60)
                        Text("\(Int(settings.pagerSpacing)) pt")
                            .frame(width: 48, alignment: .trailing)
                    }
                    
                    Toggle("Show glass background", isOn: $settings.pagerStyle2BackgroundEnabled)
                }

                Toggle("Show pagers", isOn: $settings.showPagers)
            }

            Section("Device Connection Popup") {
                Toggle("New device connection popup", isOn: $settings.devicePopupEnabled)
                
                if settings.devicePopupEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("External storage drives", isOn: $settings.devicePopupStorageEnabled)
                        Toggle("Bluetooth devices (Requires Bluetooth permission)", isOn: $settings.devicePopupBluetoothEnabled)
                        Toggle("Other wired devices (Earbuds, Mice, Displays, etc.)", isOn: $settings.devicePopupWiredEnabled)
                        Toggle("Use accent symbols", isOn: $devicePopupUseAccentSymbols)
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 4)

                    HStack {
                        Text("Popup close delay")
                        Slider(value: $settings.devicePopupDelay, in: 0...30, step: 1)
                        Text(settings.devicePopupDelay == 0 ? "Never" : "\(Int(settings.devicePopupDelay))s")
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Section("Battery Indicator") {
                Toggle("Show battery level around notch", isOn: $settings.batteryIndicatorEnabled)
                
                if settings.batteryIndicatorEnabled {
                    HStack {
                        Text("Bar thickness")
                        Slider(value: $settings.batteryBarThickness, in: 1...12)
                        Text("\(Int(settings.batteryBarThickness)) pt")
                            .frame(width: 40, alignment: .trailing)
                    }
                    
                    Toggle("Show battery track", isOn: $settings.batteryBarShowGhostTrack)
                    
                    Picker("Color Mode", selection: $settings.batteryBarColorMode) {
                        Text("Accent Color").tag(0)
                        Text("Single Color").tag(1)
                        Text("Dynamic Levels").tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    if settings.batteryBarColorMode == 1 {
                        ColorPicker("Bar color", selection: Binding(
                            get: { Color(settings.batteryBarColor) },
                            set: { settings.batteryBarColor = NSColor($0) }
                        ))
                    } else if settings.batteryBarColorMode == 2 {
                        VStack(spacing: 8) {
                            ColorPicker("< 20%", selection: Binding(
                                get: { Color(settings.batteryBarColor0to20) },
                                set: { settings.batteryBarColor0to20 = NSColor($0) }
                            ))
                            ColorPicker("20% - 50%", selection: Binding(
                                get: { Color(settings.batteryBarColor20to50) },
                                set: { settings.batteryBarColor20to50 = NSColor($0) }
                            ))
                            ColorPicker("50% - 75%", selection: Binding(
                                get: { Color(settings.batteryBarColor50to75) },
                                set: { settings.batteryBarColor50to75 = NSColor($0) }
                            ))
                            ColorPicker("75% - 100%", selection: Binding(
                                get: { Color(settings.batteryBarColor75to100) },
                                set: { settings.batteryBarColor75to100 = NSColor($0) }
                            ))
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                    }
                    
                    ColorPicker("Color while charging", selection: Binding(get: { Color(settings.batteryBarColorCharging) }, set: { settings.batteryBarColorCharging = NSColor($0) }))
                    
                    Toggle("Match Low Power Mode (Yellow)", isOn: $settings.batteryBarMatchLowPowerMode)
                }
            }
        }
        .nativeSettingsFormStyle()
    }

    private var clipSettings: some View {
        Form {
            Group {
                Section("Clipboard Configuration") {
                    HStack {
                        Text("Remember clips")
                        Slider(
                            value: Binding(
                                get: { Double(settings.rememberClips) },
                                set: { settings.rememberClips = Int($0.rounded()) }
                            ),
                            in: settings.rememberClipsRange,
                            onEditingChanged: { isEditing in
                                setPreviewFocus(.clipboardLimit, isEditing: isEditing)
                            }
                        )
                        Text("\(settings.rememberClips)")
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text("Set to 0 for unlimited")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Clipboard Layout") {
                    HStack {
                        Text("Columns")
                        Slider(
                            value: Binding(
                                get: { Double(settings.clipboardColumns) },
                                set: { settings.clipboardColumns = Int($0.rounded()) }
                            ),
                            in: settings.clipboardColumnsRange
                        )
                        Text("\(settings.clipboardColumns)")
                            .frame(width: 32, alignment: .trailing)
                    }

                    HStack {
                        Text("Text size")
                        Slider(value: $settings.clipTextSize, in: settings.clipTextSizeRange)
                        Text("\(Int(settings.clipTextSize))")
                            .frame(width: 36, alignment: .trailing)
                    }

                    HStack {
                        Text("File label size")
                        Slider(value: $settings.clipFileLabelSize, in: settings.clipFileLabelSizeRange)
                        Text("\(Int(settings.clipFileLabelSize))")
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                titleCustomizationSection(for: .clipboard)
            }
            .disabled(!settings.clipEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var jotSettings: some View {
        Form {
            Group {
                Section("Jot Layout") {
                    HStack {
                        Text("Columns")
                        Slider(
                            value: Binding(
                                get: { Double(settings.jotColumns) },
                                set: { settings.jotColumns = Int($0.rounded()) }
                            ),
                            in: settings.jotColumnsRange
                        )
                        Text("\(settings.jotColumns)")
                            .frame(width: 32, alignment: .trailing)
                    }

                    HStack {
                        Text("Text size")
                        Slider(value: $settings.jotTextSize, in: settings.jotTextSizeRange)
                        Text("\(Int(settings.jotTextSize))")
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                titleCustomizationSection(for: .jot)
            }
            .disabled(!settings.jotEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var boxSettings: some View {
        Form {
            Group {
                Section("Box Configuration") {
                    Toggle("Show file names in Box", isOn: $settings.showBoxFileNames)
                    
                    Toggle("Enable Slim Box Mode", isOn: $settings.boxSlimModeEnabled)
                        .help("Open a compact 180x260 view of the Box page on drag or when holding a file")
                    
                    if settings.boxSlimModeEnabled {
                        Picker("Trigger Method", selection: $settings.boxSlimModeTrigger) {
                            Text("Wiggle Mouse").tag(0)
                            Text("Hold Delay").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        if settings.boxSlimModeTrigger == 0 {
                            HStack {
                                Text("Wiggle Sensitivity")
                                Slider(value: $settings.boxSlimModeWiggleSensitivity, in: 1.0...10.0)
                                Text(String(format: "%.1f", settings.boxSlimModeWiggleSensitivity))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } else {
                            HStack {
                                Text("Slim Box Hold Delay")
                                Slider(value: $settings.boxSlimModeHoldDuration, in: 0.5...3.0)
                                Text(String(format: "%.1fs", settings.boxSlimModeHoldDuration))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        
                        Picker("Window Position", selection: $settings.boxSlimModePosition) {
                            Text("Default (Notch)").tag(0)
                            Text("Next to Mouse").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        Toggle("Keep Slim Box open after drop", isOn: $settings.boxSlimModeKeepOpen)
                        
                        Picker("Expand Direction", selection: $settings.boxSlimModeExpandDirection) {
                            Text("Horizontal").tag(0)
                            Text("Vertical").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        HStack {
                            Text("Max View Size")
                            Slider(value: $settings.boxSlimModeMaxViewSize, in: 1.0...10.0, step: 1.0)
                            Text("\(Int(settings.boxSlimModeMaxViewSize)) items")
                                .frame(width: 60, alignment: .trailing)
                        }
                        
                        HStack {
                            Text("Item Size")
                            Slider(value: Binding(
                                get: { settings.boxSlimModeItemWidth },
                                set: { newValue in
                                    settings.boxSlimModeItemWidth = newValue
                                    settings.boxSlimModeItemHeight = newValue
                                }
                            ), in: 40.0...160.0, step: 4.0)
                            Text("\(Int(settings.boxSlimModeItemWidth))px")
                                .frame(width: 50, alignment: .trailing)
                        }
                        
                    }
                }

                Section("Box Layout") {
                    HStack {
                        Text("Columns")
                        Slider(
                            value: Binding(
                                get: { Double(settings.boxColumns) },
                                set: { settings.boxColumns = Int($0.rounded()) }
                            ),
                            in: settings.boxColumnsRange
                        )
                        Text("\(settings.boxColumns)")
                            .frame(width: 32, alignment: .trailing)
                    }

                    HStack {
                        Text("File name size")
                        Slider(value: $settings.boxFileNameSize, in: settings.boxFileNameSizeRange)
                        Text("\(Int(settings.boxFileNameSize))")
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Section("Observe Folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        if settings.observedFolders.isEmpty {
                            Text("No folders selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ForEach(settings.observedFolders, id: \.self) { path in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.subheadline)
                                    Text(path)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    settings.observedFolders.removeAll { $0 == path }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            openFolderPanel()
                        } label: {
                            Label("Add folder", systemImage: "plus")
                        }

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Text("Auto-hide toast")
                            Slider(value: $settings.toastHideDelay, in: 0...30, step: 1)
                            Text(settings.toastHideDelay == 0 ? "Never" : "\(Int(settings.toastHideDelay))s")
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                Section("Folder Slots") {
                    Toggle("Enable Folder Slots", isOn: $settings.enableFolderSlots)
                    
                    if settings.enableFolderSlots {
                        Picker("Sort by", selection: $settings.folderSlotsSortOption) {
                            Text("Name").tag(0)
                            Text("Type").tag(1)
                            Text("Size").tag(2)
                            Text("Date Modified").tag(3)
                        }
                        
                        Toggle("Sort folders to top", isOn: $settings.folderSlotsSortFoldersFirst)
                        
                        Toggle("Enable Smart Stacks", isOn: $settings.folderSlotsEnableStacks)
                        
                        if settings.folderSlotsEnableStacks {
                            Toggle("Stack folders", isOn: $settings.folderSlotsStackFolders)
                            
                            HStack {
                                Text("Stack limit")
                                Slider(value: Binding(
                                    get: { Double(settings.folderSlotsStackThreshold) },
                                    set: { settings.folderSlotsStackThreshold = Int($0) }
                                ), in: 3...50, step: 1)
                                Text("\(settings.folderSlotsStackThreshold) items")
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                        
                        Toggle("Put each file type in its own row", isOn: $settings.folderSlotsGroupByType)
                        
                        Picker("Expand Direction", selection: $settings.folderSlotsDirection) {
                            Text("Left").tag(0)
                            Text("Right").tag(1)
                            Text("Bottom").tag(2)
                        }
                        .pickerStyle(.segmented)
                        
                        HStack {
                            Text("Columns")
                            Slider(value: Binding(
                                get: { Double(settings.folderSlotsColumns) },
                                set: { settings.folderSlotsColumns = Int($0) }
                            ), in: 1...8, step: 1)
                            Text("\(settings.folderSlotsColumns)")
                                .frame(width: 32, alignment: .trailing)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if settings.folderSlotsPaths.isEmpty {
                                Text("No folders selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            ForEach(settings.folderSlotsPaths, id: \.self) { path in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.subheadline)
                                        Text(path)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        settings.folderSlotsPaths.removeAll { $0 == path }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Button {
                                openFolderSlotsPanel()
                            } label: {
                                Label("Add folder", systemImage: "plus")
                            }
                        }
                    }
                }

                titleCustomizationSection(for: .box)
            }
            .disabled(!settings.boxEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var chronoSettings: some View {
        Form {
            Group {
                Section("HUD Options") {
                    Toggle("Disable HUD when notch is closed", isOn: $settings.disableChronoHUD)
                }
                titleCustomizationSection(for: .chrono)
            }
            .disabled(!settings.chronoEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var calendarSettings: some View {
        Form {
            Group {
                Section("Calendar Access") {
                    CalendarPermissionStatusView()
                }
                
                Section("Layout Options") {
                    Picker("View Style", selection: $settings.calendarViewOption) {
                        Text("Month").tag(0)
                        Text("Week").tag(1)
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Week starts on", selection: $settings.calendarWeekStartsOn) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Month Grid displays a full monthly layout with day details. Week Carousel displays a horizontal strip for the week.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                titleCustomizationSection(for: .calendar)
            }
            .disabled(!settings.calendarEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var launcherBookmarksSettings: some View {
        Form {
            Group {
                Section("Actions Layout") {
                Picker("Layout mode", selection: $settings.customActionsLayoutOption) {
                    Text("Combined Page").tag(0)
                    Text("Separated Pages").tag(1)
                }
                .pickerStyle(.segmented)
                
                Text("Combined mode places Launcher and Bookmarks inside one scrolling page. Separated mode splits them into two individual pages.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Peeker Widget") {
                Text("Show custom actions at the bottom of the expanded island as a quick-access shortcut strip:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Show launcher apps in Peeker", isOn: $settings.showLauncherInPeeker)
                Toggle("Show bookmarks in Peeker", isOn: $settings.showBookmarksInPeeker)
                
                HStack {
                    Text("Item Size")
                    Slider(value: $settings.peekerSize, in: 10...36)
                    Text("\(Int(settings.peekerSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                .disabled(!settings.showLauncherInPeeker && !settings.showBookmarksInPeeker)
            }

            Section("Launcher Setup") {
                HStack {
                    Text("Columns")
                    Slider(
                        value: Binding(
                            get: { Double(settings.launcherColumns) },
                            set: { settings.launcherColumns = Int($0.rounded()) }
                        ),
                        in: 2...8
                    )
                    Text("\(settings.launcherColumns)")
                        .frame(width: 32, alignment: .trailing)
                }
                
                HStack {
                    Text("Icon Size")
                    Slider(value: $settings.launcherIconSize, in: 24...64)
                    Text("\(Int(settings.launcherIconSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                HStack {
                    Text("Text Size")
                    Slider(value: $settings.launcherTextSize, in: 8...16)
                    Text("\(Int(settings.launcherTextSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                Toggle("Show application names", isOn: $settings.launcherShowName)
                
                Picker("Display layout", selection: $settings.launcherDisplayMode) {
                    Text("Grid").tag(0)
                    Text("List").tag(1)
                }
                .pickerStyle(.segmented)
                
                Toggle("Show 'Add Application' button in island", isOn: $settings.showAddAppButton)
            }

            Section("Manage Applications") {
                List {
                    ForEach(launcherApps) { app in
                        HStack {
                            CustomAppIconView(appPath: app.path, size: 20)
                            Text(app.name)
                                .font(.body)
                            Spacer()
                            Button {
                                if let idx = launcherApps.firstIndex(where: { $0.id == app.id }) {
                                    var updated = launcherApps
                                    updated[idx].isPinned.toggle()
                                    launcherApps = updated
                                    saveApps()
                                }
                            } label: {
                                Image(systemName: app.isPinned ? "pin.fill" : "pin")
                                    .foregroundColor(app.isPinned ? Color(settings.accentColor) : .secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .help(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker")

                            Button {
                                if let idx = launcherApps.firstIndex(where: { $0.id == app.id }) {
                                    launcherApps.remove(at: idx)
                                    saveApps()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                
                Button("Add Application...") {
                    isSettingsAddAppPresented = true
                }
                .popover(isPresented: $isSettingsAddAppPresented, arrowEdge: .bottom) {
                    AddAppSheet(isPresented: $isSettingsAddAppPresented, onAdd: { app in
                        launcherApps.append(app)
                        saveApps()
                    })
                }
            }

            if settings.customActionsLayoutOption != 0 {
                titleCustomizationSection(for: .launcher)
            }

            Section("Bookmarks Setup") {
                HStack {
                    Text("Columns")
                    Slider(
                        value: Binding(
                            get: { Double(settings.bookmarkColumns) },
                            set: { settings.bookmarkColumns = Int($0.rounded()) }
                        ),
                        in: 2...8
                    )
                    Text("\(settings.bookmarkColumns)")
                        .frame(width: 32, alignment: .trailing)
                }

                HStack {
                    Text("Icon Size")
                    Slider(value: $settings.bookmarkIconSize, in: 24...64)
                    Text("\(Int(settings.bookmarkIconSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                HStack {
                    Text("Text Size")
                    Slider(value: $settings.bookmarkTextSize, in: 8...16)
                    Text("\(Int(settings.bookmarkTextSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                Toggle("Show bookmark names", isOn: $settings.bookmarkShowName)
                
                Picker("Display layout", selection: $settings.bookmarkDisplayMode) {
                    Text("Grid").tag(0)
                    Text("List").tag(1)
                }
                .pickerStyle(.segmented)
                
                Toggle("Show 'Add Bookmark' button in island", isOn: $settings.showAddBookmarkButton)
            }

            Section("Manage Bookmarks") {
                List {
                    ForEach(bookmarkItems) { bookmark in
                        HStack {
                            BookmarkIconView(bookmark: bookmark, size: 20, accentColor: Color(settings.accentColor))
                            VStack(alignment: .leading, spacing: 2) {
                                  Text(bookmark.name)
                                      .font(.body)
                                  Text(bookmark.urlString)
                                      .font(.caption)
                                      .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                if let idx = bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                    var updated = bookmarkItems
                                    updated[idx].isPinned.toggle()
                                    bookmarkItems = updated
                                    saveBookmarks()
                                }
                            } label: {
                                Image(systemName: bookmark.isPinned ? "pin.fill" : "pin")
                                    .foregroundColor(bookmark.isPinned ? Color(settings.accentColor) : .secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .help(bookmark.isPinned ? "Unpin from Peeker" : "Pin to Peeker")

                            Button {
                                if let idx = bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                    bookmarkItems.remove(at: idx)
                                    saveBookmarks()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                
                Button("Add Bookmark...") {
                    isSettingsAddBookmarkPresented = true
                }
                .popover(isPresented: $isSettingsAddBookmarkPresented, arrowEdge: .bottom) {
                    AddBookmarkSheet(isPresented: $isSettingsAddBookmarkPresented, onAdd: { bookmark in
                        bookmarkItems.append(bookmark)
                        saveBookmarks()
                        fetchFaviconBase64(for: bookmark.urlString) { base64 in
                            if let base64 = base64 {
                                DispatchQueue.main.async {
                                    if let idx = bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                        bookmarkItems[idx].iconBase64 = base64
                                        saveBookmarks()
                                    }
                                }
                            }
                        }
                    })
                }
            }

            if settings.customActionsLayoutOption != 0 {
                titleCustomizationSection(for: .bookmarks)
            } else {
                titleCustomizationSection(for: .customCombined)
            }
            }
            .disabled(settings.customActionsLayoutOption == 0 ? !settings.launcherEnabled : (!settings.launcherEnabled && !settings.bookmarksEnabled))
        }
        .nativeSettingsFormStyle()
    }

    private var appearanceSettings: some View {
        Form {
            Section("Accent & Background") {
                ColorPicker("Accent color", selection: Binding(
                    get: { Color(settings.accentColor) },
                    set: { settings.accentColor = NSColor($0) }
                ))
                ColorPicker("Background color", selection: Binding(
                    get: { Color(settings.backgroundColor) },
                    set: { settings.backgroundColor = NSColor($0) }
                ))
            }

            Section("Title") {
                Picker("Title alignment", selection: $settings.titleAlignment) {
                    ForEach(TitleAlignmentOption.allCases, id: \.rawValue) { option in
                        Text(option.label)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Title size")
                    Slider(value: $settings.titleSize, in: settings.titleSizeRange, onEditingChanged: { isEditing in
                        setTitlePreviewFocus(isEditing: isEditing, page: selectedTitlePage)
                    })
                    Text("\(Int(settings.titleSize))")
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    ColorPicker("Title color", selection: Binding(
                        get: { Color(settings.titleColor) },
                        set: { settings.titleColor = NSColor($0) }
                    ))
                    .disabled(settings.titleUseAccent)

                    Toggle("Use accent", isOn: $settings.titleUseAccent)
                        .toggleStyle(.switch)
                }

                HStack(spacing: 10) {
                    TextField("SF Symbol name", text: $settings.titleIconName)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: settings.titleIconName.isEmpty ? "textformat" : settings.titleIconName)
                        .foregroundColor(Color(settings.effectiveTitleColor))
                }
            }

            Section("Layout") {
                HStack {
                    Text("Corner radius")
                    Slider(value: $settings.cornerRadius, in: settings.cornerRadiusRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.cornerRadius, isEditing: isEditing)
                    })
                    Text("\(Int(settings.cornerRadius))")
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .nativeSettingsFormStyle()
    }

    private var advancedSettings: some View {
        Form {
            Section("Notch Size") {
                HStack {
                    Text("Notch edge")
                    Slider(value: $settings.notchEdgeThickness, in: settings.notchEdgeThicknessRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.notchEdge, isEditing: isEditing)
                    })
                    Text("\(Int(settings.notchEdgeThickness))")
                        .frame(width: 48, alignment: .trailing)
                }

                DisclosureGroup("Approach size") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Width")
                            Slider(value: $settings.approachWidth, in: settings.approachWidthRange, onEditingChanged: { isEditing in
                                setPreviewFocus(.approach, isEditing: isEditing)
                            })
                            Text("\(Int(settings.approachWidth))")
                                .frame(width: 48, alignment: .trailing)
                        }
                        HStack {
                            Text("Height")
                            Slider(value: $settings.approachHeight, in: settings.approachHeightRange, onEditingChanged: { isEditing in
                                setPreviewFocus(.approach, isEditing: isEditing)
                            })
                            Text("\(Int(settings.approachHeight))")
                                .frame(width: 48, alignment: .trailing)
                        }
                        Text("Approach only animates. Notch edge opens the UI.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            Section("Sensitivities") {
                HStack {
                    Text("Carousel")
                    Slider(value: $settings.carouselSensitivity, in: settings.carouselSensitivityRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.sensitivityCarousel, isEditing: isEditing)
                    })
                    Text(String(format: "%.2f", settings.carouselSensitivity))
                        .frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Close")
                    Slider(value: $settings.closeSensitivity, in: settings.closeSensitivityRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.sensitivityClose, isEditing: isEditing)
                    })
                    Text(String(format: "%.2f", settings.closeSensitivity))
                        .frame(width: 48, alignment: .trailing)
                }
                Text("Higher values trigger with shorter swipes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Animation") {
                DisclosureGroup("Advanced", isExpanded: $showAdvancedAnimation) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notch open")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("Response")
                                Slider(value: $settings.notchAnimationResponse, in: settings.animationResponseRange, onEditingChanged: { isEditing in
                                    setPreviewFocus(.animationNotch, isEditing: isEditing)
                                })
                                Text(String(format: "%.2f", settings.notchAnimationResponse))
                                    .frame(width: 48, alignment: .trailing)
                            }
                            HStack {
                                Text("Damping")
                                Slider(value: $settings.notchAnimationDamping, in: settings.animationDampingRange, onEditingChanged: { isEditing in
                                    setPreviewFocus(.animationNotch, isEditing: isEditing)
                                })
                                Text(String(format: "%.2f", settings.notchAnimationDamping))
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }

                        Divider().opacity(0.3)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Carousel")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("Response")
                                Slider(value: $settings.carouselAnimationResponse, in: settings.animationResponseRange, onEditingChanged: { isEditing in
                                    setPreviewFocus(.animationCarousel, isEditing: isEditing)
                                })
                                Text(String(format: "%.2f", settings.carouselAnimationResponse))
                                    .frame(width: 48, alignment: .trailing)
                            }
                            HStack {
                                Text("Damping")
                                Slider(value: $settings.carouselAnimationDamping, in: settings.animationDampingRange, onEditingChanged: { isEditing in
                                    setPreviewFocus(.animationCarousel, isEditing: isEditing)
                                })
                                Text(String(format: "%.2f", settings.carouselAnimationDamping))
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }

                        Divider().opacity(0.3)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Swipe")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("Response")
                                Slider(value: $settings.swipeAnimationResponse, in: settings.animationResponseRange, onEditingChanged: { isEditing in
                                    setPreviewFocus(.animationSwipe, isEditing: isEditing)
                                })
                                Text(String(format: "%.2f", settings.swipeAnimationResponse))
                                    .frame(width: 48, alignment: .trailing)
                            }
                            HStack {
                                Text("Damping")
                                Slider(value: $settings.swipeAnimationDamping, in: settings.animationDampingRange, onEditingChanged: { isEditing in
                                    setPreviewFocus(.animationSwipe, isEditing: isEditing)
                                })
                                Text(String(format: "%.2f", settings.swipeAnimationDamping))
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }

            Section("Delays") {
                HStack {
                    Text("Approach delay")
                    Slider(value: $settings.approachDelay, in: settings.approachDelayRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.delayApproach, isEditing: isEditing)
                    })
                    Text(String(format: "%.2fs", settings.approachDelay))
                        .frame(width: 56, alignment: .trailing)
                }

                HStack {
                    Text("Hover close")
                    Slider(value: $settings.hoverCloseDelay, in: settings.hoverCloseDelayRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.delayHoverClose, isEditing: isEditing)
                    })
                    Text(String(format: "%.2fs", settings.hoverCloseDelay))
                        .frame(width: 56, alignment: .trailing)
                }

                HStack {
                    Text("Swipe close")
                    Slider(value: $settings.swipeCloseDelay, in: settings.swipeCloseDelayRange, onEditingChanged: { isEditing in
                        setPreviewFocus(.delaySwipeClose, isEditing: isEditing)
                    })
                    Text(String(format: "%.2fs", settings.swipeCloseDelay))
                        .frame(width: 56, alignment: .trailing)
                }

                Toggle("Enable approach", isOn: $settings.enableApproach)
                    .help("Gradually expands the island as the cursor approaches the notch")

                Toggle("Always use approach when dragging file", isOn: $settings.alwaysUseApproachWhenDraggingFile)
                    .help("For file drags, approach is enabled even if disabled, and its width/height are doubled")
            }
        }
        .nativeSettingsFormStyle()
    }

    private var updatesSettings: some View {
        Form {
            Section("Current Version") {
                HStack(spacing: 12) {
                    if let icon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                        Text("Apollo")
                            .font(.headline)
                        Text("Version \(version) (\(build))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Updates") {
                CheckForUpdatesView(updater: updater)
                
                Toggle("Automatically check for updates on startup", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
            }
        }
        .nativeSettingsFormStyle()
    }

    private func pageCustomTitleBinding(_ page: IslandPage) -> Binding<String> {
        Binding(
            get: {
                switch page {
                case .clipboard: return settings.clipboardCustomTitle ?? ""
                case .jot: return settings.jotCustomTitle ?? ""
                case .box: return settings.boxCustomTitle ?? ""
                case .chrono: return settings.chronoCustomTitle ?? ""
                case .calendar: return settings.calendarCustomTitle ?? ""
                case .launcher: return settings.launcherCustomTitle ?? ""
                case .bookmarks: return settings.bookmarksCustomTitle ?? ""
                case .customCombined: return settings.combinedCustomTitle ?? ""
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmed.isEmpty ? nil : trimmed
                switch page {
                case .clipboard: settings.clipboardCustomTitle = value
                case .jot: settings.jotCustomTitle = value
                case .box: settings.boxCustomTitle = value
                case .chrono: settings.chronoCustomTitle = value
                case .calendar: settings.calendarCustomTitle = value
                case .launcher: settings.launcherCustomTitle = value
                case .bookmarks: settings.bookmarksCustomTitle = value
                case .customCombined: settings.combinedCustomTitle = value
                }
            }
        )
    }

    private func pageShowTitleIconBinding(_ page: IslandPage) -> Binding<Bool> {
        Binding(
            get: {
                switch page {
                case .clipboard: return settings.clipboardShowTitleIcon ?? true
                case .jot: return settings.jotShowTitleIcon ?? true
                case .box: return settings.boxShowTitleIcon ?? true
                case .chrono: return settings.chronoShowTitleIcon ?? true
                case .calendar: return settings.calendarShowTitleIcon ?? true
                case .launcher: return settings.launcherShowTitleIcon ?? true
                case .bookmarks: return settings.bookmarksShowTitleIcon ?? true
                case .customCombined: return settings.combinedShowTitleIcon ?? true
                }
            },
            set: { newValue in
                switch page {
                case .clipboard: settings.clipboardShowTitleIcon = newValue
                case .jot: settings.jotShowTitleIcon = newValue
                case .box: settings.boxShowTitleIcon = newValue
                case .chrono: settings.chronoShowTitleIcon = newValue
                case .calendar: settings.calendarShowTitleIcon = newValue
                case .launcher: settings.launcherShowTitleIcon = newValue
                case .bookmarks: settings.bookmarksShowTitleIcon = newValue
                case .customCombined: settings.combinedShowTitleIcon = newValue
                }
            }
        )
    }

    private func setPreviewFocus(_ focus: HoverPreviewFocus, isEditing: Bool) {
        settings.hoverPreviewFocus = isEditing ? focus : .all
    }

    private func setTitlePreviewFocus(isEditing: Bool, page: IslandPage? = nil) {
        if let page {
            settings.hoverPreviewTitlePage = page
        }
        setPreviewFocus(.titleSize, isEditing: isEditing)
    }

    private func titlePageLabel(_ page: IslandPage) -> String {
        switch page {
        case .clipboard: return "Clipboard"
        case .jot: return "Jot"
        case .box: return "Box"
        case .chrono: return "Chrono"
        default: return "Custom"
        }
    }

    private func pageTitleAlignmentBinding(_ page: IslandPage) -> Binding<Int> {
        Binding(
            get: { settings.titleAlignment(for: page).rawValue },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleAlignment = newValue
                case .jot:
                    settings.jotTitleAlignment = newValue
                case .box:
                    settings.boxTitleAlignment = newValue
                case .chrono:
                    settings.chronoTitleAlignment = newValue
                case .calendar:
                    settings.calendarTitleAlignment = newValue
                case .launcher:
                    settings.launcherTitleAlignment = newValue
                case .bookmarks:
                    settings.bookmarksTitleAlignment = newValue
                case .customCombined:
                    settings.combinedTitleAlignment = newValue
                }
            }
        )
    }

    private func pageTitleSizeBinding(_ page: IslandPage) -> Binding<CGFloat> {
        Binding(
            get: { settings.titleSize(for: page) },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleSize = newValue
                case .jot:
                    settings.jotTitleSize = newValue
                case .box:
                    settings.boxTitleSize = newValue
                case .chrono:
                    settings.chronoTitleSize = newValue
                case .calendar:
                    settings.calendarTitleSize = newValue
                case .launcher:
                    settings.launcherTitleSize = newValue
                case .bookmarks:
                    settings.bookmarksTitleSize = newValue
                case .customCombined:
                    settings.combinedTitleSize = newValue
                }
            }
        )
    }

    private func pageTitleColorBinding(_ page: IslandPage) -> Binding<Color> {
        Binding(
            get: { Color(settings.titleColor(for: page)) },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleColor = NSColor(newValue)
                case .jot:
                    settings.jotTitleColor = NSColor(newValue)
                case .box:
                    settings.boxTitleColor = NSColor(newValue)
                case .chrono:
                    settings.chronoTitleColor = NSColor(newValue)
                case .calendar:
                    settings.calendarTitleColor = NSColor(newValue)
                case .launcher:
                    settings.launcherTitleColor = NSColor(newValue)
                case .bookmarks:
                    settings.bookmarksTitleColor = NSColor(newValue)
                case .customCombined:
                    settings.combinedTitleColor = NSColor(newValue)
                }
            }
        )
    }

    private func pageTitleUseAccentBinding(_ page: IslandPage) -> Binding<Bool> {
        Binding(
            get: {
                switch page {
                case .clipboard:
                    return settings.clipboardTitleUseAccent ?? false
                case .jot:
                    return settings.jotTitleUseAccent ?? false
                case .box:
                    return settings.boxTitleUseAccent ?? false
                case .chrono:
                    return settings.chronoTitleUseAccent ?? false
                case .calendar:
                    return settings.calendarTitleUseAccent ?? false
                case .launcher:
                    return settings.launcherTitleUseAccent ?? false
                case .bookmarks:
                    return settings.bookmarksTitleUseAccent ?? false
                case .customCombined:
                    return settings.combinedTitleUseAccent ?? false
                }
            },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleUseAccent = newValue
                case .jot:
                    settings.jotTitleUseAccent = newValue
                case .box:
                    settings.boxTitleUseAccent = newValue
                case .chrono:
                    settings.chronoTitleUseAccent = newValue
                case .calendar:
                    settings.calendarTitleUseAccent = newValue
                case .launcher:
                    settings.launcherTitleUseAccent = newValue
                case .bookmarks:
                    settings.bookmarksTitleUseAccent = newValue
                case .customCombined:
                    settings.combinedTitleUseAccent = newValue
                }
            }
        )
    }

    private func pageTitleSymbolBinding(_ page: IslandPage) -> Binding<String> {
        Binding(
            get: {
                switch page {
                case .clipboard:
                    return settings.clipboardTitleIconName ?? ""
                case .jot:
                    return settings.jotTitleIconName ?? ""
                case .box:
                    return settings.boxTitleIconName ?? ""
                case .chrono:
                    return settings.chronoTitleIconName ?? ""
                case .calendar:
                    return settings.calendarTitleIconName ?? ""
                case .launcher:
                    return settings.launcherTitleIconName ?? ""
                case .bookmarks:
                    return settings.bookmarksTitleIconName ?? ""
                case .customCombined:
                    return settings.combinedTitleIconName ?? ""
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmed.isEmpty ? nil : trimmed
                switch page {
                case .clipboard:
                    settings.clipboardTitleIconName = value
                case .jot:
                    settings.jotTitleIconName = value
                case .box:
                    settings.boxTitleIconName = value
                case .chrono:
                    settings.chronoTitleIconName = value
                case .calendar:
                    settings.calendarTitleIconName = value
                case .launcher:
                    settings.launcherTitleIconName = value
                case .bookmarks:
                    settings.bookmarksTitleIconName = value
                case .customCombined:
                    settings.combinedTitleIconName = value
                }
            }
        )
    }

    private func resetTitleOverrides(for page: IslandPage) {
        switch page {
        case .clipboard:
            settings.clipboardTitleAlignment = nil
            settings.clipboardTitleSize = nil
            settings.clipboardTitleIconName = nil
            settings.clipboardTitleUseAccent = nil
            settings.clipboardTitleColor = nil
        case .jot:
            settings.jotTitleAlignment = nil
            settings.jotTitleSize = nil
            settings.jotTitleIconName = nil
            settings.jotTitleUseAccent = nil
            settings.jotTitleColor = nil
        case .box:
            settings.boxTitleAlignment = nil
            settings.boxTitleSize = nil
            settings.boxTitleIconName = nil
            settings.boxTitleUseAccent = nil
            settings.boxTitleColor = nil
        case .chrono:
            settings.chronoTitleAlignment = nil
            settings.chronoTitleSize = nil
            settings.chronoTitleIconName = nil
            settings.chronoTitleUseAccent = nil
            settings.chronoTitleColor = nil
        case .calendar:
            settings.calendarTitleAlignment = nil
            settings.calendarTitleSize = nil
            settings.calendarTitleIconName = nil
            settings.calendarTitleUseAccent = nil
            settings.calendarTitleColor = nil
        case .launcher:
            settings.launcherTitleAlignment = nil
            settings.launcherTitleSize = nil
            settings.launcherTitleIconName = nil
            settings.launcherTitleUseAccent = nil
            settings.launcherTitleColor = nil
        case .bookmarks:
            settings.bookmarksTitleAlignment = nil
            settings.bookmarksTitleSize = nil
            settings.bookmarksTitleIconName = nil
            settings.bookmarksTitleUseAccent = nil
            settings.bookmarksTitleColor = nil
        case .customCombined:
            settings.combinedTitleAlignment = nil
            settings.combinedTitleSize = nil
            settings.combinedTitleIconName = nil
            settings.combinedTitleUseAccent = nil
            settings.combinedTitleColor = nil
        }
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                settings.observedFolders.append(url.path)
            }
        }
    }

    private func openFolderSlotsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: "folder_bookmark_\(url.path)")
            }
            
            DispatchQueue.main.async {
                settings.folderSlotsPaths.append(url.path)
            }
        }
    }
}
