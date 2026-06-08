
import SwiftUI

extension UnifiedNotchContainer {
    func chronoPage(contentAreaHeight: CGFloat) -> some View {
        ChronoPageContent(
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            isStopwatchRunning: model.isStopwatchRunning,
            stopwatchAccumulatedTime: model.stopwatchAccumulatedTime,
            stopwatchStartTime: model.stopwatchStartTime,
            isTimerRunning: model.isTimerRunning,
            timerDuration: model.timerDuration,
            timerRemainingAtPause: model.timerRemainingAtPause,
            timerEndTime: model.timerEndTime,
            isVisible: (model.isExpanded || model.isPinned) && activePages.indices.contains(model.currentPage) && activePages[model.currentPage] == .chrono,
            toggleStopwatch: toggleStopwatch,
            resetStopwatch: resetStopwatch,
            toggleTimer: toggleTimer,
            resetTimer: resetTimer,
            setTimerDuration: { model.timerDuration = $0 }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    // MARK: - Chrono Live Activity Widgets

    @ViewBuilder
    func closedIslandChronoWidgets(islandWidth: CGFloat, islandHeight: CGFloat, leftExt: CGFloat, rightExt: CGFloat) -> some View {
        if !settings.chronoEnabled || settings.disableChronoHUD {
            EmptyView()
        } else {
            let showStopwatch = model.isStopwatchRunning
            let showTimer = model.isTimerRunning

            if showStopwatch || showTimer {
                Color.clear
                    .overlay(alignment: .topLeading) {
                        GeometryReader { geo in
                            let hardwareCenter = geo.size.width / 2 - ((rightExt - leftExt) / 2)
                            let hardwareLeft = hardwareCenter - (settings.effectiveNotchWidth / 2)
                            let hardwareRight = hardwareCenter + (settings.effectiveNotchWidth / 2)
                            
                            if showStopwatch {
                                chronoStopwatchWidget
                                    .frame(width: leftExt, height: islandHeight)
                                    .offset(x: hardwareLeft - leftExt, y: 0)
                            }
                            
                            if showTimer {
                                chronoTimerWidget
                                    .frame(width: rightExt, height: islandHeight)
                                    .offset(x: hardwareRight, y: 0)
                            }
                        }
                    }
                    .frame(width: islandWidth, height: islandHeight)
            }
        }
    }
    
    private var chronoStopwatchWidget: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(formatCompactChrono(stopwatchElapsed(for: context.date)))
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var chronoTimerWidget: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(formatCompactChrono(timerRemaining(for: context.date)))
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Logic Helpers

    private func stopwatchElapsed(for date: Date) -> TimeInterval {
        let activeTime = model.isStopwatchRunning ? date.timeIntervalSinceReferenceDate - (model.stopwatchStartTime ?? date.timeIntervalSinceReferenceDate) : 0
        return model.stopwatchAccumulatedTime + activeTime
    }

    private func timerRemaining(for date: Date) -> TimeInterval {
        let remaining = model.isTimerRunning ? max(0, (model.timerEndTime ?? date.timeIntervalSinceReferenceDate) - date.timeIntervalSinceReferenceDate) : model.timerRemainingAtPause
        return remaining
    }

    private func formatCompactChrono(_ time: TimeInterval) -> String {
        let totalS = Int(time)
        let s = totalS % 60
        let m = (totalS / 60) % 60
        let h = totalS / 3600
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else if m > 0 {
            return String(format: "%d:%02d", m, s)
        } else {
            return String(format: "%d", s)
        }
    }

    private func toggleStopwatch() {
        if model.isStopwatchRunning {
            model.stopwatchAccumulatedTime = stopwatchElapsed(for: Date())
            model.isStopwatchRunning = false
        } else {
            model.stopwatchStartTime = Date().timeIntervalSinceReferenceDate
            model.isStopwatchRunning = true
        }
    }

    private func resetStopwatch() {
        model.stopwatchAccumulatedTime = 0
        model.stopwatchStartTime = nil
        model.isStopwatchRunning = false
    }

    private func toggleTimer() {
        if model.isTimerRunning {
            model.timerRemainingAtPause = timerRemaining(for: Date())
            model.isTimerRunning = false
        } else {
            if model.timerRemainingAtPause == 0 && model.timerDuration > 0 {
                model.timerRemainingAtPause = model.timerDuration
            }
            model.timerEndTime = Date().timeIntervalSinceReferenceDate + model.timerRemainingAtPause
            model.isTimerRunning = true
        }
    }

    private func resetTimer() {
        model.timerRemainingAtPause = 0
        model.timerEndTime = nil
        model.isTimerRunning = false
    }
}
