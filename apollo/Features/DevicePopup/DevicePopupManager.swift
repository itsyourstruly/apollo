import SwiftUI
import AppKit
import Combine
import CoreAudio
import IOBluetooth

// MARK: - Models

public enum DeviceCategory {
    case bluetoothHeadphones
    case airpods
    case wiredAudio
    case externalStorage
    case genericBluetooth
}

public struct DeviceDetails: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let sfSymbol: String
    public let deviceType: DeviceCategory
    public let batteryLevel: Double?        // 0.0 to 1.0
    public let isCurrentAudioOutput: Bool?
    public let fileURL: URL?
    public let audioDeviceID: UInt32?
    
    public init(id: UUID = UUID(), name: String, sfSymbol: String, deviceType: DeviceCategory, batteryLevel: Double? = nil, isCurrentAudioOutput: Bool? = nil, fileURL: URL? = nil, audioDeviceID: UInt32? = nil) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.deviceType = deviceType
        self.batteryLevel = batteryLevel
        self.isCurrentAudioOutput = isCurrentAudioOutput
        self.fileURL = fileURL
        self.audioDeviceID = audioDeviceID
    }
}

public enum NotchSystemPopupState: Equatable {
    case idle
    case connected(DeviceDetails)
}

// MARK: - Device Popup Window

class DevicePopupWindow: NSPanel {
    var onSwipeUp: (() -> Void)?
    
    override func scrollWheel(with event: NSEvent) {
        let fingerDeltaY = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        if fingerDeltaY > 5 {
            onSwipeUp?()
            return
        }
        super.scrollWheel(with: event)
    }
    
    override func swipe(with event: NSEvent) {
        if event.deltaY > 0 {
            onSwipeUp?()
            return
        }
        super.swipe(with: event)
    }
}

// MARK: - View Model / Manager

@MainActor
public class DevicePopupManager: ObservableObject {
    public static let shared = DevicePopupManager()
    
    @Published public var state: NotchSystemPopupState = .idle
    @Published public var currentOutputDeviceID: AudioDeviceID = 0
    private var dismissalTask: Task<Void, Never>?
    private var popupWindow: NSPanel?
    
    private var cancellables = Set<AnyCancellable>()
    
    // Hardware state caching
    private var knownAudioDeviceIDs = Set<AudioDeviceID>()
    private var knownDataSources = [AudioDeviceID: UInt32]()
    private var btObserver: BluetoothObserver?
    private var storageObserverToken: NSObjectProtocol?
    private var isAudioListenerSetup = false
    
    private init() {
    }
    
    public func start() {
        // Invoked at app launch to instantiate singleton and attach listeners
        setupAudioListener()
        
        AppSettings.shared.$devicePopupBluetoothEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.setupBluetoothListener()
                } else {
                    self?.stopBluetoothListener()
                }
            }
            .store(in: &cancellables)
            
        AppSettings.shared.$devicePopupStorageEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.setupStorageListener()
                } else {
                    self?.stopStorageListener()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 1. CoreAudio Listener (USB-C & AUX 3.5mm Earbuds)
    
    private func setupAudioListener() {
        guard !isAudioListenerSetup else { return }
        isAudioListenerSetup = true
        
        self.knownAudioDeviceIDs = fetchAudioDevices()
        self.currentOutputDeviceID = getDefaultOutputDevice()
        
        // Hook 1: Listen for global USB-C / Thunderbolt audio interfaces
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(UInt32(kAudioObjectSystemObject), &propertyAddress, .main) { [weak self] _, _ in
            self?.handleAudioDeviceListChange()
        }
        
        // Hook 2: Listen for 3.5mm AUX inserts on existing hardware ports
        for deviceID in knownAudioDeviceIDs {
            if isOutputDevice(deviceID) {
                hookDataSourceListener(for: deviceID)
            }
        }
        
        // Hook 3: Listen for Default Output Device changes
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(UInt32(kAudioObjectSystemObject), &defaultOutputAddress, .main) { [weak self] _, _ in
            guard let self = self else { return }
            let newID = self.getDefaultOutputDevice()
            DispatchQueue.main.async {
                self.currentOutputDeviceID = newID
            }
        }
    }
    
    private func handleAudioDeviceListChange() {
        guard AppSettings.shared.devicePopupWiredEnabled else { return }
        
        let currentDevices = fetchAudioDevices()
        let addedDevices = currentDevices.subtracting(knownAudioDeviceIDs)
        knownAudioDeviceIDs = currentDevices
        
        for deviceID in addedDevices {
            if isOutputDevice(deviceID) {
                hookDataSourceListener(for: deviceID)
                
                let name = getAudioDeviceName(deviceID)
                let lowerName = name.lowercased()
                
                // Ignore internal generic speaker re-initializations
                if lowerName.contains("built-in") || lowerName.contains("macbook") || lowerName.contains("imac") || lowerName.contains("mac mini") {
                    continue
                }
                
                let isHeadphones = lowerName.contains("headphone") || lowerName.contains("earbud") || lowerName.contains("audio")
                let symbol = isHeadphones ? "headphones" : "hifispeaker.fill"
                
                let device = DeviceDetails(name: name, sfSymbol: symbol, deviceType: .wiredAudio, isCurrentAudioOutput: false, audioDeviceID: deviceID)
                self.presentPopup(for: device)
            }
        }
    }
    
    private func hookDataSourceListener(for deviceID: AudioDeviceID) {
        guard knownDataSources[deviceID] == nil else { return }
        knownDataSources[deviceID] = getDeviceDataSource(deviceID)
        
        var dsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(deviceID, &dsAddress, .main) { [weak self] _, _ in
            self?.handleDataSourceChange(for: deviceID)
        }
    }
    
    private func handleDataSourceChange(for deviceID: AudioDeviceID) {
        guard AppSettings.shared.devicePopupWiredEnabled else { return }
        
        let newSource = getDeviceDataSource(deviceID)
        let oldSource = knownDataSources[deviceID]
        knownDataSources[deviceID] = newSource
        
        // If the data source shifted from Internal Speaker to AUX Earbuds
        if newSource != oldSource && newSource != 0 {
            let codeString = stringFromFourCC(newSource).lowercased()
            if codeString.contains("hdpn") || codeString.contains("head") {
                let device = DeviceDetails(name: "Headphones", sfSymbol: "headphones", deviceType: .wiredAudio, isCurrentAudioOutput: true, audioDeviceID: deviceID)
                self.presentPopup(for: device)
            }
        }
    }
    
    // MARK: - 2. IOBluetooth Listener (AirPods & Wireless Devices)
    
    private func setupBluetoothListener() {
        if btObserver == nil {
            btObserver = BluetoothObserver()
            btObserver?.onConnect = { [weak self] device in
                let name = device.name ?? "Bluetooth Device"
                guard !name.isEmpty else { return }
                
                let isAudio = device.deviceClassMajor == kBluetoothDeviceClassMajorAudio
                let isAirPods = name.lowercased().contains("airpods")
                
                let category: DeviceCategory = isAirPods ? .airpods : (isAudio ? .bluetoothHeadphones : .genericBluetooth)
                let sfSymbol = isAirPods ? "airpodspro" : (isAudio ? "headphones.bluetooth" : "bluetooth")
                
                let details = DeviceDetails(name: name, sfSymbol: sfSymbol, deviceType: category)
                
                Task { @MainActor in
                    self?.presentPopup(for: details)
                }
            }
        }
        btObserver?.start()
    }
    
    private func stopBluetoothListener() {
        btObserver?.stop()
    }
    
    // MARK: - 3. NSWorkspace Listener (External Storage & SD Cards)
    
    private func setupStorageListener() {
        guard storageObserverToken == nil else { return }
        storageObserverToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let volumeURL = userInfo[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            
            let volumeName = userInfo["NSWorkspaceVolumeLocalizedNameKey"] as? String ?? volumeURL.lastPathComponent
            
            // Skip booting Macintosh HD / system mounts
            guard volumeURL.path != "/" && volumeURL.path.hasPrefix("/Volumes/") else { return }
            
            let device = DeviceDetails(name: volumeName, sfSymbol: "externaldrive.fill", deviceType: .externalStorage, fileURL: volumeURL)
            Task { @MainActor [weak self] in
                self?.presentPopup(for: device)
            }
        }
    }
    
    private func stopStorageListener() {
        if let token = storageObserverToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            storageObserverToken = nil
        }
    }
    
    // MARK: - Lifecycle Management
    
    /// Presents the popup natively and configures the automated dismissal sequence.
    public func presentPopup(for device: DeviceDetails) {
        guard AppSettings.shared.devicePopupEnabled else { return }
        
        // Immediately cleanly cancel any pending dismissal from a previous popup
        dismissalTask?.cancel()
        
        setupPopupWindowIfNeeded()
        
        // Play subtle connection sound
        if let pop = NSSound(named: "Pop"), !pop.isPlaying {
            pop.play()
        }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            self.state = .connected(device)
        }
        
        let delay = AppSettings.shared.devicePopupDelay
        
        // If 0, bypass auto-dismissal. Else, setup the safe asynchronous sleep operation.
        if delay > 0 {
            dismissalTask = Task {
                // Wait out the lifespan safely
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                // If the task was cancelled while sleeping (e.g. new device connected), bail out
                guard !Task.isCancelled else { return }
                
                // If we safely reach here, visually dismiss
                self.dismissManually()
            }
        }
    }
    
    /// Triggers an immediate UI takedown sequence
    public func dismissManually() {
        dismissalTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            self.state = .idle
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, self.state == .idle else { return }
            self.popupWindow?.orderOut(nil)
        }
    }
    
    /// Routes global CoreAudio Output directly to the specified accessory
    public func routeAudio(for device: DeviceDetails) {
        Task {
            var targetDeviceID: AudioDeviceID? = device.audioDeviceID
            
            if targetDeviceID == nil {
                // Retry loop for Bluetooth devices since CoreAudio registration lags behind IOBluetooth
                for _ in 0..<10 {
                    let devices = self.fetchAudioDevices()
                    for id in devices {
                        if self.isOutputDevice(id) {
                            let name = self.getAudioDeviceName(id)
                            if name.localizedCaseInsensitiveContains(device.name) || device.name.localizedCaseInsensitiveContains(name) {
                                targetDeviceID = id
                                break
                            }
                        }
                    }
                    if targetDeviceID != nil { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            
            if let id = targetDeviceID {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var newDeviceID = id
                let size = UInt32(MemoryLayout<AudioDeviceID>.size)
                
                // Set default output device (for music, media, etc.)
                AudioObjectSetPropertyData(UInt32(kAudioObjectSystemObject), &address, 0, nil, size, &newDeviceID)
                
                // Set default system output device (for UI sounds, alerts, etc.)
                address.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice
                AudioObjectSetPropertyData(UInt32(kAudioObjectSystemObject), &address, 0, nil, size, &newDeviceID)
            }
        }
    }
    
    private func setupPopupWindowIfNeeded() {
        if popupWindow == nil {
            let rect = NSRect(x: 0, y: 0, width: 400, height: 160)
            let panel = DevicePopupWindow(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .statusBar + 3
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onSwipeUp = { [weak self] in
                self?.dismissManually()
            }
            
            let hostingView = NSHostingView(rootView: NotchExpansionPopupView())
            hostingView.autoresizingMask = [.width, .height]
            hostingView.sizingOptions = [] // Disables constraint wrestling loop
            if #available(macOS 11.0, *) {
                hostingView.safeAreaRegions = []
            }
            panel.contentView = hostingView
            popupWindow = panel
        }
        
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.screens.first {
            let notchX = AppSettings.shared.hardwareNotchX
            let notchW = AppSettings.shared.hardwareNotchWidth
            let windowW: CGFloat = 400
            let windowH: CGFloat = 160
            let windowX = notchX - (windowW - notchW) / 2
            let windowY = screen.frame.maxY - windowH
            popupWindow?.setFrame(NSRect(x: windowX, y: windowY, width: windowW, height: windowH), display: true)
        }
        
        popupWindow?.orderFrontRegardless()
    }
    
    // MARK: - CoreAudio Utility Functions
    
    public func isDeviceCurrentOutput(_ device: DeviceDetails) -> Bool {
        if device.isCurrentAudioOutput == true { return true }
        let defaultID = currentOutputDeviceID
        if defaultID == 0 { return false }
        if let id = device.audioDeviceID, id == defaultID { return true }
        
        // Bluetooth devices take a moment to get an audioDeviceID, so dynamically match by name
        if device.deviceType == .bluetoothHeadphones || device.deviceType == .airpods {
            let defaultName = getAudioDeviceName(defaultID)
            if defaultName.localizedCaseInsensitiveContains(device.name) || device.name.localizedCaseInsensitiveContains(defaultName) {
                return true
            }
        }
        return false
    }
    
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(UInt32(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceID)
        return deviceID
    }
    
    private func fetchAudioDevices() -> Set<AudioDeviceID> {
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(UInt32(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else { return [] }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(UInt32(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }
        return Set(deviceIDs)
    }
    
    private func getAudioDeviceName(_ deviceID: AudioDeviceID) -> String {
        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, ptr)
        }
        if status == noErr, let validName = name {
            return validName as String
        }
        return "Audio Device"
    }
    
    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var dataSize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }
    
    private func getDeviceDataSource(_ deviceID: AudioDeviceID) -> UInt32 {
        var dataSourceID: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &dataSourceID)
        return dataSourceID
    }
    
    private func stringFromFourCC(_ code: UInt32) -> String {
        let c1 = String(UnicodeScalar((code >> 24) & 255) ?? "?")
        let c2 = String(UnicodeScalar((code >> 16) & 255) ?? "?")
        let c3 = String(UnicodeScalar((code >> 8) & 255) ?? "?")
        let c4 = String(UnicodeScalar(code & 255) ?? "?")
        return c1 + c2 + c3 + c4
    }
}

// MARK: - SwiftUI User Interface

public struct NotchExpansionPopupView: View {
    @ObservedObject var manager = DevicePopupManager.shared
    @State private var activeDevice: DeviceDetails?
    @State private var dragOffset: CGFloat = 0
    
    public init() {}
    
    public var body: some View {
        let isConnected = manager.state != .idle
        let notchW = AppSettings.shared.effectiveNotchWidth
        let notchH = AppSettings.shared.effectiveNotchHeight
        let targetW: CGFloat = 360
        let targetH: CGFloat = notchH + 64
        
        ZStack(alignment: .top) {
            Color.clear // Provides stable structural dimensions to prevent AppKit constraint loop crashes
            
            ZStack(alignment: .top) {
                BottomRoundedRectangle(cornerRadius: isConnected ? 24 : 12)
                    .fill(Color(AppSettings.shared.backgroundColor))
                    .shadow(color: Color.black.opacity(isConnected ? 0.35 : 0), radius: 24, x: 0, y: 12)
                
                if let device = activeDevice {
                    HStack(spacing: 16) {
                        Image(systemName: device.sfSymbol)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            if let battery = device.batteryLevel {
                                HStack(spacing: 4) {
                                    Image(systemName: batteryGlyph(for: battery))
                                        .foregroundColor(battery > 0.20 ? .green : .red)
                                        .font(.system(size: 11, weight: .medium))
                                    Text("\(Int(battery * 100))%")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                        }
                        
                        Spacer(minLength: 16)
                        
                        // Context-Driven Interactions
                        if [DeviceCategory.wiredAudio, .bluetoothHeadphones, .airpods].contains(device.deviceType) {
                            let isCurrent = manager.isDeviceCurrentOutput(device)
                            Button(action: {
                                if !isCurrent {
                                    manager.routeAudio(for: device)
                                    // Give macOS time to switch and the UI time to show "Switched"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        manager.dismissManually()
                                    }
                                } else {
                                    manager.dismissManually()
                                }
                            }) {
                                Text(isCurrent ? "Switched" : "Switch to")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isCurrent ? Color.blue.opacity(0.3) : Color.white.opacity(0.15))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isCurrent ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else if device.deviceType == .externalStorage, let url = device.fileURL {
                            Button(action: {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                                manager.dismissManually()
                            }) {
                                Image(systemName: "externaldrive.badge.plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .shadow(color: Color.blue.opacity(0.4), radius: 4, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, notchH + 14)
                    .padding(.bottom, 16)
                    .opacity(isConnected ? 1 : 0)
                    .blur(radius: isConnected ? 0 : 4)
                    .scaleEffect(isConnected ? 1.0 : 0.8, anchor: .top)
                }
            }
            .offset(y: dragOffset)
            .frame(width: isConnected ? targetW : notchW, height: isConnected ? targetH : notchH)
            .opacity(isConnected ? 1 : 0)
            .allowsHitTesting(isConnected)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isConnected)
            .onTapGesture {
                manager.dismissManually()
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height < 0 {
                            dragOffset = value.translation.height
                        } else {
                            dragOffset = value.translation.height * 0.15
                        }
                    }
                    .onEnded { value in
                        if value.translation.height < -15 || value.predictedEndTranslation.height < -50 {
                            manager.dismissManually()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
            )
        }
        .frame(width: 400, height: 160, alignment: .top)
        .onReceive(manager.$state) { newState in
            if case .connected(let device) = newState {
                activeDevice = device
            }
        }
    }
    
    private func batteryGlyph(for level: Double) -> String {
        if level >= 0.95 { return "battery.100" }
        if level >= 0.60 { return "battery.75" }
        if level >= 0.35 { return "battery.50" }
        return "battery.25"
    }
}

// MARK: - External Object Sub-Observer

public class BluetoothObserver: NSObject {
    public var onConnect: ((IOBluetoothDevice) -> Void)?
    private var notification: IOBluetoothUserNotification?
    
    public func start() {
        if notification == nil {
            notification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        }
    }
    
    public func stop() {
        notification?.unregister()
        notification = nil
    }
    
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice?) {
        guard let device = device else { return }
        onConnect?(device)
    }
}