
import SwiftUI

// MARK: - Chrono Page
struct ChronoPageContent: View, Equatable {
    let width: CGFloat
    let height: CGFloat
    let isStopwatchRunning: Bool
    let stopwatchAccumulatedTime: TimeInterval
    let stopwatchStartTime: TimeInterval?
    let isTimerRunning: Bool
    let timerDuration: TimeInterval
    let timerRemainingAtPause: TimeInterval
    let timerEndTime: TimeInterval?
    let isVisible: Bool

    let toggleStopwatch: () -> Void
    let resetStopwatch: () -> Void
    let toggleTimer: () -> Void
    let resetTimer: () -> Void
    let setTimerDuration: (TimeInterval) -> Void

    static func == (lhs: ChronoPageContent, rhs: ChronoPageContent) -> Bool {
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.isStopwatchRunning == rhs.isStopwatchRunning &&
        lhs.stopwatchAccumulatedTime == rhs.stopwatchAccumulatedTime &&
        lhs.stopwatchStartTime == rhs.stopwatchStartTime &&
        lhs.isTimerRunning == rhs.isTimerRunning &&
        lhs.timerDuration == rhs.timerDuration &&
        lhs.timerRemainingAtPause == rhs.timerRemainingAtPause &&
        lhs.timerEndTime == rhs.timerEndTime &&
        lhs.isVisible == rhs.isVisible
    }

    var body: some View {
        HStack(spacing: 0) {
            stopwatchView
                .frame(maxWidth: .infinity)
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 12)
            
            timerView
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(width: width, height: height, alignment: .top)
    }

    private var stopwatchView: some View {
        VStack(spacing: 12) {
            if isStopwatchRunning {
                if isVisible {
                    TimelineView(.animation(minimumInterval: 0.05)) { context in
                        Text(formatStopwatch(stopwatchElapsed(for: context.date), includeMs: true))
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                } else {
                    Text(formatStopwatch(stopwatchElapsed(for: Date()), includeMs: false))
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            } else {
                Text(formatStopwatch(stopwatchAccumulatedTime, includeMs: true))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 24) {
                Button(action: toggleStopwatch) {
                    Image(systemName: isStopwatchRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(isStopwatchRunning ? .yellow : .green)
                }
                .buttonStyle(.plain)
                
                if !isStopwatchRunning && stopwatchAccumulatedTime > 0 {
                    Button(action: resetStopwatch) {
                        Image(systemName: "trash.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var timerView: some View {
        VStack(spacing: 12) {
            if isTimerRunning {
                if isVisible {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        Text(formatTimer(timerRemaining(for: context.date)))
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                } else {
                    Text(formatTimer(timerRemaining(for: Date())))
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            } else if timerDuration > 0 && timerRemainingAtPause > 0 {
                Text(formatTimer(timerRemainingAtPause))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            } else {
                TimerInputView(duration: Binding(get: { timerDuration }, set: setTimerDuration))
            }
            
            HStack(spacing: 24) {
                Button(action: toggleTimer) {
                    Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(isTimerRunning ? .yellow : .green)
                }
                .buttonStyle(.plain)
                .disabled(timerDuration == 0 && timerRemainingAtPause == 0)
                
                if !isTimerRunning && (timerRemainingAtPause > 0 || timerDuration > 0) {
                    Button(action: resetTimer) {
                        Image(systemName: "trash.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stopwatchElapsed(for date: Date) -> TimeInterval {
        let activeTime = isStopwatchRunning ? date.timeIntervalSinceReferenceDate - (stopwatchStartTime ?? date.timeIntervalSinceReferenceDate) : 0
        return stopwatchAccumulatedTime + activeTime
    }

    private func timerRemaining(for date: Date) -> TimeInterval {
        let remaining = isTimerRunning ? max(0, (timerEndTime ?? date.timeIntervalSinceReferenceDate) - date.timeIntervalSinceReferenceDate) : timerRemainingAtPause
        return remaining
    }

    private func formatStopwatch(_ time: TimeInterval, includeMs: Bool) -> String {
        let totalMs = Int(time * 100)
        let ms = totalMs % 100
        let s = (totalMs / 100) % 60
        let m = (totalMs / 6000) % 60
        let h = totalMs / 360000
        
        if h > 0 {
            return includeMs ? String(format: "%d:%02d:%02d.%02d", h, m, s, ms) : String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return includeMs ? String(format: "%02d:%02d.%02d", m, s, ms) : String(format: "%02d:%02d", m, s)
        }
    }

    private func formatTimer(_ time: TimeInterval) -> String {
        let totalS = Int(time)
        let s = totalS % 60
        let m = (totalS / 60) % 60
        let h = totalS / 3600
        
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
