import SwiftUI
import AppKit
import EventKit
import Combine

extension EKEvent {
    var occurrenceIdentifier: String {
        let timeInterval = startDate?.timeIntervalSince1970 ?? 0
        return "\(eventIdentifier ?? "no-id")-\(timeInterval)"
    }
}

// MARK: - Calendar Manager
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    let eventStore = EKEventStore()
    @Published var permissionGranted = false
    @Published var permissionChecked = false
    @Published var events: [EKEvent] = []
    private var lastFetchTime: Date?
    private var activationObserver: NSObjectProtocol?
    
    init() {
        checkPermission()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPermission()
        }
    }

    deinit {
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func checkPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async {
            if status.rawValue == 3 {
                self.permissionGranted = true
                self.permissionChecked = true
                self.fetchEvents()
            } else if status == .notDetermined {
                self.permissionGranted = false
                self.permissionChecked = false
            } else {
                self.permissionGranted = false
                self.permissionChecked = true
            }
        }
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if #available(macOS 14.0, *) {
                    self.eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                        DispatchQueue.main.async {
                            self?.permissionGranted = granted
                            self?.permissionChecked = true
                            if granted {
                                self?.fetchEvents()
                            }
                            completion(granted)
                        }
                    }
                } else {
                    self.eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                        DispatchQueue.main.async {
                            self?.permissionGranted = granted
                            self?.permissionChecked = true
                            if granted {
                                self?.fetchEvents()
                            }
                            completion(granted)
                        }
                    }
                }
            }
        } else if status == .denied || status == .restricted {
            let urls = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                "x-apple.systempreferences:com.apple.preference.security"
            ]
            for urlString in urls {
                if let url = URL(string: urlString) {
                    if NSWorkspace.shared.open(url) {
                        break
                    }
                }
            }
            completion(false)
        } else {
            let granted = status.rawValue == 3
            completion(granted)
        }
    }
    
    func fetchEvents(force: Bool = false) {
        guard EKEventStore.authorizationStatus(for: .event).rawValue == 3 else { return }
        
        if !force, let lastFetch = lastFetchTime, Date().timeIntervalSince(lastFetch) < 300 {
            return
        }
        
        lastFetchTime = Date()
        
        let calendars = eventStore.calendars(for: .event)
        let now = Date()
        let calendar = Calendar.current
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let threeMonthsFuture = calendar.date(byAdding: .month, value: 3, to: now) ?? now
        
        let predicate = eventStore.predicateForEvents(withStart: oneMonthAgo, end: threeMonthsFuture, calendars: calendars)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fetched = self?.eventStore.events(matching: predicate) ?? []
            let sorted = fetched.sorted { $0.startDate < $1.startDate }
            DispatchQueue.main.async {
                self?.events = sorted
            }
        }
    }
}

// MARK: - Floating Calendar Panel
final class CalendarWidgetPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 230),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .mainMenu + 2 // Sit above standard windows and notch
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.contentView = contentView
    }
}

// MARK: - Month Grid View
struct MonthGridView: View {
    let month: Date
    @Binding var selectedDate: Date
    let events: [EKEvent]
    let accentColor: Color
    let weekStartsOn: Int

    private var daysInMonth: [Date?] {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsOn
        guard let monthRange = calendar.range(of: .day, in: .month, for: month),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        var offset = firstWeekday - calendar.firstWeekday
        if offset < 0 { offset += 7 }
        
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in 1...monthRange.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private var weekdaySymbols: [String] {
        if weekStartsOn == 2 {
            return ["M", "T", "W", "T", "F", "S", "S"]
        }
        return ["S", "M", "T", "W", "T", "F", "S"]
    }

    var body: some View {
        VStack(spacing: 6) {
            // Month Header
            Text(monthHeaderString)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
            
            // Weekday Headers
            HStack(spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days Grid
            let days = daysInMonth
            let rowsCount = days.count / 7
            
            VStack(spacing: 2) {
                ForEach(0..<rowsCount, id: \.self) { rowIndex in
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { colIndex in
                            let dayIndex = rowIndex * 7 + colIndex
                            if dayIndex < days.count, let date = days[dayIndex] {
                                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                let isToday = Calendar.current.isDateInToday(date)
                                let hasEvs = hasEvents(on: date)
                                
                                Button {
                                    selectedDate = date
                                } label: {
                                    VStack(spacing: 1) {
                                        Text("\(Calendar.current.component(.day, from: date))")
                                            .font(.system(size: 9, weight: isSelected || isToday ? .bold : .regular))
                                            .foregroundColor(isSelected ? .black : (isToday ? accentColor : .white))
                                        
                                        Circle()
                                            .fill(isSelected ? Color.black.opacity(0.7) : accentColor.opacity(0.8))
                                            .frame(width: 3, height: 3)
                                            .opacity(hasEvs ? 1.0 : 0.0)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.vertical, 2)
                                    .background(
                                        isSelected ? accentColor : (isToday ? Color.white.opacity(0.15) : Color.clear),
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
    }

    private var monthHeaderString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    private func hasEvents(on date: Date) -> Bool {
        let calendar = Calendar.current
        return events.contains { event in
            calendar.isDate(event.startDate, inSameDayAs: date)
        }
    }
}

// MARK: - Event Row
struct EventRow: View {
    let event: EKEvent
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.calendar.color != nil ? Color(nsColor: event.calendar.color) : accentColor)
                .frame(width: 3, height: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "No Title")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(formatEventTime(event))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
    }
    
    private func formatEventTime(_ event: EKEvent) -> String {
        if event.isAllDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }
}

// MARK: - Calendar Page Content
struct CalendarPageContent: View, Equatable {
    let width: CGFloat
    let height: CGFloat
    let accentColor: Color
    let calendarViewOption: Int
    let calendarWeekStartsOn: Int
    @ObservedObject private var manager = CalendarManager.shared
    
    static func == (lhs: CalendarPageContent, rhs: CalendarPageContent) -> Bool {
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.accentColor == rhs.accentColor &&
        lhs.calendarViewOption == rhs.calendarViewOption &&
        lhs.calendarWeekStartsOn == rhs.calendarWeekStartsOn &&
        lhs.manager.events.count == rhs.manager.events.count &&
        lhs.manager.events.first?.eventIdentifier == rhs.manager.events.first?.eventIdentifier &&
        lhs.manager.permissionGranted == rhs.manager.permissionGranted &&
        lhs.manager.permissionChecked == rhs.manager.permissionChecked
    }
    
    @State private var selectedDate = Date()
    @State private var floatingPanel: CalendarWidgetPanel?
    
    private var filteredEvents: [EKEvent] {
        let calendar = Calendar.current
        let dailyEvents = manager.events.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: selectedDate)
        }
        var seen = Set<String>()
        return dailyEvents.filter { event in
            seen.insert(event.occurrenceIdentifier).inserted
        }
    }

    private var currentWeekDays: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = calendarWeekStartsOn
        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        return (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: startOfWeek)
        }
    }

    private func hasEvents(on date: Date) -> Bool {
        let calendar = Calendar.current
        return manager.events.contains { event in
            calendar.isDate(event.startDate, inSameDayAs: date)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !manager.permissionChecked {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking calendar access...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !manager.permissionGranted {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Calendar access required")
                        .font(.caption)
                        .foregroundColor(.white)
                    Button {
                        manager.requestPermission { _ in }
                    } label: {
                        Text("Grant Access")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentColor, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if calendarViewOption == 0 {
                    // Month View
                    if width >= 340 {
                        // Side-by-Side View
                        HStack(spacing: 12) {
                            MonthGridView(month: Date(), selectedDate: $selectedDate, events: manager.events, accentColor: accentColor, weekStartsOn: calendarWeekStartsOn)
                                .frame(width: 170)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatSelectedDateTitle)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(accentColor)
                                
                                if filteredEvents.isEmpty {
                                    Text("No Events")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.4))
                                        .frame(maxHeight: .infinity, alignment: .center)
                                } else {
                                    ScrollView(.vertical, showsIndicators: false) {
                                        LazyVStack(spacing: 4) {
                                            ForEach(filteredEvents, id: \.occurrenceIdentifier) { event in
                                                EventRow(event: event, accentColor: accentColor)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .padding(.horizontal, 10)
                        .frame(width: width, height: height)
                        .onAppear {
                            closeFloatingWidget()
                        }
                    } else {
                        // Narrow Month View (Events inside notch, monthly grid floats to the left)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formatSelectedDateTitle)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(accentColor)
                                Spacer()
                                Button {
                                    toggleFloatingWidget()
                                } label: {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 10))
                                        .foregroundColor(floatingPanel != nil ? accentColor : .white.opacity(0.6))
                                        .padding(6)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if filteredEvents.isEmpty {
                                Text("No Events")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            } else {
                                ScrollView(.vertical, showsIndicators: false) {
                                    LazyVStack(spacing: 4) {
                                        ForEach(filteredEvents, id: \.occurrenceIdentifier) { event in
                                            EventRow(event: event, accentColor: accentColor)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(width: width, height: height)
                        .onAppear {
                            showFloatingWidget()
                        }
                        .onDisappear {
                            closeFloatingWidget()
                        }
                        .onChange(of: selectedDate) { _, _ in
                            // Auto-fetch events on selection
                        }
                    }
                } else {
                    // Week View
                    VStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(currentWeekDays, id: \.self) { date in
                                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                let isToday = Calendar.current.isDateInToday(date)
                                let hasEvs = hasEvents(on: date)
                                
                                Button {
                                    selectedDate = date
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(dayAbbreviation(for: date))
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundColor(isSelected ? .black : .white.opacity(0.5))
                                        
                                        Text("\(Calendar.current.component(.day, from: date))")
                                            .font(.system(size: 10, weight: isSelected || isToday ? .bold : .regular))
                                            .foregroundColor(isSelected ? .black : (isToday ? accentColor : .white))
                                        
                                        Circle()
                                            .fill(isSelected ? Color.black.opacity(0.7) : accentColor.opacity(0.8))
                                            .frame(width: 3, height: 3)
                                            .opacity(hasEvs ? 1.0 : 0.0)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(
                                        isSelected ? accentColor : (isToday ? Color.white.opacity(0.12) : Color.clear),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.horizontal, 8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if filteredEvents.isEmpty {
                                Text("No Events")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            } else {
                                ScrollView(.vertical, showsIndicators: false) {
                                    LazyVStack(spacing: 4) {
                                        ForEach(filteredEvents, id: \.occurrenceIdentifier) { event in
                                            EventRow(event: event, accentColor: accentColor)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                    }
                    .frame(width: width, height: height)
                    .onAppear {
                        closeFloatingWidget()
                    }
                }
            }
        }
        .onAppear {
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                manager.requestPermission { _ in
                    manager.checkPermission()
                }
            } else {
                manager.checkPermission()
            }
        }
    }

    private var formatSelectedDateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    private func dayAbbreviation(for date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.weekday, from: date) // 1=Sun, 7=Sat
        let symbols = width < 240 ? ["S", "M", "T", "W", "T", "F", "S"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return symbols[day - 1]
    }

    // MARK: - Floating Widget Management
    private func showFloatingWidget() {
        guard floatingPanel == nil else { return }
        
        let gridView = VStack {
            MonthGridView(month: Date(), selectedDate: $selectedDate, events: manager.events, accentColor: accentColor, weekStartsOn: calendarWeekStartsOn)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        
        let hosting = NSHostingView(rootView: gridView)
        hosting.sizingOptions = []
        if #available(macOS 11.0, *) {
            hosting.safeAreaRegions = []
        }
        let panel = CalendarWidgetPanel(contentView: hosting)
        
        // Align to left of notch window
        if let delegate = NSApp.delegate as? AppDelegate, let window = delegate.islandWindow {
            let notchFrame = window.frame
            let widgetFrame = NSRect(
                x: notchFrame.minX - 220,
                y: notchFrame.maxY - 230,
                width: 210,
                height: 230
            )
            panel.setFrame(widgetFrame, display: true)
            panel.orderFrontRegardless()
            DispatchQueue.main.async {
                self.floatingPanel = panel
            }
        }
    }
    
    private func toggleFloatingWidget() {
        if floatingPanel != nil {
            closeFloatingWidget()
        } else {
            showFloatingWidget()
        }
    }
    
    private func closeFloatingWidget() {
        floatingPanel?.orderOut(nil)
        DispatchQueue.main.async {
            floatingPanel = nil
        }
    }
}

// MARK: - UnifiedNotchContainer integration
extension View {
    func calendarPageOverlay(width: CGFloat, height: CGFloat, accentColor: Color, calendarViewOption: Int, calendarWeekStartsOn: Int) -> some View {
        CalendarPageContent(width: width, height: height, accentColor: accentColor, calendarViewOption: calendarViewOption, calendarWeekStartsOn: calendarWeekStartsOn)
    }
}
