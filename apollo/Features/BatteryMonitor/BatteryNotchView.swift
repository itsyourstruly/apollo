import SwiftUI

struct BatteryNotchView: View {
    @EnvironmentObject var batteryMonitor: BatteryMonitor
    @ObservedObject var settings = AppSettings.shared

    @State private var pulseOpacity: Double = 0
    @State private var lowBatteryPulse: Double = 0
    @State private var animatedLevel: Double = 1.0

    var body: some View {
        GeometryReader { _ in
            let t = settings.batteryBarThickness
            let padding: CGFloat = 24
            let notchWidth = settings.effectiveNotchWidth
            let notchHeight = settings.effectiveNotchHeight
            
            let path = Path { p in
                p.move(to: CGPoint(x: padding - t/2, y: 0))
                p.addLine(to: CGPoint(x: padding - t/2, y: notchHeight + t/2))
                p.addLine(to: CGPoint(x: padding + notchWidth + t/2, y: notchHeight + t/2))
                p.addLine(to: CGPoint(x: padding + notchWidth + t/2, y: 0))
            }
            
            let glowRadius = t * 1.5
            let color = batteryColor
            
            ZStack {
                if settings.batteryBarShowGhostTrack {
                    path
                        .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: t, lineCap: .round, lineJoin: .round))
                }
                
                path
                    .trim(from: 0, to: CGFloat(animatedLevel))
                    .stroke(color, style: StrokeStyle(lineWidth: t, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(batteryMonitor.batteryLevel < 0.1 ? (0.2 + 0.8 * lowBatteryPulse) : 0.5), radius: glowRadius)
                    .shadow(color: color.opacity(0.8 * pulseOpacity), radius: glowRadius * 2)
            }
        }
        .onChange(of: batteryMonitor.batteryLevel) { _, newLevel in
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedLevel = newLevel
            }
        }
        .onChange(of: batteryMonitor.justPluggedIn) { _, pluggedIn in
            if pluggedIn {
                withAnimation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true)) {
                    pulseOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { pulseOpacity = 0.0 }
                }
            }
        }
        .onAppear {
            animatedLevel = batteryMonitor.batteryLevel
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                lowBatteryPulse = 1.0
            }
        }
    }
    
    private var batteryColor: Color {
        if batteryMonitor.powerState == .charging || batteryMonitor.powerState == .full {
            return Color(settings.batteryBarColorCharging)
        }
        if settings.batteryBarMatchLowPowerMode && batteryMonitor.isLowPowerModeEnabled {
            return .yellow
        }
        
        if settings.batteryBarColorMode == 0 {
            return Color(settings.accentColor)
        } else if settings.batteryBarColorMode == 1 {
            return Color(settings.batteryBarColor)
        } else {
            let level = batteryMonitor.batteryLevel
            if level < 0.20 {
                return Color(settings.batteryBarColor0to20)
            } else if level < 0.50 {
                return Color(settings.batteryBarColor20to50)
            } else if level < 0.75 {
                return Color(settings.batteryBarColor50to75)
            } else {
                return Color(settings.batteryBarColor75to100)
            }
        }
    }
}