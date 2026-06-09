import Foundation
import Combine
import IOKit.ps

public enum PowerState: String {
    case battery
    case charging
    case full
    case unknown
}

public class BatteryMonitor: ObservableObject {
    public static let shared = BatteryMonitor()
    
    @Published public var batteryLevel: Double = 1.0
    @Published public var isCharging: Bool = false
    @Published public var isPluggedIn: Bool = false
    @Published public var justPluggedIn: Bool = false
    @Published public var isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published public var powerState: PowerState = .unknown
    
    private var runLoopSource: CFRunLoopSource?
    
    private init() {
        setup()
        update()
    }
    
    private func setup() {
        // Use the UserNotifications.Battery API for battery state change notifications
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.update() // Update the battery monitor when the notification is received
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.update()
            }
        }, context).takeRetainedValue()
        
        if let rls = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), rls, .commonModes)
        }
    }
    
    public func update() {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        
        for ps in list {
            if let dict = IOPSGetPowerSourceDescription(blob, ps).takeUnretainedValue() as? [String: Any] {
                let currentCapacity = dict["Current Capacity"] as? Double ?? 0
                let maxCapacity = dict["Max Capacity"] as? Double ?? 100
                let isChargingNow = dict["Is Charging"] as? Bool ?? false
                let isChargedNow = dict["Is Charged"] as? Bool ?? false
                let powerSourceState = dict["Power Source State"] as? String ?? ""
                
                let level = maxCapacity > 0 ? (currentCapacity / maxCapacity) : 0
                self.batteryLevel = max(0.0, min(1.0, level))
                self.isCharging = isChargingNow
                
                let pluggedInNow = (powerSourceState == "AC Power")
                if pluggedInNow && !self.isPluggedIn {
                    self.justPluggedIn = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.justPluggedIn = false
                    }
                }
                self.isPluggedIn = pluggedInNow
                
                if pluggedInNow {
                    if self.isCharging {
                        self.powerState = .charging
                    } else if isChargedNow || self.batteryLevel == 1.0 {
                        self.powerState = .full
                    } else {
                        self.powerState = .charging
                    }
                } else if powerSourceState == "Battery Power" {
                    self.powerState = .battery
                } else {
                    self.powerState = .unknown
                }
                break
            }
        }
    }
}
