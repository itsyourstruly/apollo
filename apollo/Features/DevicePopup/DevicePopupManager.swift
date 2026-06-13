import SwiftUI
import AppKit
import Combine
import CoreAudio
import CoreBluetooth
import IOBluetooth

// MARK: - Models

public enum DeviceCategory {
    case bluetoothHeadphones
    case airpods
    case wiredAudio
    case externalStorage
    case genericBluetooth
    case externalDisplay
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

    public init(id: UUID = UUID(), name: String, sfSymbol: String, deviceType: DeviceCategory,
                batteryLevel: Double? = nil, isCurrentAudioOutput: Bool? = nil,
                fileURL: URL? = nil, audioDeviceID: UInt32? = nil) {
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

    public var deviceDetails: DeviceDetails? {
        guard case .connected(let details) = self else {
            return nil
        }
        return details
    }
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

struct ProfilerDeviceDetails {
    var name: String?
    var leftBattery: String?
    var rightBattery: String?
    var caseBattery: String?
    
    func airpodsSymbol(for name: String) -> String {
        let lower = name.lowercased()
        
        if lower.contains("max") { return "airpods.max" }
        return "airpods.pro"
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

    // FIX: IOBluetooth's registerForConnectNotifications is silently broken on macOS Sonoma+ /
    // Tahoe due to TCC gating.  We keep a BluetoothObserver as a best-effort fallback for
    // cases where the user HAS granted Bluetooth permission, but pair it with a
    // CoreBluetooth-based observer (CBCentralManager) that reliably triggers the system TCC
    // prompt and fires delegate callbacks regardless of IOBluetooth state.
    private var btObserver: BluetoothObserver?
    private var btPollingTimer: Timer?
    private var connectedBluetoothMACs = Set<String>()

    private var storageObserverToken: NSObjectProtocol?
    private var storageUnmountObserverToken: NSObjectProtocol?
    private var screenObserverToken: NSObjectProtocol?
    private var knownScreensCount = 0
    private var isAudioListenerSetup = false
    private var isStartupPhase = true

    private init() {}

    public func start() {
        self.knownScreensCount = NSScreen.screens.count
        setupDisplayListener()
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

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.isStartupPhase = false
        }
    }

    // MARK: - 1. CoreAudio Listener (USB-C & AUX 3.5mm)

    private func setupAudioListener() {
        guard !isAudioListenerSetup else { return }
        isAudioListenerSetup = true

        self.knownAudioDeviceIDs = fetchAudioDevices()
        self.currentOutputDeviceID = getDefaultOutputDevice()

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(UInt32(kAudioObjectSystemObject), &propertyAddress, .main) { [weak self] _, _ in
            self?.handleAudioDeviceListChange()
        }

        for deviceID in knownAudioDeviceIDs where isOutputDevice(deviceID) {
            hookDataSourceListener(for: deviceID)
        }

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(UInt32(kAudioObjectSystemObject), &defaultOutputAddress, .main) { [weak self] _, _ in
            guard let self = self else { return }
            let newID = self.getDefaultOutputDevice()
            DispatchQueue.main.async { self.currentOutputDeviceID = newID }
        }
    }

    private func handleAudioDeviceListChange() {
        guard AppSettings.shared.devicePopupWiredEnabled else { return }
        let currentDevices = fetchAudioDevices()
        let addedDevices = currentDevices.subtracting(knownAudioDeviceIDs)
        let removedDevices = knownAudioDeviceIDs.subtracting(currentDevices)
        knownAudioDeviceIDs = currentDevices
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if case .connected(let details) = self.state, let currentID = details.audioDeviceID {
                if removedDevices.contains(currentID) {
                    self.dismissManually()
                }
            }
        }
        
        guard !isStartupPhase else { return }

        for deviceID in addedDevices where isOutputDevice(deviceID) {
            hookDataSourceListener(for: deviceID)
            let name = getAudioDeviceName(deviceID)
            let lowerName = name.lowercased()
            if lowerName.contains("built-in") || lowerName.contains("macbook") ||
               lowerName.contains("imac") || lowerName.contains("mac mini") ||
               lowerName.contains("iphone") || lowerName.contains("ipad") { continue }
               
            // Extract MAC from UID to check if it's a known Bluetooth device
            let uid = getAudioDeviceUID(deviceID) ?? ""
            var matchedMac: String? = nil
            for mac in connectedBluetoothMACs {
                let formattedMac = mac.uppercased().replacingOccurrences(of: ":", with: "-")
                if uid.uppercased().contains(formattedMac) {
                    matchedMac = mac
                    break
                }
            }

            // Prevent CoreAudio from triggering duplicate popups for Apple Bluetooth accessories
            if matchedMac == nil && (isGenericDeviceName(name) || lowerName.contains("airpods") || lowerName.contains("beats")) { continue }
            
            if let mac = matchedMac {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    var finalName = name
                    var symbol = "headphones"
                    var category = DeviceCategory.wiredAudio
                    
                    let details = await self.fetchSystemProfilerDeviceDetails(macAddress: mac)
                    if let details = details, let pName = details.name, !self.isGenericDeviceName(pName) {
                        finalName = pName
                    }
                    
                    let (cat, baseSymbol) = Self.getDeviceCategoryAndSymbol(for: nil, resolvedName: finalName, initialName: finalName)
                    let hasAppleBattery = details?.leftBattery != nil || details?.rightBattery != nil || details?.caseBattery != nil
                    let isBeats = finalName.lowercased().contains("beats")
                    
                    if (cat == .airpods || hasAppleBattery) && !isBeats {
                        category = .airpods
                        symbol = details?.airpodsSymbol(for: finalName) ?? "airpods.pro"
                    } else {
                        category = cat
                        symbol = baseSymbol
                    }
                    
                    let device = DeviceDetails(name: finalName, sfSymbol: symbol, deviceType: category,
                                               isCurrentAudioOutput: false, audioDeviceID: deviceID)
                    self.presentPopup(for: device)
                }
            } else {
                let transportType = self.getAudioDeviceTransportType(deviceID)
                let transportString = self.stringFromFourCC(transportType).lowercased()
                let isHDMIOrDP = transportString.contains("hdmi") || transportString.contains("dprt")
                
                let isEarbuds = lowerName.contains("earbud") || lowerName.contains("buds") || lowerName.contains("earphone") || lowerName.contains("in-ear") || lowerName.contains("tws")
                let isHeadphones = lowerName.contains("headphone") || lowerName.contains("audio") || lowerName.contains("headset")
                let isDisplay = isHDMIOrDP || lowerName.contains("display") || lowerName.contains("monitor") || lowerName.contains("tv") || NSScreen.screens.contains(where: { 
                    let screenName = $0.localizedName.lowercased()
                    return screenName.contains(lowerName) || lowerName.contains(screenName)
                })
                
                let symbol: String
                if isDisplay {
                    symbol = "display"
                } else if isEarbuds {
                    symbol = "earbuds"
                } else if isHeadphones {
                    symbol = "beats.headphones"
                } else {
                    symbol = "hifispeaker.fill"
                }
                let device = DeviceDetails(name: name, sfSymbol: symbol, deviceType: .wiredAudio,
                                           isCurrentAudioOutput: false, audioDeviceID: deviceID)
                presentPopup(for: device)
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
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if case .connected(let details) = self.state, details.audioDeviceID == deviceID, newSource != oldSource {
                let codeString = self.stringFromFourCC(newSource).lowercased()
                if !codeString.contains("hdpn") && !codeString.contains("head") {
                    self.dismissManually()
                }
            }
        }
        
        guard !isStartupPhase else { return }

        if newSource != oldSource && newSource != 0 {
            let name = getAudioDeviceName(deviceID).lowercased()
            // Prevent duplicate popups for AirPods via Audio hardware changes
            if name.contains("airpods") || name.contains("beats") { return }
            
            let codeString = stringFromFourCC(newSource).lowercased()
            if codeString.contains("hdpn") || codeString.contains("head") {
                let device = DeviceDetails(name: "Headphones", sfSymbol: "beats.headphones",
                                           deviceType: .wiredAudio, isCurrentAudioOutput: true,
                                           audioDeviceID: deviceID)
                presentPopup(for: device)
            }
        }
    }

    // MARK: - 2. Bluetooth Listeners

    private func setupBluetoothListener() {
        prePopulateConnectedDevices()
        setupIOBluetoothListener()
        startBluetoothPolling()
    }

    private func stopBluetoothListener() {
        btObserver?.stop()
        btObserver = nil
        btPollingTimer?.invalidate()
        btPollingTimer = nil
        connectedBluetoothMACs.removeAll()
    }

    private func prePopulateConnectedDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in paired {
            if device.isConnected(), let mac = device.addressString {
                connectedBluetoothMACs.insert(mac)
            }
        }
    }

    private func startBluetoothPolling() {
        btPollingTimer?.invalidate()
        btPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollBluetoothConnections()
            }
        }
    }

    private func pollBluetoothConnections() {
        guard !isStartupPhase else { return }
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        
        var currentlyConnected = Set<String>()
        for device in paired {
            guard let mac = device.addressString else { continue }
            if device.isConnected() {
                currentlyConnected.insert(mac)
                if !connectedBluetoothMACs.contains(mac) {
                    // Newly connected!
                    connectedBluetoothMACs.insert(mac)
                    handleDeviceConnected(device)
                }
            }
        }
        
        // Purge devices that disconnected to allow re-triggering later
        connectedBluetoothMACs.formIntersection(currentlyConnected)
    }

    private func setupIOBluetoothListener() {
        guard btObserver == nil else { return }
        btObserver = BluetoothObserver()
        btObserver?.onConnect = { [weak self] device in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isStartupPhase else { return }
                guard device.isConnected(), let mac = device.addressString else { return }
                
                if !self.connectedBluetoothMACs.contains(mac) {
                    self.connectedBluetoothMACs.insert(mac)
                    self.handleDeviceConnected(device)
                }
            }
        }
        btObserver?.start()
    }

    private func handleDeviceConnected(_ device: IOBluetoothDevice) {
        let macAddress = device.addressString ?? ""
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            NSLog("[ApolloBT] ====== NEW BLUETOOTH CONNECTION ======")
            NSLog("[ApolloBT] MAC Address: \(macAddress)")
            
            let rawName = device.name ?? "nil"
            let nameOrAddr = device.nameOrAddress ?? "nil"
            NSLog("[ApolloBT] 1. Initial device.name: \(rawName)")
            NSLog("[ApolloBT] 2. Initial device.nameOrAddress: \(nameOrAddr)")
            
            var pairedName = "nil"
            if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
               let match = paired.first(where: { $0.addressString == macAddress }) {
                pairedName = match.name ?? "nil"
            }
            NSLog("[ApolloBT] 3. Paired array match name: \(pairedName)")
            
            var plistName = "nil"
            if let pathName = self.getCustomBluetoothName(macAddress: macAddress) {
                plistName = pathName
            }
            NSLog("[ApolloBT] 4. Bluetooth.plist custom name: \(plistName)")
            
            // 1. Debounce Phase: Wait briefly (0.25s) to filter out instant teardown/phantom connections
            try? await Task.sleep(nanoseconds: 250_000_000)
            
            guard let currentDevice = IOBluetoothDevice(addressString: macAddress), currentDevice.isConnected() else {
                NSLog("[ApolloBT] Device disconnected during debounce. Aborting.")
                self.connectedBluetoothMACs.remove(macAddress)
                return
            }
            
            let postDebounceName = currentDevice.name ?? "nil"
            let postDebounceNameOrAddr = currentDevice.nameOrAddress ?? "nil"
            NSLog("[ApolloBT] 5. Post-debounce currentDevice.name: \(postDebounceName)")
            NSLog("[ApolloBT] 6. Post-debounce currentDevice.nameOrAddress: \(postDebounceNameOrAddr)")
            
            // 2. Name Resolution Phase
            var bestName = currentDevice.nameOrAddress ?? postDebounceName
            if bestName == "nil" || bestName.isEmpty { bestName = "Bluetooth Device" }
            
            // Priority 1: The native macOS preferences cache (where Settings app instantly reads from)
            if plistName != "nil", !plistName.isEmpty, !self.isGenericDeviceName(plistName) {
                bestName = plistName
                NSLog("[ApolloBT] Applied custom name from macOS Preferences: \(bestName)")
            }
            
            var profilerDetails: ProfilerDeviceDetails? = nil
            // Priority 2: System Profiler (Slow but 100% accurate for custom names without caching)
            if self.isGenericDeviceName(bestName) {
                NSLog("[ApolloBT] Post-debounce name is generic '\(bestName)'. Querying system_profiler...")
                profilerDetails = await self.fetchSystemProfilerDeviceDetails(macAddress: macAddress)
                if let pDetails = profilerDetails, let profilerName = pDetails.name, !self.isGenericDeviceName(profilerName) {
                    bestName = profilerName
                    NSLog("[ApolloBT] Found custom name from system_profiler: \(bestName)")
                } else {
                    NSLog("[ApolloBT] system_profiler returned generic or nil. Polling IOBluetoothDevice...")
                    for i in 0..<16 { // Poll for up to 8 seconds
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard let checkDevice = IOBluetoothDevice(addressString: macAddress), checkDevice.isConnected() else {
                            NSLog("[ApolloBT] Device disconnected during polling. Aborting.")
                            self.connectedBluetoothMACs.remove(macAddress)
                            return
                        }
                        
                        let freshName = checkDevice.nameOrAddress ?? checkDevice.name ?? "nil"
                        if freshName != "nil", !freshName.isEmpty, !self.isGenericDeviceName(freshName) {
                            bestName = freshName
                            NSLog("[ApolloBT] Found custom name during polling [\(i)]: \(bestName)")
                            break
                        }
                    }
                }
            } else {
                NSLog("[ApolloBT] Found custom name immediately: \(bestName)")
            }
            
            NSLog("[ApolloBT] FINAL Selected Name for UI: \(bestName)")
            
            let lowerName = bestName.lowercased()
            
            // Ignore Mac/iPhone connections as they aren't accessories
            if currentDevice.deviceClassMajor == kBluetoothDeviceClassMajorPhone ||
               currentDevice.deviceClassMajor == kBluetoothDeviceClassMajorComputer { 
                NSLog("[ApolloBT] Ignored due to device class.")
                return 
            }
            if lowerName.contains("iphone") || lowerName.contains("ipad") ||
               lowerName.contains("macbook") || lowerName.contains("imac") { 
                NSLog("[ApolloBT] Ignored due to name containing Apple device keywords.")
                return 
            }

            let (category, baseSymbol) = Self.getDeviceCategoryAndSymbol(for: currentDevice, resolvedName: bestName, initialName: rawName != "nil" ? rawName : bestName)
            var sfSymbol = baseSymbol
            var finalCategory = category
            
            if profilerDetails == nil {
                profilerDetails = await self.fetchSystemProfilerDeviceDetails(macAddress: macAddress)
            }
            
            let hasAppleBattery = profilerDetails?.leftBattery != nil || profilerDetails?.rightBattery != nil || profilerDetails?.caseBattery != nil
            let isBeats = bestName.lowercased().contains("beats")
            
            if (category == .airpods || hasAppleBattery) && !isBeats {
                finalCategory = .airpods
                sfSymbol = profilerDetails?.airpodsSymbol(for: bestName) ?? "airpods.pro"
            }

            let deviceID = UUID()
            let details = DeviceDetails(id: deviceID, name: bestName, sfSymbol: sfSymbol,
                                        deviceType: finalCategory, batteryLevel: nil)
            self.presentPopup(for: details)
            
            // 3. Live Connection Monitor: If the device disconnects while the popup is still showing
            // (e.g., user instantly puts AirPods back in the case), dismiss the popup immediately.
            Task { @MainActor [weak self] in
                while true {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard let self = self else { return }
                    
                    // Only keep monitoring if this specific device's popup is still visibly active
                    guard case .connected(let current) = self.state, current.id == deviceID else {
                        break
                    }
                    
                    if let checkDevice = IOBluetoothDevice(addressString: macAddress), !checkDevice.isConnected() {
                        NSLog("[ApolloBT] Device disconnected while popup showing. Auto-dismissing.")
                        self.connectedBluetoothMACs.remove(macAddress)
                        self.dismissManually()
                        break
                    }
                }
            }
        }
    }

    private func isGenericDeviceName(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        
        // If it has an apostrophe/quote, it's definitely a user's custom name (e.g. "Amo's AirPods")
        if lower.contains("'") || lower.contains("’") || lower.contains("”") { return false }
        
        let exactGenerics: Set<String> = [
            "bluetooth device", "headphone", "headphones", "headset", "earbuds",
            "airpods", "airpods pro", "airpods max", 
            "magic mouse", "magic mouse 2", "magic keyboard", "magic trackpad", "magic trackpad 2"
        ]
        if exactGenerics.contains(lower) { return true }
        
        // Check for factory names with generation/suffix markers
        if lower.hasPrefix("airpods") && (lower.contains("generation") || lower.contains("find my")) { return true }
        if lower.hasPrefix("beats") && (lower.contains("studio") || lower.contains("solo") || lower.contains("fit") || lower.contains("flex")) { return true }
        if lower.hasPrefix("powerbeats") && lower.contains("pro") { return true }
        
        return false
    }

    private func getCustomBluetoothName(macAddress: String) -> String? {
        let targetMac = macAddress.uppercased().replacingOccurrences(of: ":", with: "-")
        
        // 1. Try UserDefaults Suite (Standard macOS location for custom Bluetooth names)
        if let defaults = UserDefaults(suiteName: "com.apple.Bluetooth"),
           let cache = defaults.dictionary(forKey: "DeviceCache") {
            for (key, value) in cache {
                let keyMac = key.uppercased().replacingOccurrences(of: ":", with: "-")
                if keyMac == targetMac {
                    if let deviceDict = value as? [String: Any], let name = deviceDict["Name"] as? String {
                        NSLog("[ApolloBT] Found custom name in UserDefaults: \(name)")
                        return name
                    }
                }
            }
        }
        
        // 2. Try User Preferences Plist (Fallback)
        let userPath = ("~/Library/Preferences/com.apple.Bluetooth.plist" as NSString).expandingTildeInPath
        if let dict = NSDictionary(contentsOfFile: userPath) as? [String: Any],
           let cache = dict["DeviceCache"] as? [String: Any] {
            for (key, value) in cache {
                let keyMac = key.uppercased().replacingOccurrences(of: ":", with: "-")
                if keyMac == targetMac {
                    if let deviceDict = value as? [String: Any], let name = deviceDict["Name"] as? String {
                        NSLog("[ApolloBT] Found custom name in User Plist: \(name)")
                        return name
                    }
                }
            }
        }
        
        // 3. Try System Preferences Plist (Fallback)
        let sysPath = "/Library/Preferences/com.apple.Bluetooth.plist"
        if let dict = NSDictionary(contentsOfFile: sysPath) as? [String: Any],
           let cache = dict["DeviceCache"] as? [String: Any] {
            for (key, value) in cache {
                let keyMac = key.uppercased().replacingOccurrences(of: ":", with: "-")
                if keyMac == targetMac {
                    if let deviceDict = value as? [String: Any], let name = deviceDict["Name"] as? String {
                        NSLog("[ApolloBT] Found custom name in System Plist: \(name)")
                        return name
                    }
                }
            }
        }
        
        NSLog("[ApolloBT] Plist fetch failed - could not find custom name for \(macAddress)")
        return nil
    }
    
    private func fetchSystemProfilerDeviceDetails(macAddress: String) async -> ProfilerDeviceDetails? {
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let btData = json["SPBluetoothDataType"] as? [[String: Any]] {
                    
                    let targetMac = macAddress.uppercased().replacingOccurrences(of: "-", with: ":")
                    
                    for section in btData {
                        if let details = await Self.extractDetailsFromProfiler(section["device_connected"], targetMac: targetMac) {
                            return details
                        }
                        if let details = await Self.extractDetailsFromProfiler(section["device_not_connected"], targetMac: targetMac) {
                            return details
                        }
                    }
                }
            } catch {
                NSLog("[ApolloBT] Profiler error: \(error)")
            }
            return nil
        }.value
    }
    
    private static func extractDetailsFromProfiler(_ devices: Any?, targetMac: String) -> ProfilerDeviceDetails? {
        guard let devices = devices else { return nil }
        
        let checkDict: ([String: Any]) -> ProfilerDeviceDetails? = { dict in
            for (name, details) in dict {
                if let detailsDict = details as? [String: Any] {
                    let addr = (detailsDict["device_address"] as? String)?.uppercased().replacingOccurrences(of: "-", with: ":")
                    if addr == targetMac {
                        var profilerDetails = ProfilerDeviceDetails()
                        profilerDetails.name = name
                        profilerDetails.leftBattery = detailsDict["device_batteryLevelLeft"] as? String
                        profilerDetails.rightBattery = detailsDict["device_batteryLevelRight"] as? String
                        profilerDetails.caseBattery = detailsDict["device_batteryLevelCase"] as? String
                        return profilerDetails
                    }
                }
            }
            return nil
        }
        
        if let arr = devices as? [[String: Any]] {
            for dict in arr {
                if let res = checkDict(dict) { return res }
            }
        } else if let dict = devices as? [String: Any] {
            return checkDict(dict)
        }
        return nil
    }

    // MARK: - Shared Helpers

    private static func getDeviceCategoryAndSymbol(for device: IOBluetoothDevice?, resolvedName: String, initialName: String) -> (DeviceCategory, String) {
        let lowerName = resolvedName.lowercased()
        let lowerInitial = initialName.lowercased()
        
        // 1. Check specific Apple/Beats branding via name (since they don't expose distinct classes from generic counterparts)
        if lowerName.contains("airpods max") || lowerInitial.contains("airpods max") {
            return (.bluetoothHeadphones, "airpods.max")
        } else if lowerName.contains("airpods pro") || lowerInitial.contains("airpods pro") {
            return (.airpods, "airpods.pro")
        } else if lowerName.contains("airpods") || lowerInitial.contains("airpods") {
            return (.airpods, "airpods.pro")
        } else if lowerName.contains("beats") || lowerInitial.contains("beats") {
            if lowerName.contains("fit") || lowerInitial.contains("fit") || lowerName.contains("flex") || lowerInitial.contains("flex") || lowerName.contains("powerbeats") || lowerInitial.contains("powerbeats") {
                return (.bluetoothHeadphones, "earbuds")
            } else {
                return (.bluetoothHeadphones, "beats.headphones")
            }
        }
        
        // 2. Basic name matching
        if lowerName.contains("mouse") || lowerInitial.contains("mouse") || lowerName.contains("trackpad") || lowerInitial.contains("trackpad") || lowerName.contains("mx master") || lowerInitial.contains("mx master") || lowerName.contains("mx anywhere") || lowerInitial.contains("mx anywhere") || lowerName.contains("trackball") || lowerInitial.contains("trackball") {
            return (.genericBluetooth, "computermouse.fill")
        } else if lowerName.contains("keyboard") || lowerInitial.contains("keyboard") {
            return (.genericBluetooth, "keyboard.fill")
        } else if lowerName.contains("speaker") || lowerInitial.contains("speaker") || lowerName.contains("bose") || lowerInitial.contains("bose") || lowerName.contains("sonos") || lowerInitial.contains("sonos") {
            return (.genericBluetooth, "hifispeaker.fill")
        } else if lowerName.contains("headphone") || lowerInitial.contains("headphone") || lowerName.contains("sony") || lowerInitial.contains("sony") || lowerName.contains("sennheiser") || lowerInitial.contains("sennheiser") {
            return (.bluetoothHeadphones, "beats.headphones")
        } else if lowerName.contains("earbud") || lowerInitial.contains("earbud") || lowerName.contains("jabra") || lowerInitial.contains("jabra") || lowerName.contains("buds") || lowerInitial.contains("buds") || lowerName.contains("earphone") || lowerInitial.contains("earphone") || lowerName.contains("in-ear") || lowerInitial.contains("in-ear") || lowerName.contains("tws") || lowerInitial.contains("tws") {
            return (.bluetoothHeadphones, "earbuds")
        } else if lowerName.contains("controller") || lowerInitial.contains("controller") || lowerName.contains("xbox") || lowerInitial.contains("xbox") || lowerName.contains("playstation") || lowerInitial.contains("playstation") {
            return (.genericBluetooth, "gamecontroller")
        } else if lowerName.contains("display") || lowerInitial.contains("display") || lowerName.contains("monitor") || lowerInitial.contains("monitor") || lowerName.contains("tv") || lowerInitial.contains("tv") {
            return (.genericBluetooth, "display")
        }
        
        // 3. Use the actual Bluetooth Device Class to determine the exact hardware type
        if let device = device {
            let major = device.deviceClassMajor
            let minor = device.deviceClassMinor
            
            if major == kBluetoothDeviceClassMajorAudio {
                if minor == 1 || minor == 2 {
                    return (.bluetoothHeadphones, "earbuds")
                } else if minor == 5 {
                    return (.genericBluetooth, "hifispeaker.fill")
                } else {
                    return (.bluetoothHeadphones, "beats.headphones")
                }
            } else if major == kBluetoothDeviceClassMajorPeripheral {
                let isKeyboard = (minor & 0x10) != 0
                let isPointer = (minor & 0x20) != 0
                let subtype = minor & 0x0F
                
                if isKeyboard && isPointer {
                    return (.genericBluetooth, "keyboard.fill")
                } else if isKeyboard {
                    return (.genericBluetooth, "keyboard.fill")
                } else if isPointer {
                    return (.genericBluetooth, "computermouse.fill")
                } else if subtype == 0x01 || subtype == 0x02 {
                    return (.genericBluetooth, "gamecontroller")
                } else {
                    return (.genericBluetooth, "computermouse.fill")
                }
            }
        }

        // 4. Ultimate fallback
        return (.genericBluetooth, "dot.radiowaves.left.and.right")
    }

    // MARK: - 3. External Listeners (Storage & Displays)

    private func setupStorageListener() {
        guard storageObserverToken == nil else { return }
        storageObserverToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let volumeURL = userInfo[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let volumeName = userInfo["NSWorkspaceVolumeLocalizedNameKey"] as? String
                ?? volumeURL.lastPathComponent
            
            Task { @MainActor [weak self] in
                guard let self = self, !self.isStartupPhase else { return }
                guard volumeURL.path != "/" && volumeURL.path.hasPrefix("/Volumes/") else { return }
                let device = DeviceDetails(name: volumeName, sfSymbol: "externaldrive.fill",
                                           deviceType: .externalStorage, fileURL: volumeURL)
                self.presentPopup(for: device)
            }
        }
        
        storageUnmountObserverToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let volumeURL = userInfo[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .connected(let details) = self.state, details.deviceType == .externalStorage, details.fileURL?.path == volumeURL.path {
                    self.dismissManually()
                }
            }
        }
    }

    private func stopStorageListener() {
        let nc = NSWorkspace.shared.notificationCenter
        if let token = storageObserverToken {
            nc.removeObserver(token)
            storageObserverToken = nil
        }
        if let token = storageUnmountObserverToken {
            nc.removeObserver(token)
            storageUnmountObserverToken = nil
        }
    }

    private func setupDisplayListener() {
        guard screenObserverToken == nil else { return }
        screenObserverToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenChange()
            }
        }
    }

    private func handleScreenChange() {
        guard AppSettings.shared.devicePopupWiredEnabled else {
            knownScreensCount = NSScreen.screens.count
            return
        }
        let currentScreens = NSScreen.screens
        let currentCount = currentScreens.count
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if currentCount > self.knownScreensCount, !self.isStartupPhase {
                if let newScreen = currentScreens.last {
                    let name = newScreen.localizedName
                    if case .connected(let currentDetails) = self.state, currentDetails.name == name { } else {
                        let device = DeviceDetails(name: name, sfSymbol: "display", deviceType: .externalDisplay)
                        self.presentPopup(for: device)
                    }
                }
            } else if currentCount < self.knownScreensCount {
                if case .connected(let details) = self.state, details.sfSymbol == "display" {
                    self.dismissManually()
                }
            }
            self.knownScreensCount = currentCount
        }
    }

    // MARK: - Lifecycle

    public func presentPopup(for device: DeviceDetails) {
        guard AppSettings.shared.devicePopupEnabled else { return }
        dismissalTask?.cancel()
        setupPopupWindowIfNeeded()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            self.state = .connected(device)
        }

        let delay = AppSettings.shared.devicePopupDelay
        if delay > 0 {
            dismissalTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.dismissManually()
            }
        }
    }

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

    public func routeAudio(for device: DeviceDetails) {
        Task {
            var targetDeviceID: AudioDeviceID? = device.audioDeviceID
            if targetDeviceID == nil {
                for _ in 0..<10 {
                    for id in self.fetchAudioDevices() where self.isOutputDevice(id) {
                        let name = self.getAudioDeviceName(id)
                        if name.localizedCaseInsensitiveContains(device.name) ||
                           device.name.localizedCaseInsensitiveContains(name) {
                            targetDeviceID = id; break
                        }
                    }
                    if targetDeviceID != nil { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            guard let id = targetDeviceID else { return }
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var newID = id
            let size = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioObjectSetPropertyData(UInt32(kAudioObjectSystemObject), &address, 0, nil, size, &newID)
            address.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice
            AudioObjectSetPropertyData(UInt32(kAudioObjectSystemObject), &address, 0, nil, size, &newID)
        }
    }

    private func setupPopupWindowIfNeeded() {
        if popupWindow == nil {
            let rect = NSRect(x: 0, y: 0, width: 400, height: 160)
            let panel = DevicePopupWindow(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .statusBar + 3
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onSwipeUp = { [weak self] in self?.dismissManually() }

            let hostingView = NSHostingView(rootView: NotchExpansionPopupView())
            hostingView.autoresizingMask = [.width, .height]
            hostingView.sizingOptions = []
            if #available(macOS 11.0, *) { hostingView.safeAreaRegions = [] }
            panel.contentView = hostingView
            popupWindow = panel
        }

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.screens.first {
            let notchX = AppSettings.shared.hardwareNotchX
            let notchW = AppSettings.shared.hardwareNotchWidth
            let windowW: CGFloat = 400, windowH: CGFloat = 160
            let windowX = notchX - (windowW - notchW) / 2
            let windowY = screen.frame.maxY - windowH
            popupWindow?.setFrame(NSRect(x: windowX, y: windowY, width: windowW, height: windowH), display: true)
        }
        popupWindow?.orderFrontRegardless()
    }

    // MARK: - CoreAudio Utilities

    public func isDeviceCurrentOutput(_ device: DeviceDetails) -> Bool {
        if device.isCurrentAudioOutput == true { return true }
        let defaultID = currentOutputDeviceID
        if defaultID == 0 { return false }
        if let id = device.audioDeviceID, id == defaultID { return true }
        if device.deviceType == .bluetoothHeadphones || device.deviceType == .airpods {
            let defaultName = getAudioDeviceName(defaultID)
            if defaultName.localizedCaseInsensitiveContains(device.name) ||
               device.name.localizedCaseInsensitiveContains(defaultName) { return true }
        }
        return false
    }

    private func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(UInt32(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &deviceID)
        return deviceID
    }

    private func fetchAudioDevices() -> Set<AudioDeviceID> {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(UInt32(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(UInt32(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &ids) == noErr else { return [] }
        return Set(ids)
    }

    private func getAudioDeviceName(_ deviceID: AudioDeviceID) -> String {
        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &dataSize, ptr)
        }
        if status == noErr, let n = name {
            return n as String
        }
        return "Audio Device"
    }
    
    private func getAudioDeviceTransportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &dataSize, &transportType)
        return transportType
    }

    private func getAudioDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &dataSize, ptr)
        }
        if status == noErr, let u = uid {
            return u as String
        }
        return nil
    }

    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var dataSize: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &dataSize) == noErr && dataSize > 0
    }

    private func getDeviceDataSource(_ deviceID: AudioDeviceID) -> UInt32 {
        var src: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &dataSize, &src)
        return src
    }

    private func stringFromFourCC(_ code: UInt32) -> String {
        [24, 16, 8, 0].map { shift -> String in
            let byte = (code >> shift) & 255
            return String(UnicodeScalar(byte) ?? "?")
        }.joined()
    }
}

// MARK: - IOBluetooth Observer (Supplementary Fallback)

public class BluetoothObserver: NSObject {
    public var onConnect: ((IOBluetoothDevice) -> Void)?
    private var notification: IOBluetoothUserNotification?

    public func start() {
        // FIX: On Tahoe, registerForConnectNotifications returns nil if the app has not been
        // granted Bluetooth access in System Settings > Privacy & Security > Bluetooth AND the
        // com.apple.security.device.bluetooth entitlement is present. There is no error thrown.
        // We log this condition in DEBUG builds to help diagnose permission issues.
        if notification == nil {
            notification = IOBluetoothDevice.register(
                forConnectNotifications: self,
                selector: #selector(deviceConnected(_:device:))
            )
            #if DEBUG
            if notification == nil {
                NSLog("[BluetoothObserver] registerForConnectNotifications returned nil. " +
                      "Check: 1) com.apple.security.device.bluetooth entitlement is set, " +
                      "2) Bluetooth permission granted in System Settings > Privacy & Security.")
            }
            #endif
        }
    }

    public func stop() {
        notification?.unregister()
        notification = nil
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification,
                                        device: IOBluetoothDevice?) {
        guard let device = device else { return }
        onConnect?(device)
    }
}

// MARK: - SwiftUI View

public struct NotchExpansionPopupView: View {
    @ObservedObject var manager = DevicePopupManager.shared
    @State private var activeDevice: DeviceDetails?
    @State private var dragOffset: CGFloat = 0
    @AppStorage("devicePopupUseAccentSymbols") private var useAccentSymbols = true

    public init() {}

    public var body: some View {
        let isConnected = manager.state != .idle
        let notchW = AppSettings.shared.effectiveNotchWidth
        let notchH = AppSettings.shared.effectiveNotchHeight
        let targetW: CGFloat = 360
        let targetH: CGFloat = notchH + 64

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                BottomRoundedRectangle(cornerRadius: isConnected ? 24 : 12)
                    .fill(Color(AppSettings.shared.backgroundColor))
                    .shadow(color: Color.black.opacity(isConnected ? 0.35 : 0), radius: 24, x: 0, y: 12)

                if let device = activeDevice {
                    HStack(spacing: 16) {
                        if device.deviceType == .genericBluetooth ||
                           device.deviceType == .externalDisplay ||
                           device.deviceType == .bluetoothHeadphones ||
                           device.deviceType == .airpods {
                            if let battery = device.batteryLevel {
                                VStack(spacing: 2) {
                                    Image(systemName: batteryGlyph(for: battery))
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(battery > 0.20 ? .green : .red)
                                    Text("\(Int(battery * 100))%")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 36, alignment: .center)
                                .transition(.scale.combined(with: .opacity))
                            } else {
                                if useAccentSymbols {
                                    Image(systemName: device.sfSymbol)
                                        .font(.system(size: 28, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color(AppSettings.shared.accentColor))
                                        .frame(width: 36, alignment: .center)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Image(systemName: device.sfSymbol)
                                        .font(.system(size: 28, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.white)
                                        .frame(width: 36, alignment: .center)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        } else {
                            if useAccentSymbols {
                                Image(systemName: device.sfSymbol)
                                    .font(.system(size: 28, weight: .semibold))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color(AppSettings.shared.accentColor))
                                    .frame(width: 36, alignment: .center)
                            } else {
                                Image(systemName: device.sfSymbol)
                                    .font(.system(size: 28, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, alignment: .center)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            if device.deviceType != .genericBluetooth &&
                               device.deviceType != .externalDisplay &&
                               device.deviceType != .bluetoothHeadphones &&
                               device.deviceType != .airpods {
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
                        }

                        Spacer(minLength: 16)

                        if [DeviceCategory.wiredAudio, .bluetoothHeadphones, .airpods].contains(device.deviceType) {
                            let isCurrent = manager.isDeviceCurrentOutput(device)
                            Button {
                                if !isCurrent {
                                    manager.routeAudio(for: device)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        manager.dismissManually()
                                    }
                                } else {
                                    manager.dismissManually()
                                }
                            } label: {
                                Text(isCurrent ? "Switched" : "Switch to")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isCurrent ? Color.blue.opacity(0.3) : Color.white.opacity(0.15))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(isCurrent ? Color.blue : Color.clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        } else if device.deviceType == .externalStorage, let url = device.fileURL {
                            Button {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                                manager.dismissManually()
                            } label: {
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
            .frame(width: isConnected ? targetW : notchW,
                   height: isConnected ? targetH : notchH)
            .opacity(isConnected ? 1 : 0)
            .allowsHitTesting(isConnected)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isConnected)
            .onTapGesture { manager.dismissManually() }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height < 0
                            ? value.translation.height
                            : value.translation.height * 0.15
                    }
                    .onEnded { value in
                        if value.translation.height < -15 || value.predictedEndTranslation.height < -50 {
                            manager.dismissManually()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragOffset = 0 }
                    }
            )
        }
        .frame(width: 400, height: 160, alignment: .top)
        .onReceive(manager.$state) { newState in
            if case .connected(let device) = newState { activeDevice = device }
        }
    }

    private func batteryGlyph(for level: Double) -> String {
        if level >= 0.95 { return "battery.100" }
        if level >= 0.60 { return "battery.75" }
        if level >= 0.35 { return "battery.50" }
        return "battery.25"
    }
}
