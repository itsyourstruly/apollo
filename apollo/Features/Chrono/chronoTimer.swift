
import SwiftUI

struct TimerInputView: View {
    @Binding var duration: TimeInterval
    
    var hours: Int { Int(duration) / 3600 }
    var minutes: Int { (Int(duration) % 3600) / 60 }
    var seconds: Int { Int(duration) % 60 }
    
    var body: some View {
        HStack(spacing: 8) {
            TimerColumn(value: hours, maxLimit: 99, label: "H") { new in update(h: new, m: minutes, s: seconds) }
            Text(":").font(.title).foregroundColor(.white.opacity(0.5)).padding(.bottom, 6)
            TimerColumn(value: minutes, maxLimit: 59, label: "M") { new in update(h: hours, m: new, s: seconds) }
            Text(":").font(.title).foregroundColor(.white.opacity(0.5)).padding(.bottom, 6)
            TimerColumn(value: seconds, maxLimit: 59, label: "S") { new in update(h: hours, m: minutes, s: new) }
        }
    }
    
    func update(h: Int, m: Int, s: Int) {
        duration = TimeInterval(h * 3600 + m * 60 + s)
    }
}

struct TimerColumn: View {
    let value: Int
    let maxLimit: Int
    let label: String
    let onChange: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            Button(action: { onChange(min(maxLimit, value + 1)) }) {
                Image(systemName: "chevron.up")
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            
            TextField("", text: Binding(
                get: { String(format: "%02d", value) },
                set: { if let v = Int($0) { onChange(min(maxLimit, v)) } }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 26, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            
            Button(action: { onChange(Swift.max(0, value - 1)) }) {
                Image(systemName: "chevron.down")
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }
}
