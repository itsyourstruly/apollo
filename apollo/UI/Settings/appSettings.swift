
import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let defaultAccent = NSColor.systemGreen
    private let defaultBackground = NSColor.black
    private let defaultTitleColor: NSColor
    private let defaultNotchWidth: CGFloat = 210
    private let defaultNotchHeight: CGFloat = 32

    let notchWidthRange: ClosedRange<CGFloat> = 205...600
    let notchHeightRange: ClosedRange<CGFloat> = 20...120
    let rememberClipsRange: ClosedRange<Double> = 0...200
    let proximitySensitivityRange: ClosedRange<Double> = 0.3...2.4
    let carouselSensitivityRange: ClosedRange<Double> = 0.4...2.5
    let closeSensitivityRange: ClosedRange<Double> = 0.4...2.5
    let titleSizeRange: ClosedRange<CGFloat> = 10...20
    let cornerRadiusRange: ClosedRange<CGFloat> = 6...28
    let clipboardColumnsRange: ClosedRange<Double> = 2...10
    let jotColumnsRange: ClosedRange<Double> = 1...8
    let boxColumnsRange: ClosedRange<Double> = 2...10
    let clipTextSizeRange: ClosedRange<CGFloat> = 9...22
    let clipFileLabelSizeRange: ClosedRange<CGFloat> = 8...20
    let jotTextSizeRange: ClosedRange<CGFloat> = 11...22
    let boxFileNameSizeRange: ClosedRange<CGFloat> = 9...20
    let animationResponseRange: ClosedRange<Double> = 0.16...0.7
    let animationDampingRange: ClosedRange<Double> = 0.55...0.95
    let approachDelayRange: ClosedRange<Double> = 0...1.6
    let hoverCloseDelayRange: ClosedRange<Double> = 0...2.8
    let swipeCloseDelayRange: ClosedRange<Double> = 0...1.0
    let notchEdgeThicknessRange: ClosedRange<CGFloat> = 2...40
    let approachWidthRange: ClosedRange<CGFloat> = 0...160
    let approachHeightRange: ClosedRange<CGFloat> = 0...220

    private var isUpdating = false
    private let defaultsWriteQueue = DispatchQueue(label: "apollo.settings.defaults-writes", qos: .utility)
    private let defaultsWriteDelay: TimeInterval = 0.25
    private var pendingDefaultWrites: [String: Any] = [:]
    private var pendingDefaultRemovals = Set<String>()
    private var defaultsFlushWorkItem: DispatchWorkItem?

    @Published var clipboardColumns: Int {
        didSet {
            enqueueDefaultSet(clipboardColumns, forKey: AppStorageKey.clipboardColumns)
        }
    }

    @Published var jotColumns: Int {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(jotColumns, min: Int(jotColumnsRange.lowerBound), max: Int(jotColumnsRange.upperBound))
            if clampedValue != jotColumns {
                isUpdating = true
                jotColumns = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(jotColumns, forKey: AppStorageKey.jotColumns)
        }
    }

    @Published var boxColumns: Int {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(boxColumns, min: Int(boxColumnsRange.lowerBound), max: Int(boxColumnsRange.upperBound))
            if clampedValue != boxColumns {
                isUpdating = true
                boxColumns = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(boxColumns, forKey: AppStorageKey.boxColumns)
        }
    }

    @Published var clipTextSize: CGFloat {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(clipTextSize, min: clipTextSizeRange.lowerBound, max: clipTextSizeRange.upperBound)
            if clampedValue != clipTextSize {
                isUpdating = true
                clipTextSize = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(Double(clipTextSize), forKey: AppStorageKey.clipTextSize)
        }
    }

    @Published var clipFileLabelSize: CGFloat {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(clipFileLabelSize, min: clipFileLabelSizeRange.lowerBound, max: clipFileLabelSizeRange.upperBound)
            if clampedValue != clipFileLabelSize {
                isUpdating = true
                clipFileLabelSize = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(Double(clipFileLabelSize), forKey: AppStorageKey.clipFileLabelSize)
        }
    }

    @Published var jotTextSize: CGFloat {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(jotTextSize, min: jotTextSizeRange.lowerBound, max: jotTextSizeRange.upperBound)
            if clampedValue != jotTextSize {
                isUpdating = true
                jotTextSize = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(Double(jotTextSize), forKey: AppStorageKey.jotTextSize)
        }
    }

    @Published var boxFileNameSize: CGFloat {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(boxFileNameSize, min: boxFileNameSizeRange.lowerBound, max: boxFileNameSizeRange.upperBound)
            if clampedValue != boxFileNameSize {
                isUpdating = true
                boxFileNameSize = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(Double(boxFileNameSize), forKey: AppStorageKey.boxFileNameSize)
        }
    }

    @Published var accentColor: NSColor {
        didSet {
            persistAccentColor()
        }
    }

    @Published var backgroundColor: NSColor {
        didSet {
            persistBackgroundColor()
        }
    }

    @Published var titleColor: NSColor {
        didSet {
            persistTitleColor()
        }
    }

    @Published var titleUseAccent: Bool {
        didSet {
            enqueueDefaultSet(titleUseAccent, forKey: AppStorageKey.titleUseAccent)
        }
    }

    @Published var clipboardTitleAlignment: Int? {
        didSet {
            persistOptionalInt(clipboardTitleAlignment, key: AppStorageKey.clipboardTitleAlignment)
        }
    }

    @Published var clipboardTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(clipboardTitleSize.map(Double.init), key: AppStorageKey.clipboardTitleSize)
        }
    }

    @Published var clipboardTitleIconName: String? {
        didSet {
            persistOptionalString(clipboardTitleIconName, key: AppStorageKey.clipboardTitleIconName)
        }
    }

    @Published var clipboardTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(clipboardTitleUseAccent, key: AppStorageKey.clipboardTitleUseAccent)
        }
    }

    @Published var clipboardTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                clipboardTitleColor,
                redKey: AppStorageKey.clipboardTitleRed,
                greenKey: AppStorageKey.clipboardTitleGreen,
                blueKey: AppStorageKey.clipboardTitleBlue,
                alphaKey: AppStorageKey.clipboardTitleAlpha
            )
        }
    }

    @Published var jotTitleAlignment: Int? {
        didSet {
            persistOptionalInt(jotTitleAlignment, key: AppStorageKey.jotTitleAlignment)
        }
    }

    @Published var jotTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(jotTitleSize.map(Double.init), key: AppStorageKey.jotTitleSize)
        }
    }

    @Published var jotTitleIconName: String? {
        didSet {
            persistOptionalString(jotTitleIconName, key: AppStorageKey.jotTitleIconName)
        }
    }

    @Published var jotTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(jotTitleUseAccent, key: AppStorageKey.jotTitleUseAccent)
        }
    }

    @Published var jotTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                jotTitleColor,
                redKey: AppStorageKey.jotTitleRed,
                greenKey: AppStorageKey.jotTitleGreen,
                blueKey: AppStorageKey.jotTitleBlue,
                alphaKey: AppStorageKey.jotTitleAlpha
            )
        }
    }

    @Published var boxTitleAlignment: Int? {
        didSet {
            persistOptionalInt(boxTitleAlignment, key: AppStorageKey.boxTitleAlignment)
        }
    }

    @Published var boxTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(boxTitleSize.map(Double.init), key: AppStorageKey.boxTitleSize)
        }
    }

    @Published var boxTitleIconName: String? {
        didSet {
            persistOptionalString(boxTitleIconName, key: AppStorageKey.boxTitleIconName)
        }
    }

    @Published var boxTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(boxTitleUseAccent, key: AppStorageKey.boxTitleUseAccent)
        }
    }

    @Published var boxTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                boxTitleColor,
                redKey: AppStorageKey.boxTitleRed,
                greenKey: AppStorageKey.boxTitleGreen,
                blueKey: AppStorageKey.boxTitleBlue,
                alphaKey: AppStorageKey.boxTitleAlpha
            )
        }
    }

    // Custom Titles (String)
    @Published var clipboardCustomTitle: String? {
        didSet {
            persistOptionalString(clipboardCustomTitle, key: AppStorageKey.clipboardCustomTitle)
        }
    }
    @Published var jotCustomTitle: String? {
        didSet {
            persistOptionalString(jotCustomTitle, key: AppStorageKey.jotCustomTitle)
        }
    }
    @Published var boxCustomTitle: String? {
        didSet {
            persistOptionalString(boxCustomTitle, key: AppStorageKey.boxCustomTitle)
        }
    }
    @Published var chronoCustomTitle: String? {
        didSet {
            persistOptionalString(chronoCustomTitle, key: AppStorageKey.chronoCustomTitle)
        }
    }
    @Published var calendarCustomTitle: String? {
        didSet {
            persistOptionalString(calendarCustomTitle, key: AppStorageKey.calendarCustomTitle)
        }
    }
    @Published var launcherCustomTitle: String? {
        didSet {
            persistOptionalString(launcherCustomTitle, key: AppStorageKey.launcherCustomTitle)
        }
    }
    @Published var bookmarksCustomTitle: String? {
        didSet {
            persistOptionalString(bookmarksCustomTitle, key: AppStorageKey.bookmarksCustomTitle)
        }
    }
    @Published var combinedCustomTitle: String? {
        didSet {
            persistOptionalString(combinedCustomTitle, key: AppStorageKey.combinedCustomTitle)
        }
    }

    // Show Title Icons (Bool)
    @Published var clipboardShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(clipboardShowTitleIcon, key: AppStorageKey.clipboardShowTitleIcon)
        }
    }
    @Published var jotShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(jotShowTitleIcon, key: AppStorageKey.jotShowTitleIcon)
        }
    }
    @Published var boxShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(boxShowTitleIcon, key: AppStorageKey.boxShowTitleIcon)
        }
    }
    @Published var chronoShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(chronoShowTitleIcon, key: AppStorageKey.chronoShowTitleIcon)
        }
    }
    @Published var calendarShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(calendarShowTitleIcon, key: AppStorageKey.calendarShowTitleIcon)
        }
    }
    @Published var launcherShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(launcherShowTitleIcon, key: AppStorageKey.launcherShowTitleIcon)
        }
    }
    @Published var bookmarksShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(bookmarksShowTitleIcon, key: AppStorageKey.bookmarksShowTitleIcon)
        }
    }
    @Published var combinedShowTitleIcon: Bool? {
        didSet {
            persistOptionalBool(combinedShowTitleIcon, key: AppStorageKey.combinedShowTitleIcon)
        }
    }

    // Bookmark Layout Customizations
    @Published var bookmarkIconSize: CGFloat {
        didSet {
            enqueueDefaultSet(Double(bookmarkIconSize), forKey: AppStorageKey.bookmarkIconSize)
        }
    }
    @Published var bookmarkTextSize: CGFloat {
        didSet {
            enqueueDefaultSet(Double(bookmarkTextSize), forKey: AppStorageKey.bookmarkTextSize)
        }
    }
    @Published var bookmarkShowName: Bool {
        didSet {
            enqueueDefaultSet(bookmarkShowName, forKey: AppStorageKey.bookmarkShowName)
        }
    }

    // Chrono Title Overrides
    @Published var chronoTitleAlignment: Int? {
        didSet {
            persistOptionalInt(chronoTitleAlignment, key: AppStorageKey.chronoTitleAlignment)
        }
    }
    @Published var chronoTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(chronoTitleSize.map(Double.init), key: AppStorageKey.chronoTitleSize)
        }
    }
    @Published var chronoTitleIconName: String? {
        didSet {
            persistOptionalString(chronoTitleIconName, key: AppStorageKey.chronoTitleIconName)
        }
    }
    @Published var chronoTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(chronoTitleUseAccent, key: AppStorageKey.chronoTitleUseAccent)
        }
    }
    @Published var chronoTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                chronoTitleColor,
                redKey: AppStorageKey.chronoTitleRed,
                greenKey: AppStorageKey.chronoTitleGreen,
                blueKey: AppStorageKey.chronoTitleBlue,
                alphaKey: AppStorageKey.chronoTitleAlpha
            )
        }
    }

    // Calendar Title Overrides
    @Published var calendarTitleAlignment: Int? {
        didSet {
            persistOptionalInt(calendarTitleAlignment, key: AppStorageKey.calendarTitleAlignment)
        }
    }
    @Published var calendarTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(calendarTitleSize.map(Double.init), key: AppStorageKey.calendarTitleSize)
        }
    }
    @Published var calendarTitleIconName: String? {
        didSet {
            persistOptionalString(calendarTitleIconName, key: AppStorageKey.calendarTitleIconName)
        }
    }
    @Published var calendarTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(calendarTitleUseAccent, key: AppStorageKey.calendarTitleUseAccent)
        }
    }
    @Published var calendarTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                calendarTitleColor,
                redKey: AppStorageKey.calendarTitleRed,
                greenKey: AppStorageKey.calendarTitleGreen,
                blueKey: AppStorageKey.calendarTitleBlue,
                alphaKey: AppStorageKey.calendarTitleAlpha
            )
        }
    }

    // Launcher Title Overrides
    @Published var launcherTitleAlignment: Int? {
        didSet {
            persistOptionalInt(launcherTitleAlignment, key: AppStorageKey.launcherTitleAlignment)
        }
    }
    @Published var launcherTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(launcherTitleSize.map(Double.init), key: AppStorageKey.launcherTitleSize)
        }
    }
    @Published var launcherTitleIconName: String? {
        didSet {
            persistOptionalString(launcherTitleIconName, key: AppStorageKey.launcherTitleIconName)
        }
    }
    @Published var launcherTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(launcherTitleUseAccent, key: AppStorageKey.launcherTitleUseAccent)
        }
    }
    @Published var launcherTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                launcherTitleColor,
                redKey: AppStorageKey.launcherTitleRed,
                greenKey: AppStorageKey.launcherTitleGreen,
                blueKey: AppStorageKey.launcherTitleBlue,
                alphaKey: AppStorageKey.launcherTitleAlpha
            )
        }
    }

    // Bookmarks Title Overrides
    @Published var bookmarksTitleAlignment: Int? {
        didSet {
            persistOptionalInt(bookmarksTitleAlignment, key: AppStorageKey.bookmarksTitleAlignment)
        }
    }
    @Published var bookmarksTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(bookmarksTitleSize.map(Double.init), key: AppStorageKey.bookmarksTitleSize)
        }
    }
    @Published var bookmarksTitleIconName: String? {
        didSet {
            persistOptionalString(bookmarksTitleIconName, key: AppStorageKey.bookmarksTitleIconName)
        }
    }
    @Published var bookmarksTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(bookmarksTitleUseAccent, key: AppStorageKey.bookmarksTitleUseAccent)
        }
    }
    @Published var bookmarksTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                bookmarksTitleColor,
                redKey: AppStorageKey.bookmarksTitleRed,
                greenKey: AppStorageKey.bookmarksTitleGreen,
                blueKey: AppStorageKey.bookmarksTitleBlue,
                alphaKey: AppStorageKey.bookmarksTitleAlpha
            )
        }
    }

    // Combined Title Overrides
    @Published var combinedTitleAlignment: Int? {
        didSet {
            persistOptionalInt(combinedTitleAlignment, key: AppStorageKey.combinedTitleAlignment)
        }
    }
    @Published var combinedTitleSize: CGFloat? {
        didSet {
            persistOptionalDouble(combinedTitleSize.map(Double.init), key: AppStorageKey.combinedTitleSize)
        }
    }
    @Published var combinedTitleIconName: String? {
        didSet {
            persistOptionalString(combinedTitleIconName, key: AppStorageKey.combinedTitleIconName)
        }
    }
    @Published var combinedTitleUseAccent: Bool? {
        didSet {
            persistOptionalBool(combinedTitleUseAccent, key: AppStorageKey.combinedTitleUseAccent)
        }
    }
    @Published var combinedTitleColor: NSColor? {
        didSet {
            persistOptionalColor(
                combinedTitleColor,
                redKey: AppStorageKey.combinedTitleRed,
                greenKey: AppStorageKey.combinedTitleGreen,
                blueKey: AppStorageKey.combinedTitleBlue,
                alphaKey: AppStorageKey.combinedTitleAlpha
            )
        }
    }

    @Published var notchWidth: CGFloat {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(notchWidth, min: notchWidthRange.lowerBound, max: notchWidthRange.upperBound)
            if clampedValue != notchWidth {
                isUpdating = true
                notchWidth = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(Double(notchWidth), forKey: AppStorageKey.notchWidth)
        }
    }

    @Published var notchHeight: CGFloat {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = clamp(notchHeight, min: notchHeightRange.lowerBound, max: notchHeightRange.upperBound)
            if clampedValue != notchHeight {
                isUpdating = true
                notchHeight = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(Double(notchHeight), forKey: AppStorageKey.notchHeight)
        }
    }


    @Published var defaultPage: Int {
        didSet {
            let clampedValue = clamp(defaultPage, min: IslandPage.clipboard.rawValue, max: IslandPage.customCombined.rawValue)
            if clampedValue != defaultPage {
                defaultPage = clampedValue
            }
            enqueueDefaultSet(defaultPage, forKey: AppStorageKey.defaultPage)
        }
    }

    @Published var rememberClips: Int {
        didSet {
            guard !isUpdating else { return }
            let clampedValue = Int(clamp(Double(rememberClips), min: rememberClipsRange.lowerBound, max: rememberClipsRange.upperBound))
            if clampedValue != rememberClips {
                isUpdating = true
                rememberClips = clampedValue
                isUpdating = false
                return
            }
            enqueueDefaultSet(rememberClips, forKey: AppStorageKey.rememberClips)
        }
    }

    @Published var titleAlignment: Int {
        didSet {
            let clampedValue = clamp(titleAlignment, min: TitleAlignmentOption.left.rawValue, max: TitleAlignmentOption.right.rawValue)
            if clampedValue != titleAlignment {
                titleAlignment = clampedValue
            }
            enqueueDefaultSet(titleAlignment, forKey: AppStorageKey.titleAlignment)
        }
    }

    @Published var titleSize: CGFloat {
        didSet {
            let clampedValue = clamp(titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
            if clampedValue != titleSize {
                titleSize = clampedValue
            }
            enqueueDefaultSet(Double(titleSize), forKey: AppStorageKey.titleSize)
        }
    }

    @Published var titleIconName: String {
        didSet {
            enqueueDefaultSet(titleIconName, forKey: AppStorageKey.titleIconName)
        }
    }

    @Published var cornerRadius: CGFloat {
        didSet {
            let clampedValue = clamp(cornerRadius, min: cornerRadiusRange.lowerBound, max: cornerRadiusRange.upperBound)
            if clampedValue != cornerRadius {
                cornerRadius = clampedValue
            }
            enqueueDefaultSet(Double(cornerRadius), forKey: AppStorageKey.cornerRadius)
        }
    }

    @Published var showPagers: Bool {
        didSet {
            enqueueDefaultSet(showPagers, forKey: AppStorageKey.showPagers)
        }
    }

    @Published var disableChronoHUD: Bool {
        didSet {
            enqueueDefaultSet(disableChronoHUD, forKey: AppStorageKey.disableChronoHUD)
        }
    }

    @Published var clipEnabled: Bool {
        didSet {
            enqueueDefaultSet(clipEnabled, forKey: AppStorageKey.clipEnabled)
        }
    }

    @Published var jotEnabled: Bool {
        didSet {
            enqueueDefaultSet(jotEnabled, forKey: AppStorageKey.jotEnabled)
        }
    }

    @Published var boxEnabled: Bool {
        didSet {
            enqueueDefaultSet(boxEnabled, forKey: AppStorageKey.boxEnabled)
        }
    }

    @Published var chronoEnabled: Bool {
        didSet {
            enqueueDefaultSet(chronoEnabled, forKey: AppStorageKey.chronoEnabled)
        }
    }

    @Published var calendarEnabled: Bool {
        didSet {
            enqueueDefaultSet(calendarEnabled, forKey: AppStorageKey.calendarEnabled)
        }
    }

    @Published var launcherEnabled: Bool {
        didSet {
            enqueueDefaultSet(launcherEnabled, forKey: AppStorageKey.launcherEnabled)
        }
    }

    @Published var pagerStyle: Int {
        didSet {
            enqueueDefaultSet(pagerStyle, forKey: AppStorageKey.pagerStyle)
        }
    }

    @Published var peekerSize: CGFloat {
        didSet {
            enqueueDefaultSet(Double(peekerSize), forKey: AppStorageKey.peekerSize)
        }
    }

    @Published var pageOrder: [Int] {
        didSet {
            enqueueDefaultSet(pageOrder, forKey: AppStorageKey.pageOrder)
        }
    }

    @Published var openMethod: Int {
        didSet {
            enqueueDefaultSet(openMethod, forKey: AppStorageKey.openMethod)
        }
    }

    @Published var bookmarksEnabled: Bool {
        didSet {
            enqueueDefaultSet(bookmarksEnabled, forKey: AppStorageKey.bookmarksEnabled)
        }
    }

    @Published var pagerStyle2BackgroundEnabled: Bool {
        didSet {
            enqueueDefaultSet(pagerStyle2BackgroundEnabled, forKey: AppStorageKey.pagerStyle2BackgroundEnabled)
        }
    }


    @Published var showBoxFileNames: Bool {
        didSet {
            enqueueDefaultSet(showBoxFileNames, forKey: AppStorageKey.showBoxFileNames)
        }
    }

    @Published var defaultToBoxIfItems: Bool {
        didSet {
            enqueueDefaultSet(defaultToBoxIfItems, forKey: AppStorageKey.defaultToBoxIfItems)
        }
    }

    @Published var clipboardAction: Int {
        didSet {
            let clampedValue = clamp(clipboardAction, min: ClipboardActionOption.copy.rawValue, max: ClipboardActionOption.paste.rawValue)
            if clampedValue != clipboardAction {
                clipboardAction = clampedValue
            }
            enqueueDefaultSet(clipboardAction, forKey: AppStorageKey.clipboardAction)
        }
    }

    @Published var reopenLastPage: Bool {
        didSet {
            enqueueDefaultSet(reopenLastPage, forKey: AppStorageKey.reopenLastPage)
        }
    }

    @Published var lastVisitedPage: Int {
        didSet {
            let clampedValue = clamp(lastVisitedPage, min: IslandPage.clipboard.rawValue, max: IslandPage.customCombined.rawValue)
            if clampedValue != lastVisitedPage {
                lastVisitedPage = clampedValue
            }
            enqueueDefaultSet(lastVisitedPage, forKey: AppStorageKey.lastVisitedPage)
        }
    }

    @Published var proximitySensitivity: Double {
        didSet {
            let clampedValue = clamp(proximitySensitivity, min: proximitySensitivityRange.lowerBound, max: proximitySensitivityRange.upperBound)
            if clampedValue != proximitySensitivity {
                proximitySensitivity = clampedValue
            }
            enqueueDefaultSet(proximitySensitivity, forKey: AppStorageKey.proximitySensitivity)
        }
    }

    @Published var carouselSensitivity: Double {
        didSet {
            let clampedValue = clamp(carouselSensitivity, min: carouselSensitivityRange.lowerBound, max: carouselSensitivityRange.upperBound)
            if clampedValue != carouselSensitivity {
                carouselSensitivity = clampedValue
            }
            enqueueDefaultSet(carouselSensitivity, forKey: AppStorageKey.carouselSensitivity)
        }
    }

    @Published var closeSensitivity: Double {
        didSet {
            let clampedValue = clamp(closeSensitivity, min: closeSensitivityRange.lowerBound, max: closeSensitivityRange.upperBound)
            if clampedValue != closeSensitivity {
                closeSensitivity = clampedValue
            }
            enqueueDefaultSet(closeSensitivity, forKey: AppStorageKey.closeSensitivity)
        }
    }

    @Published var approachDelay: Double {
        didSet {
            let clampedValue = clamp(approachDelay, min: approachDelayRange.lowerBound, max: approachDelayRange.upperBound)
            if clampedValue != approachDelay {
                approachDelay = clampedValue
            }
            enqueueDefaultSet(approachDelay, forKey: AppStorageKey.approachDelay)
        }
    }

    @Published var hoverCloseDelay: Double {
        didSet {
            let clampedValue = clamp(hoverCloseDelay, min: hoverCloseDelayRange.lowerBound, max: hoverCloseDelayRange.upperBound)
            if clampedValue != hoverCloseDelay {
                hoverCloseDelay = clampedValue
            }
            enqueueDefaultSet(hoverCloseDelay, forKey: AppStorageKey.hoverCloseDelay)
        }
    }

    @Published var swipeCloseDelay: Double {
        didSet {
            let clampedValue = clamp(swipeCloseDelay, min: swipeCloseDelayRange.lowerBound, max: swipeCloseDelayRange.upperBound)
            if clampedValue != swipeCloseDelay {
                swipeCloseDelay = clampedValue
            }
            enqueueDefaultSet(swipeCloseDelay, forKey: AppStorageKey.swipeCloseDelay)
        }
    }

    @Published var disableApproach: Bool {
        didSet {
            enqueueDefaultSet(disableApproach, forKey: AppStorageKey.disableApproach)
        }
    }

    @Published var alwaysUseApproachWhenDraggingFile: Bool {
        didSet {
            enqueueDefaultSet(alwaysUseApproachWhenDraggingFile, forKey: AppStorageKey.alwaysUseApproachWhenDraggingFile)
        }
    }

    @Published var notchEdgeThickness: CGFloat {
        didSet {
            let clampedValue = clamp(notchEdgeThickness, min: notchEdgeThicknessRange.lowerBound, max: notchEdgeThicknessRange.upperBound)
            if clampedValue != notchEdgeThickness {
                notchEdgeThickness = clampedValue
            }
            enqueueDefaultSet(Double(notchEdgeThickness), forKey: AppStorageKey.notchEdgeThickness)
        }
    }

    @Published var approachWidth: CGFloat {
        didSet {
            let clampedValue = clamp(approachWidth, min: approachWidthRange.lowerBound, max: approachWidthRange.upperBound)
            if clampedValue != approachWidth {
                approachWidth = clampedValue
            }
            enqueueDefaultSet(Double(approachWidth), forKey: AppStorageKey.approachWidth)
        }
    }

    @Published var approachHeight: CGFloat {
        didSet {
            let clampedValue = clamp(approachHeight, min: approachHeightRange.lowerBound, max: approachHeightRange.upperBound)
            if clampedValue != approachHeight {
                approachHeight = clampedValue
            }
            enqueueDefaultSet(Double(approachHeight), forKey: AppStorageKey.approachHeight)
        }
    }

    @Published var showHoverPreviews: Bool = false
@Published var hoverPreviewFocus: HoverPreviewFocus = .all
    @Published var hoverPreviewTitlePage: IslandPage = .clipboard

    @Published var animationResponse: Double {
        didSet {
            let clampedValue = clamp(animationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != animationResponse {
                animationResponse = clampedValue
            }
            enqueueDefaultSet(animationResponse, forKey: AppStorageKey.animationResponse)
        }
    }

    @Published var animationDamping: Double {
        didSet {
            let clampedValue = clamp(animationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != animationDamping {
                animationDamping = clampedValue
            }
            enqueueDefaultSet(animationDamping, forKey: AppStorageKey.animationDamping)
        }
    }

    @Published var notchAnimationResponse: Double {
        didSet {
            let clampedValue = clamp(notchAnimationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != notchAnimationResponse {
                notchAnimationResponse = clampedValue
            }
            enqueueDefaultSet(notchAnimationResponse, forKey: AppStorageKey.notchAnimationResponse)
        }
    }

    @Published var notchAnimationDamping: Double {
        didSet {
            let clampedValue = clamp(notchAnimationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != notchAnimationDamping {
                notchAnimationDamping = clampedValue
            }
            enqueueDefaultSet(notchAnimationDamping, forKey: AppStorageKey.notchAnimationDamping)
        }
    }

    @Published var carouselAnimationResponse: Double {
        didSet {
            let clampedValue = clamp(carouselAnimationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != carouselAnimationResponse {
                carouselAnimationResponse = clampedValue
            }
            enqueueDefaultSet(carouselAnimationResponse, forKey: AppStorageKey.carouselAnimationResponse)
        }
    }

    @Published var carouselAnimationDamping: Double {
        didSet {
            let clampedValue = clamp(carouselAnimationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != carouselAnimationDamping {
                carouselAnimationDamping = clampedValue
            }
            enqueueDefaultSet(carouselAnimationDamping, forKey: AppStorageKey.carouselAnimationDamping)
        }
    }

    @Published var swipeAnimationResponse: Double {
        didSet {
            let clampedValue = clamp(swipeAnimationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != swipeAnimationResponse {
                swipeAnimationResponse = clampedValue
            }
            enqueueDefaultSet(swipeAnimationResponse, forKey: AppStorageKey.swipeAnimationResponse)
        }
    }

    @Published var swipeAnimationDamping: Double {
        didSet {
            let clampedValue = clamp(swipeAnimationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != swipeAnimationDamping {
                swipeAnimationDamping = clampedValue
            }
            enqueueDefaultSet(swipeAnimationDamping, forKey: AppStorageKey.swipeAnimationDamping)
        }
    }

    @Published var observedFolders: [String] {
        didSet {
            var seen = Set<String>()
            let unique = observedFolders.filter { seen.insert($0).inserted }
            if unique != observedFolders {
                observedFolders = unique
                return
            }
            enqueueDefaultSet(observedFolders, forKey: AppStorageKey.observedFolders)
        }
    }

    @Published var calendarViewOption: Int {
        didSet {
            enqueueDefaultSet(calendarViewOption, forKey: "calendarViewOption")
        }
    }

    @Published var customActionsLayoutOption: Int {
        didSet {
            enqueueDefaultSet(customActionsLayoutOption, forKey: "customActionsLayoutOption")
        }
    }

    @Published var showLauncherInPeeker: Bool {
        didSet {
            enqueueDefaultSet(showLauncherInPeeker, forKey: "showLauncherInPeeker")
        }
    }

    @Published var showBookmarksInPeeker: Bool {
        didSet {
            enqueueDefaultSet(showBookmarksInPeeker, forKey: "showBookmarksInPeeker")
        }
    }

    @Published var showCombinedInPeeker: Bool {
        didSet {
            enqueueDefaultSet(showCombinedInPeeker, forKey: "showCombinedInPeeker")
        }
    }

    @Published var showAddAppButton: Bool {
        didSet {
            enqueueDefaultSet(showAddAppButton, forKey: "showAddAppButton")
        }
    }

    @Published var showAddBookmarkButton: Bool {
        didSet {
            enqueueDefaultSet(showAddBookmarkButton, forKey: "showAddBookmarkButton")
        }
    }

    @Published var launcherColumns: Int {
        didSet {
            enqueueDefaultSet(launcherColumns, forKey: "launcherColumns")
        }
    }

    @Published var bookmarkColumns: Int {
        didSet {
            enqueueDefaultSet(bookmarkColumns, forKey: "bookmarkColumns")
        }
    }

    @Published var launcherIconSize: CGFloat {
        didSet {
            enqueueDefaultSet(Double(launcherIconSize), forKey: "launcherIconSize")
        }
    }

    @Published var launcherTextSize: CGFloat {
        didSet {
            enqueueDefaultSet(Double(launcherTextSize), forKey: "launcherTextSize")
        }
    }

    @Published var launcherShowName: Bool {
        didSet {
            enqueueDefaultSet(launcherShowName, forKey: "launcherShowName")
        }
    }

    @Published var launcherDisplayMode: Int {
        didSet {
            enqueueDefaultSet(launcherDisplayMode, forKey: "launcherDisplayMode")
        }
    }

    @Published var bookmarkDisplayMode: Int {
        didSet {
            enqueueDefaultSet(bookmarkDisplayMode, forKey: "bookmarkDisplayMode")
        }
    }

    @Published var sharingTargetApps: [String] {
        didSet {
            enqueueDefaultSet(sharingTargetApps, forKey: "sharingTargetApps")
        }
    }

    @Published var boxSlimModeEnabled: Bool {
        didSet {
            enqueueDefaultSet(boxSlimModeEnabled, forKey: "boxSlimModeEnabled")
        }
    }

    @Published var boxSlimModeHoldDuration: Double {
        didSet {
            enqueueDefaultSet(boxSlimModeHoldDuration, forKey: "boxSlimModeHoldDuration")
        }
    }

    @Published var boxSlimModeTrigger: Int {
        didSet {
            enqueueDefaultSet(boxSlimModeTrigger, forKey: "boxSlimModeTrigger")
        }
    }

    @Published var boxSlimModeWiggleSensitivity: Double {
        didSet {
            enqueueDefaultSet(boxSlimModeWiggleSensitivity, forKey: "boxSlimModeWiggleSensitivity")
        }
    }

    @Published var boxSlimModePosition: Int {
        didSet {
            enqueueDefaultSet(boxSlimModePosition, forKey: "boxSlimModePosition")
        }
    }

    @Published var boxSlimModeKeepOpen: Bool {
        didSet {
            enqueueDefaultSet(boxSlimModeKeepOpen, forKey: "boxSlimModeKeepOpen")
        }
    }

    @Published var boxSlimModeExpandDirection: Int {
        didSet {
            enqueueDefaultSet(boxSlimModeExpandDirection, forKey: "boxSlimModeExpandDirection")
        }
    }

    @Published var boxSlimModeMaxViewSize: Double {
        didSet {
            enqueueDefaultSet(boxSlimModeMaxViewSize, forKey: "boxSlimModeMaxViewSize")
        }
    }

    @Published var boxSlimModeItemWidth: Double {
        didSet {
            enqueueDefaultSet(boxSlimModeItemWidth, forKey: "boxSlimModeItemWidth")
        }
    }

    @Published var boxSlimModeItemHeight: Double {
        didSet {
            enqueueDefaultSet(boxSlimModeItemHeight, forKey: "boxSlimModeItemHeight")
        }
    }

    @Published var boxSlimModeWidth: Double {
        didSet {
            enqueueDefaultSet(boxSlimModeWidth, forKey: "boxSlimModeWidth")
        }
    }

    @Published var boxSlimModeHeight: Double {
        didSet {
            enqueueDefaultSet(boxSlimModeHeight, forKey: "boxSlimModeHeight")
        }
    }

    @Published var hardwareNotchX: CGFloat = 0
    @Published var hardwareNotchWidth: CGFloat = 210
    @Published var hardwareNotchHeight: CGFloat = 32

    var clampedNotchWidth: CGFloat {
        let safeValue = notchWidth.isFinite ? notchWidth : defaultNotchWidth
        return clamp(safeValue, min: notchWidthRange.lowerBound, max: notchWidthRange.upperBound)
    }
    var clampedNotchHeight: CGFloat {
        let safeValue = notchHeight.isFinite ? notchHeight : defaultNotchHeight
        return clamp(safeValue, min: notchHeightRange.lowerBound, max: notchHeightRange.upperBound)
    }

    var effectiveNotchWidth: CGFloat {
        hardwareNotchWidth
    }
    var effectiveNotchHeight: CGFloat {
        hardwareNotchHeight
    }

    var clampedRememberClips: Int {
        if rememberClips == 0 {
            return 0
        }
        return clamp(rememberClips, min: Int(rememberClipsRange.lowerBound), max: Int(rememberClipsRange.upperBound))
    }

    var clampedProximitySensitivity: CGFloat {
        let safeValue = proximitySensitivity.isFinite ? proximitySensitivity : 1.0
        return CGFloat(clamp(safeValue, min: proximitySensitivityRange.lowerBound, max: proximitySensitivityRange.upperBound))
    }

    var clampedCarouselSensitivity: CGFloat {
        let safeValue = carouselSensitivity.isFinite ? carouselSensitivity : 1.0
        return CGFloat(clamp(safeValue, min: carouselSensitivityRange.lowerBound, max: carouselSensitivityRange.upperBound))
    }

    var clampedCloseSensitivity: CGFloat {
        let safeValue = closeSensitivity.isFinite ? closeSensitivity : 1.0
        return CGFloat(clamp(safeValue, min: closeSensitivityRange.lowerBound, max: closeSensitivityRange.upperBound))
    }

    var clampedNotchEdgeThickness: CGFloat {
        let safeValue = notchEdgeThickness.isFinite ? notchEdgeThickness : notchEdgeThicknessRange.lowerBound
        return clamp(safeValue, min: notchEdgeThicknessRange.lowerBound, max: notchEdgeThicknessRange.upperBound)
    }

    var clampedApproachWidth: CGFloat {
        let safeValue = approachWidth.isFinite ? approachWidth : 0
        return clamp(safeValue, min: approachWidthRange.lowerBound, max: approachWidthRange.upperBound)
    }

    var clampedApproachHeight: CGFloat {
        let safeValue = approachHeight.isFinite ? approachHeight : 0
        return clamp(safeValue, min: approachHeightRange.lowerBound, max: approachHeightRange.upperBound)
    }

    var effectiveRememberClips: Int? {
        clampedRememberClips == 0 ? nil : clampedRememberClips
    }

    var titleAlignmentOption: TitleAlignmentOption {
        TitleAlignmentOption(rawValue: titleAlignment) ?? .left
    }

    var effectiveTitleColor: NSColor {
        titleUseAccent ? accentColor : titleColor
    }

    var clipboardActionOption: ClipboardActionOption {
        ClipboardActionOption(rawValue: clipboardAction) ?? .copy
    }

    var notchOpenAnimation: Animation {
        .spring(response: notchAnimationResponse, dampingFraction: notchAnimationDamping)
    }

    var carouselAnimation: Animation {
        .spring(response: carouselAnimationResponse, dampingFraction: carouselAnimationDamping)
    }

    var swipeAnimation: Animation {
        .spring(response: swipeAnimationResponse, dampingFraction: swipeAnimationDamping)
    }

    func titleText(for page: IslandPage) -> String {
        switch page {
        case .clipboard:
            if clipboardCustomTitle == "*" { return "" }
            return clipboardCustomTitle?.isEmpty == false ? clipboardCustomTitle! : "Clip"
        case .jot:
            if jotCustomTitle == "*" { return "" }
            return jotCustomTitle?.isEmpty == false ? jotCustomTitle! : "Jot"
        case .box:
            if boxCustomTitle == "*" { return "" }
            return boxCustomTitle?.isEmpty == false ? boxCustomTitle! : "Box"
        case .chrono:
            if chronoCustomTitle == "*" { return "" }
            return chronoCustomTitle?.isEmpty == false ? chronoCustomTitle! : "Chrono"
        case .calendar:
            if calendarCustomTitle == "*" { return "" }
            return calendarCustomTitle?.isEmpty == false ? calendarCustomTitle! : "Calendar"
        case .launcher:
            if launcherCustomTitle == "*" { return "" }
            return launcherCustomTitle?.isEmpty == false ? launcherCustomTitle! : "Launcher"
        case .bookmarks:
            if bookmarksCustomTitle == "*" { return "" }
            return bookmarksCustomTitle?.isEmpty == false ? bookmarksCustomTitle! : "Bookmarks"
        case .customCombined:
            if combinedCustomTitle == "*" { return "" }
            return combinedCustomTitle?.isEmpty == false ? combinedCustomTitle! : "Combined"
        }
    }

    func showTitleIcon(for page: IslandPage) -> Bool {
        switch page {
        case .clipboard:
            return clipboardShowTitleIcon ?? true
        case .jot:
            return jotShowTitleIcon ?? true
        case .box:
            return boxShowTitleIcon ?? true
        case .chrono:
            return chronoShowTitleIcon ?? true
        case .calendar:
            return calendarShowTitleIcon ?? true
        case .launcher:
            return launcherShowTitleIcon ?? true
        case .bookmarks:
            return bookmarksShowTitleIcon ?? true
        case .customCombined:
            return combinedShowTitleIcon ?? true
        }
    }

    func titleAlignment(for page: IslandPage) -> TitleAlignmentOption {
        switch page {
        case .clipboard:
            return TitleAlignmentOption(rawValue: clipboardTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .jot:
            return TitleAlignmentOption(rawValue: jotTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .box:
            return TitleAlignmentOption(rawValue: boxTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .chrono:
            return TitleAlignmentOption(rawValue: chronoTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .calendar:
            return TitleAlignmentOption(rawValue: calendarTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .launcher:
            return TitleAlignmentOption(rawValue: launcherTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .bookmarks:
            return TitleAlignmentOption(rawValue: bookmarksTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .customCombined:
            return TitleAlignmentOption(rawValue: combinedTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        }
    }

    func titleSize(for page: IslandPage) -> CGFloat {
        switch page {
        case .clipboard:
            return clamp(clipboardTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .jot:
            return clamp(jotTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .box:
            return clamp(boxTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .chrono:
            return clamp(chronoTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .calendar:
            return clamp(calendarTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .launcher:
            return clamp(launcherTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .bookmarks:
            return clamp(bookmarksTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .customCombined:
            return clamp(combinedTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        }
    }

    private func getPageTitleColor(useAccent: Bool?, overrideColor: NSColor?, mainColor: NSColor) -> NSColor {
        if useAccent == true {
            return accentColor
        }
        if let override = overrideColor {
            return override
        }
        if useAccent == false {
            return titleColor
        }
        return mainColor
    }

    func titleColor(for page: IslandPage) -> NSColor {
        let mainColor = effectiveTitleColor
        switch page {
        case .clipboard:
            return getPageTitleColor(useAccent: clipboardTitleUseAccent, overrideColor: clipboardTitleColor, mainColor: mainColor)
        case .jot:
            return getPageTitleColor(useAccent: jotTitleUseAccent, overrideColor: jotTitleColor, mainColor: mainColor)
        case .box:
            return getPageTitleColor(useAccent: boxTitleUseAccent, overrideColor: boxTitleColor, mainColor: mainColor)
        case .chrono:
            return getPageTitleColor(useAccent: chronoTitleUseAccent, overrideColor: chronoTitleColor, mainColor: mainColor)
        case .calendar:
            return getPageTitleColor(useAccent: calendarTitleUseAccent, overrideColor: calendarTitleColor, mainColor: mainColor)
        case .launcher:
            return getPageTitleColor(useAccent: launcherTitleUseAccent, overrideColor: launcherTitleColor, mainColor: mainColor)
        case .bookmarks:
            return getPageTitleColor(useAccent: bookmarksTitleUseAccent, overrideColor: bookmarksTitleColor, mainColor: mainColor)
        case .customCombined:
            return getPageTitleColor(useAccent: combinedTitleUseAccent, overrideColor: combinedTitleColor, mainColor: mainColor)
        }
    }

    func titleSymbol(for page: IslandPage, fallback: String) -> String {
        let mainSymbol = titleIconName.isEmpty ? fallback : titleIconName
        switch page {
        case .clipboard:
            if let override = clipboardTitleIconName, !override.isEmpty { return override }
        case .jot:
            if let override = jotTitleIconName, !override.isEmpty { return override }
        case .box:
            if let override = boxTitleIconName, !override.isEmpty { return override }
        case .chrono:
            if let override = chronoTitleIconName, !override.isEmpty { return override }
        case .calendar:
            if let override = calendarTitleIconName, !override.isEmpty { return override }
        case .launcher:
            if let override = launcherTitleIconName, !override.isEmpty { return override }
        case .bookmarks:
            if let override = bookmarksTitleIconName, !override.isEmpty { return override }
        case .customCombined:
            if let override = combinedTitleIconName, !override.isEmpty { return override }
        }
        return mainSymbol
    }

    private init() {
        defaultTitleColor = defaultAccent
        let accent = AppSettings.loadAccentColor(defaults: defaults, fallback: defaultAccent)
        accentColor = accent
        let background = AppSettings.loadColor(
            defaults: defaults,
            redKey: AppStorageKey.backgroundRed,
            greenKey: AppStorageKey.backgroundGreen,
            blueKey: AppStorageKey.backgroundBlue,
            alphaKey: AppStorageKey.backgroundAlpha,
            fallback: defaultBackground
        )
        backgroundColor = background
        let loadedTitleColor = AppSettings.loadColor(
            defaults: defaults,
            redKey: AppStorageKey.titleRed,
            greenKey: AppStorageKey.titleGreen,
            blueKey: AppStorageKey.titleBlue,
            alphaKey: AppStorageKey.titleAlpha,
            fallback: defaultTitleColor
        )
        titleColor = loadedTitleColor
        if defaults.object(forKey: AppStorageKey.titleUseAccent) == nil {
            titleUseAccent = false
        } else {
            titleUseAccent = defaults.bool(forKey: AppStorageKey.titleUseAccent)
        }
        clipboardTitleAlignment = defaults.object(forKey: AppStorageKey.clipboardTitleAlignment) as? Int
        clipboardTitleSize = (defaults.object(forKey: AppStorageKey.clipboardTitleSize) as? Double).map { CGFloat($0) }
        clipboardTitleIconName = defaults.string(forKey: AppStorageKey.clipboardTitleIconName)
        clipboardTitleUseAccent = defaults.object(forKey: AppStorageKey.clipboardTitleUseAccent) as? Bool
        clipboardTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.clipboardTitleRed,
            greenKey: AppStorageKey.clipboardTitleGreen,
            blueKey: AppStorageKey.clipboardTitleBlue,
            alphaKey: AppStorageKey.clipboardTitleAlpha
        )
        jotTitleAlignment = defaults.object(forKey: AppStorageKey.jotTitleAlignment) as? Int
        jotTitleSize = (defaults.object(forKey: AppStorageKey.jotTitleSize) as? Double).map { CGFloat($0) }
        jotTitleIconName = defaults.string(forKey: AppStorageKey.jotTitleIconName)
        jotTitleUseAccent = defaults.object(forKey: AppStorageKey.jotTitleUseAccent) as? Bool
        jotTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.jotTitleRed,
            greenKey: AppStorageKey.jotTitleGreen,
            blueKey: AppStorageKey.jotTitleBlue,
            alphaKey: AppStorageKey.jotTitleAlpha
        )
        boxTitleAlignment = defaults.object(forKey: AppStorageKey.boxTitleAlignment) as? Int
        boxTitleSize = (defaults.object(forKey: AppStorageKey.boxTitleSize) as? Double).map { CGFloat($0) }
        boxTitleIconName = defaults.string(forKey: AppStorageKey.boxTitleIconName)
        boxTitleUseAccent = defaults.object(forKey: AppStorageKey.boxTitleUseAccent) as? Bool
        boxTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.boxTitleRed,
            greenKey: AppStorageKey.boxTitleGreen,
            blueKey: AppStorageKey.boxTitleBlue,
            alphaKey: AppStorageKey.boxTitleAlpha
        )
        if let storedWidth = defaults.object(forKey: AppStorageKey.notchWidth) as? Double {
            notchWidth = clamp(CGFloat(storedWidth), min: notchWidthRange.lowerBound, max: notchWidthRange.upperBound)
        } else {
            notchWidth = defaultNotchWidth
        }
        if let storedHeight = defaults.object(forKey: AppStorageKey.notchHeight) as? Double {
            notchHeight = clamp(CGFloat(storedHeight), min: notchHeightRange.lowerBound, max: notchHeightRange.upperBound)
        } else {
            notchHeight = defaultNotchHeight
        }
        if defaults.object(forKey: AppStorageKey.defaultPage) == nil {
            defaultPage = IslandPage.clipboard.rawValue
        } else {
            defaultPage = clamp(defaults.integer(forKey: AppStorageKey.defaultPage), min: IslandPage.clipboard.rawValue, max: IslandPage.customCombined.rawValue)
        }
        if defaults.object(forKey: AppStorageKey.rememberClips) == nil {
            rememberClips = 40
        } else {
            let storedValue = defaults.integer(forKey: AppStorageKey.rememberClips)
            rememberClips = clamp(storedValue, min: Int(rememberClipsRange.lowerBound), max: Int(rememberClipsRange.upperBound))
        }

        if defaults.object(forKey: AppStorageKey.titleAlignment) == nil {
            titleAlignment = TitleAlignmentOption.left.rawValue
        } else {
            titleAlignment = clamp(defaults.integer(forKey: AppStorageKey.titleAlignment), min: TitleAlignmentOption.left.rawValue, max: TitleAlignmentOption.right.rawValue)
        }

        if let storedTitleSize = defaults.object(forKey: AppStorageKey.titleSize) as? Double {
            titleSize = clamp(CGFloat(storedTitleSize), min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        } else {
            titleSize = 12
        }

        titleIconName = defaults.string(forKey: AppStorageKey.titleIconName) ?? ""

        if let storedCornerRadius = defaults.object(forKey: AppStorageKey.cornerRadius) as? Double {
            cornerRadius = clamp(CGFloat(storedCornerRadius), min: cornerRadiusRange.lowerBound, max: cornerRadiusRange.upperBound)
        } else {
            cornerRadius = 16
        }

        if defaults.object(forKey: AppStorageKey.showPagers) == nil {
            showPagers = true
        } else {
            showPagers = defaults.bool(forKey: AppStorageKey.showPagers)
        }

        if defaults.object(forKey: AppStorageKey.disableChronoHUD) == nil {
            disableChronoHUD = false
        } else {
            disableChronoHUD = defaults.bool(forKey: AppStorageKey.disableChronoHUD)
        }

        if defaults.object(forKey: AppStorageKey.clipEnabled) == nil {
            clipEnabled = true
        } else {
            clipEnabled = defaults.bool(forKey: AppStorageKey.clipEnabled)
        }

        if defaults.object(forKey: AppStorageKey.jotEnabled) == nil {
            jotEnabled = true
        } else {
            jotEnabled = defaults.bool(forKey: AppStorageKey.jotEnabled)
        }

        if defaults.object(forKey: AppStorageKey.boxEnabled) == nil {
            boxEnabled = true
        } else {
            boxEnabled = defaults.bool(forKey: AppStorageKey.boxEnabled)
        }

        if defaults.object(forKey: AppStorageKey.chronoEnabled) == nil {
            chronoEnabled = true
        } else {
            chronoEnabled = defaults.bool(forKey: AppStorageKey.chronoEnabled)
        }

        if defaults.object(forKey: AppStorageKey.calendarEnabled) == nil {
            calendarEnabled = true
        } else {
            calendarEnabled = defaults.bool(forKey: AppStorageKey.calendarEnabled)
        }

        if defaults.object(forKey: AppStorageKey.launcherEnabled) == nil {
            launcherEnabled = true
        } else {
            launcherEnabled = defaults.bool(forKey: AppStorageKey.launcherEnabled)
        }

        if defaults.object(forKey: AppStorageKey.pagerStyle) == nil {
            pagerStyle = 0
        } else {
            pagerStyle = defaults.integer(forKey: AppStorageKey.pagerStyle)
        }

        if defaults.object(forKey: AppStorageKey.peekerSize) == nil {
            peekerSize = 14
        } else {
            peekerSize = CGFloat(defaults.double(forKey: AppStorageKey.peekerSize))
        }

        if let savedOrder = defaults.array(forKey: AppStorageKey.pageOrder) as? [Int] {
            var order = savedOrder
            let allStandard = [0, 1, 2, 3, 4, 5, 6]
            for p in allStandard {
                if !order.contains(p) {
                    order.append(p)
                }
            }
            order = order.filter { allStandard.contains($0) }
            pageOrder = order
        } else {
            pageOrder = [0, 1, 2, 3, 4, 5, 6]
        }

        if defaults.object(forKey: AppStorageKey.openMethod) == nil {
            openMethod = 0
        } else {
            openMethod = defaults.integer(forKey: AppStorageKey.openMethod)
        }

        if defaults.object(forKey: AppStorageKey.bookmarksEnabled) == nil {
            bookmarksEnabled = true
        } else {
            bookmarksEnabled = defaults.bool(forKey: AppStorageKey.bookmarksEnabled)
        }

        if defaults.object(forKey: AppStorageKey.pagerStyle2BackgroundEnabled) == nil {
            pagerStyle2BackgroundEnabled = true
        } else {
            pagerStyle2BackgroundEnabled = defaults.bool(forKey: AppStorageKey.pagerStyle2BackgroundEnabled)
        }


        if defaults.object(forKey: AppStorageKey.showBoxFileNames) == nil {
            showBoxFileNames = true
        } else {
            showBoxFileNames = defaults.bool(forKey: AppStorageKey.showBoxFileNames)
        }

        if defaults.object(forKey: AppStorageKey.defaultToBoxIfItems) == nil {
            defaultToBoxIfItems = false
        } else {
            defaultToBoxIfItems = defaults.bool(forKey: AppStorageKey.defaultToBoxIfItems)
        }

        if defaults.object(forKey: AppStorageKey.clipboardAction) == nil {
            clipboardAction = ClipboardActionOption.copy.rawValue
        } else {
            clipboardAction = clamp(defaults.integer(forKey: AppStorageKey.clipboardAction), min: ClipboardActionOption.copy.rawValue, max: ClipboardActionOption.paste.rawValue)
        }

        if defaults.object(forKey: AppStorageKey.reopenLastPage) == nil {
            reopenLastPage = false
        } else {
            reopenLastPage = defaults.bool(forKey: AppStorageKey.reopenLastPage)
        }

        if defaults.object(forKey: AppStorageKey.clipboardColumns) == nil {
            clipboardColumns = 5
        } else {
            clipboardColumns = clamp(defaults.integer(forKey: AppStorageKey.clipboardColumns), min: Int(clipboardColumnsRange.lowerBound), max: Int(clipboardColumnsRange.upperBound))
        }

        if defaults.object(forKey: AppStorageKey.jotColumns) == nil {
            jotColumns = 3
        } else {
            jotColumns = clamp(defaults.integer(forKey: AppStorageKey.jotColumns), min: Int(jotColumnsRange.lowerBound), max: Int(jotColumnsRange.upperBound))
        }

        if defaults.object(forKey: AppStorageKey.boxColumns) == nil {
            boxColumns = 5
        } else {
            boxColumns = clamp(defaults.integer(forKey: AppStorageKey.boxColumns), min: Int(boxColumnsRange.lowerBound), max: Int(boxColumnsRange.upperBound))
        }

        if let storedClipTextSize = defaults.object(forKey: AppStorageKey.clipTextSize) as? Double {
            clipTextSize = clamp(CGFloat(storedClipTextSize), min: clipTextSizeRange.lowerBound, max: clipTextSizeRange.upperBound)
        } else {
            clipTextSize = 12
        }

        if let storedClipFileLabelSize = defaults.object(forKey: AppStorageKey.clipFileLabelSize) as? Double {
            clipFileLabelSize = clamp(CGFloat(storedClipFileLabelSize), min: clipFileLabelSizeRange.lowerBound, max: clipFileLabelSizeRange.upperBound)
        } else {
            clipFileLabelSize = 10
        }

        if let storedJotTextSize = defaults.object(forKey: AppStorageKey.jotTextSize) as? Double {
            jotTextSize = clamp(CGFloat(storedJotTextSize), min: jotTextSizeRange.lowerBound, max: jotTextSizeRange.upperBound)
        } else {
            jotTextSize = 14
        }

        if let storedBoxFileNameSize = defaults.object(forKey: AppStorageKey.boxFileNameSize) as? Double {
            boxFileNameSize = clamp(CGFloat(storedBoxFileNameSize), min: boxFileNameSizeRange.lowerBound, max: boxFileNameSizeRange.upperBound)
        } else {
            boxFileNameSize = 11
        }

        if defaults.object(forKey: AppStorageKey.lastVisitedPage) == nil {
            lastVisitedPage = IslandPage.clipboard.rawValue
        } else {
            lastVisitedPage = clamp(defaults.integer(forKey: AppStorageKey.lastVisitedPage), min: IslandPage.clipboard.rawValue, max: IslandPage.customCombined.rawValue)
        }

        if let storedSensitivity = defaults.object(forKey: AppStorageKey.proximitySensitivity) as? Double {
            proximitySensitivity = clamp(storedSensitivity, min: proximitySensitivityRange.lowerBound, max: proximitySensitivityRange.upperBound)
        } else {
            proximitySensitivity = 1.0
        }

        if let storedCarouselSensitivity = defaults.object(forKey: AppStorageKey.carouselSensitivity) as? Double {
            carouselSensitivity = clamp(storedCarouselSensitivity, min: carouselSensitivityRange.lowerBound, max: carouselSensitivityRange.upperBound)
        } else {
            carouselSensitivity = 1.0
        }

        if let storedCloseSensitivity = defaults.object(forKey: AppStorageKey.closeSensitivity) as? Double {
            closeSensitivity = clamp(storedCloseSensitivity, min: closeSensitivityRange.lowerBound, max: closeSensitivityRange.upperBound)
        } else {
            closeSensitivity = 1.0
        }

        let baseResponse: Double
        if let storedAnimationResponse = defaults.object(forKey: AppStorageKey.animationResponse) as? Double {
            baseResponse = clamp(storedAnimationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
        } else {
            baseResponse = 0.32
        }
        animationResponse = baseResponse

        let baseDamping: Double
        if let storedAnimationDamping = defaults.object(forKey: AppStorageKey.animationDamping) as? Double {
            baseDamping = clamp(storedAnimationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
        } else {
            baseDamping = 0.86
        }
        animationDamping = baseDamping

        if let storedNotchResponse = defaults.object(forKey: AppStorageKey.notchAnimationResponse) as? Double {
            notchAnimationResponse = clamp(storedNotchResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
        } else {
            notchAnimationResponse = baseResponse
        }

        if let storedNotchDamping = defaults.object(forKey: AppStorageKey.notchAnimationDamping) as? Double {
            notchAnimationDamping = clamp(storedNotchDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
        } else {
            notchAnimationDamping = baseDamping
        }

        if let storedCarouselResponse = defaults.object(forKey: AppStorageKey.carouselAnimationResponse) as? Double {
            carouselAnimationResponse = clamp(storedCarouselResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
        } else {
            carouselAnimationResponse = baseResponse
        }

        if let storedCarouselDamping = defaults.object(forKey: AppStorageKey.carouselAnimationDamping) as? Double {
            carouselAnimationDamping = clamp(storedCarouselDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
        } else {
            carouselAnimationDamping = baseDamping
        }

        if let storedSwipeResponse = defaults.object(forKey: AppStorageKey.swipeAnimationResponse) as? Double {
            swipeAnimationResponse = clamp(storedSwipeResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
        } else {
            swipeAnimationResponse = baseResponse
        }

        if let storedSwipeDamping = defaults.object(forKey: AppStorageKey.swipeAnimationDamping) as? Double {
            swipeAnimationDamping = clamp(storedSwipeDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
        } else {
            swipeAnimationDamping = baseDamping
        }

        if let storedApproachDelay = defaults.object(forKey: AppStorageKey.approachDelay) as? Double {
            approachDelay = clamp(storedApproachDelay, min: approachDelayRange.lowerBound, max: approachDelayRange.upperBound)
        } else {
            approachDelay = 0.2
        }

        if let storedHoverDelay = defaults.object(forKey: AppStorageKey.hoverCloseDelay) as? Double {
            hoverCloseDelay = clamp(storedHoverDelay, min: hoverCloseDelayRange.lowerBound, max: hoverCloseDelayRange.upperBound)
        } else {
            hoverCloseDelay = 0.25
        }

        if let storedSwipeCloseDelay = defaults.object(forKey: AppStorageKey.swipeCloseDelay) as? Double {
            swipeCloseDelay = clamp(storedSwipeCloseDelay, min: swipeCloseDelayRange.lowerBound, max: swipeCloseDelayRange.upperBound)
        } else {
            swipeCloseDelay = 0.0
        }

        if defaults.object(forKey: AppStorageKey.disableApproach) == nil {
            disableApproach = true
        } else {
            disableApproach = defaults.bool(forKey: AppStorageKey.disableApproach)
        }

        if defaults.object(forKey: AppStorageKey.alwaysUseApproachWhenDraggingFile) == nil {
            alwaysUseApproachWhenDraggingFile = false
        } else {
            alwaysUseApproachWhenDraggingFile = defaults.bool(forKey: AppStorageKey.alwaysUseApproachWhenDraggingFile)
        }

        if let storedEdge = defaults.object(forKey: AppStorageKey.notchEdgeThickness) as? Double {
            notchEdgeThickness = clamp(CGFloat(storedEdge), min: notchEdgeThicknessRange.lowerBound, max: notchEdgeThicknessRange.upperBound)
        } else {
            notchEdgeThickness = 6
        }

        if let storedApproachWidth = defaults.object(forKey: AppStorageKey.approachWidth) as? Double {
            approachWidth = clamp(CGFloat(storedApproachWidth), min: approachWidthRange.lowerBound, max: approachWidthRange.upperBound)
        } else {
            approachWidth = 40
        }

        if let storedApproachHeight = defaults.object(forKey: AppStorageKey.approachHeight) as? Double {
            approachHeight = clamp(CGFloat(storedApproachHeight), min: approachHeightRange.lowerBound, max: approachHeightRange.upperBound)
        } else {
            approachHeight = 90
        }

        observedFolders = defaults.stringArray(forKey: AppStorageKey.observedFolders) ?? []

        calendarViewOption = defaults.integer(forKey: "calendarViewOption")
        customActionsLayoutOption = defaults.integer(forKey: "customActionsLayoutOption")
        showLauncherInPeeker = defaults.bool(forKey: "showLauncherInPeeker")
        showBookmarksInPeeker = defaults.bool(forKey: "showBookmarksInPeeker")
        showCombinedInPeeker = defaults.bool(forKey: "showCombinedInPeeker")

        if defaults.object(forKey: "showAddAppButton") == nil {
            showAddAppButton = true
        } else {
            showAddAppButton = defaults.bool(forKey: "showAddAppButton")
        }

        if defaults.object(forKey: "showAddBookmarkButton") == nil {
            showAddBookmarkButton = true
        } else {
            showAddBookmarkButton = defaults.bool(forKey: "showAddBookmarkButton")
        }

        if defaults.object(forKey: "launcherColumns") == nil {
            launcherColumns = 4
        } else {
            launcherColumns = defaults.integer(forKey: "launcherColumns")
        }

        if defaults.object(forKey: "bookmarkColumns") == nil {
            bookmarkColumns = 4
        } else {
            bookmarkColumns = defaults.integer(forKey: "bookmarkColumns")
        }

        if defaults.object(forKey: "launcherIconSize") == nil {
            launcherIconSize = 24
        } else {
            launcherIconSize = CGFloat(defaults.double(forKey: "launcherIconSize"))
        }

        if defaults.object(forKey: "launcherTextSize") == nil {
            launcherTextSize = 11
        } else {
            launcherTextSize = CGFloat(defaults.double(forKey: "launcherTextSize"))
        }

        if defaults.object(forKey: "launcherShowName") == nil {
            launcherShowName = true
        } else {
            launcherShowName = defaults.bool(forKey: "launcherShowName")
        }

        launcherDisplayMode = defaults.integer(forKey: "launcherDisplayMode")
        bookmarkDisplayMode = defaults.integer(forKey: "bookmarkDisplayMode")
        sharingTargetApps = defaults.stringArray(forKey: "sharingTargetApps") ?? []

        boxSlimModeEnabled = defaults.bool(forKey: "boxSlimModeEnabled")

        if defaults.object(forKey: "boxSlimModeHoldDuration") == nil {
            boxSlimModeHoldDuration = 1.5
        } else {
            boxSlimModeHoldDuration = defaults.double(forKey: "boxSlimModeHoldDuration")
        }

        if defaults.object(forKey: "boxSlimModeTrigger") == nil {
            boxSlimModeTrigger = 0
        } else {
            boxSlimModeTrigger = defaults.integer(forKey: "boxSlimModeTrigger")
        }

        if defaults.object(forKey: "boxSlimModeWiggleSensitivity") == nil {
            boxSlimModeWiggleSensitivity = 5.0
        } else {
            boxSlimModeWiggleSensitivity = defaults.double(forKey: "boxSlimModeWiggleSensitivity")
        }

        if defaults.object(forKey: "boxSlimModePosition") == nil {
            boxSlimModePosition = 0
        } else {
            boxSlimModePosition = defaults.integer(forKey: "boxSlimModePosition")
        }

        boxSlimModeKeepOpen = defaults.bool(forKey: "boxSlimModeKeepOpen")

        if defaults.object(forKey: "boxSlimModeExpandDirection") == nil {
            boxSlimModeExpandDirection = 0
        } else {
            boxSlimModeExpandDirection = defaults.integer(forKey: "boxSlimModeExpandDirection")
        }

        if defaults.object(forKey: "boxSlimModeMaxViewSize") == nil {
            boxSlimModeMaxViewSize = 5.0
        } else {
            let val = defaults.double(forKey: "boxSlimModeMaxViewSize")
            if val > 10.0 {
                boxSlimModeMaxViewSize = 5.0
            } else {
                boxSlimModeMaxViewSize = val
            }
        }

        if defaults.object(forKey: "boxSlimModeItemWidth") == nil {
            boxSlimModeItemWidth = 80.0
        } else {
            boxSlimModeItemWidth = defaults.double(forKey: "boxSlimModeItemWidth")
        }

        if defaults.object(forKey: "boxSlimModeItemHeight") == nil {
            boxSlimModeItemHeight = 80.0
        } else {
            boxSlimModeItemHeight = defaults.double(forKey: "boxSlimModeItemHeight")
        }

        if defaults.object(forKey: "boxSlimModeWidth") == nil {
            boxSlimModeWidth = 180.0
        } else {
            boxSlimModeWidth = defaults.double(forKey: "boxSlimModeWidth")
        }

        if defaults.object(forKey: "boxSlimModeHeight") == nil {
            boxSlimModeHeight = 260.0
        } else {
            boxSlimModeHeight = defaults.double(forKey: "boxSlimModeHeight")
        }

        // Custom Titles
        clipboardCustomTitle = defaults.string(forKey: AppStorageKey.clipboardCustomTitle)
        jotCustomTitle = defaults.string(forKey: AppStorageKey.jotCustomTitle)
        boxCustomTitle = defaults.string(forKey: AppStorageKey.boxCustomTitle)
        chronoCustomTitle = defaults.string(forKey: AppStorageKey.chronoCustomTitle)
        calendarCustomTitle = defaults.string(forKey: AppStorageKey.calendarCustomTitle)
        launcherCustomTitle = defaults.string(forKey: AppStorageKey.launcherCustomTitle)
        bookmarksCustomTitle = defaults.string(forKey: AppStorageKey.bookmarksCustomTitle)
        combinedCustomTitle = defaults.string(forKey: AppStorageKey.combinedCustomTitle)

        // Show Title Icons
        clipboardShowTitleIcon = defaults.object(forKey: AppStorageKey.clipboardShowTitleIcon) as? Bool
        jotShowTitleIcon = defaults.object(forKey: AppStorageKey.jotShowTitleIcon) as? Bool
        boxShowTitleIcon = defaults.object(forKey: AppStorageKey.boxShowTitleIcon) as? Bool
        chronoShowTitleIcon = defaults.object(forKey: AppStorageKey.chronoShowTitleIcon) as? Bool
        calendarShowTitleIcon = defaults.object(forKey: AppStorageKey.calendarShowTitleIcon) as? Bool
        launcherShowTitleIcon = defaults.object(forKey: AppStorageKey.launcherShowTitleIcon) as? Bool
        bookmarksShowTitleIcon = defaults.object(forKey: AppStorageKey.bookmarksShowTitleIcon) as? Bool
        combinedShowTitleIcon = defaults.object(forKey: AppStorageKey.combinedShowTitleIcon) as? Bool

        // Bookmark Layout Customizations
        if defaults.object(forKey: AppStorageKey.bookmarkIconSize) == nil {
            bookmarkIconSize = 24
        } else {
            bookmarkIconSize = CGFloat(defaults.double(forKey: AppStorageKey.bookmarkIconSize))
        }

        if defaults.object(forKey: AppStorageKey.bookmarkTextSize) == nil {
            bookmarkTextSize = 11
        } else {
            bookmarkTextSize = CGFloat(defaults.double(forKey: AppStorageKey.bookmarkTextSize))
        }

        if defaults.object(forKey: AppStorageKey.bookmarkShowName) == nil {
            bookmarkShowName = true
        } else {
            bookmarkShowName = defaults.bool(forKey: AppStorageKey.bookmarkShowName)
        }

        // Chrono Title Overrides
        chronoTitleAlignment = defaults.object(forKey: AppStorageKey.chronoTitleAlignment) as? Int
        chronoTitleSize = (defaults.object(forKey: AppStorageKey.chronoTitleSize) as? Double).map { CGFloat($0) }
        chronoTitleIconName = defaults.string(forKey: AppStorageKey.chronoTitleIconName)
        chronoTitleUseAccent = defaults.object(forKey: AppStorageKey.chronoTitleUseAccent) as? Bool
        chronoTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.chronoTitleRed,
            greenKey: AppStorageKey.chronoTitleGreen,
            blueKey: AppStorageKey.chronoTitleBlue,
            alphaKey: AppStorageKey.chronoTitleAlpha
        )

        // Calendar Title Overrides
        calendarTitleAlignment = defaults.object(forKey: AppStorageKey.calendarTitleAlignment) as? Int
        calendarTitleSize = (defaults.object(forKey: AppStorageKey.calendarTitleSize) as? Double).map { CGFloat($0) }
        calendarTitleIconName = defaults.string(forKey: AppStorageKey.calendarTitleIconName)
        calendarTitleUseAccent = defaults.object(forKey: AppStorageKey.calendarTitleUseAccent) as? Bool
        calendarTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.calendarTitleRed,
            greenKey: AppStorageKey.calendarTitleGreen,
            blueKey: AppStorageKey.calendarTitleBlue,
            alphaKey: AppStorageKey.calendarTitleAlpha
        )

        // Launcher Title Overrides
        launcherTitleAlignment = defaults.object(forKey: AppStorageKey.launcherTitleAlignment) as? Int
        launcherTitleSize = (defaults.object(forKey: AppStorageKey.launcherTitleSize) as? Double).map { CGFloat($0) }
        launcherTitleIconName = defaults.string(forKey: AppStorageKey.launcherTitleIconName)
        launcherTitleUseAccent = defaults.object(forKey: AppStorageKey.launcherTitleUseAccent) as? Bool
        launcherTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.launcherTitleRed,
            greenKey: AppStorageKey.launcherTitleGreen,
            blueKey: AppStorageKey.launcherTitleBlue,
            alphaKey: AppStorageKey.launcherTitleAlpha
        )

        // Bookmarks Title Overrides
        bookmarksTitleAlignment = defaults.object(forKey: AppStorageKey.bookmarksTitleAlignment) as? Int
        bookmarksTitleSize = (defaults.object(forKey: AppStorageKey.bookmarksTitleSize) as? Double).map { CGFloat($0) }
        bookmarksTitleIconName = defaults.string(forKey: AppStorageKey.bookmarksTitleIconName)
        bookmarksTitleUseAccent = defaults.object(forKey: AppStorageKey.bookmarksTitleUseAccent) as? Bool
        bookmarksTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.bookmarksTitleRed,
            greenKey: AppStorageKey.bookmarksTitleGreen,
            blueKey: AppStorageKey.bookmarksTitleBlue,
            alphaKey: AppStorageKey.bookmarksTitleAlpha
        )

        // Combined Title Overrides
        combinedTitleAlignment = defaults.object(forKey: AppStorageKey.combinedTitleAlignment) as? Int
        combinedTitleSize = (defaults.object(forKey: AppStorageKey.combinedTitleSize) as? Double).map { CGFloat($0) }
        combinedTitleIconName = defaults.string(forKey: AppStorageKey.combinedTitleIconName)
        combinedTitleUseAccent = defaults.object(forKey: AppStorageKey.combinedTitleUseAccent) as? Bool
        combinedTitleColor = AppSettings.loadOptionalColor(
            defaults: defaults,
            redKey: AppStorageKey.combinedTitleRed,
            greenKey: AppStorageKey.combinedTitleGreen,
            blueKey: AppStorageKey.combinedTitleBlue,
            alphaKey: AppStorageKey.combinedTitleAlpha
        )

        persistAccentColor()
        persistBackgroundColor()
        persistTitleColor()
    }

    func flushPendingWrites() {
        defaultsWriteQueue.sync {
            flushPendingWritesLocked()
        }
    }

    private func enqueueDefaultSet(_ value: Any, forKey key: String) {
        defaultsWriteQueue.async { [weak self] in
            guard let self else { return }
            self.pendingDefaultRemovals.remove(key)
            self.pendingDefaultWrites[key] = value
            self.scheduleDefaultsFlushLocked()
        }
    }

    private func enqueueDefaultRemove(forKey key: String) {
        defaultsWriteQueue.async { [weak self] in
            guard let self else { return }
            self.pendingDefaultWrites.removeValue(forKey: key)
            self.pendingDefaultRemovals.insert(key)
            self.scheduleDefaultsFlushLocked()
        }
    }

    private func scheduleDefaultsFlushLocked() {
        defaultsFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingWritesLocked()
        }
        defaultsFlushWorkItem = workItem
        defaultsWriteQueue.asyncAfter(deadline: .now() + defaultsWriteDelay, execute: workItem)
    }

    private func flushPendingWritesLocked() {
        defaultsFlushWorkItem?.cancel()
        defaultsFlushWorkItem = nil

        for key in pendingDefaultRemovals {
            defaults.removeObject(forKey: key)
        }
        pendingDefaultRemovals.removeAll()

        for (key, value) in pendingDefaultWrites {
            defaults.set(value, forKey: key)
        }
        pendingDefaultWrites.removeAll()
    }

    func updateHardwareNotchDimensions(x: CGFloat, width: CGFloat, height: CGFloat) {
        hardwareNotchX = x
        hardwareNotchWidth = width
        hardwareNotchHeight = height
    }

    private func persistAccentColor() {
        persistColor(
            accentColor,
            redKey: AppStorageKey.accentRed,
            greenKey: AppStorageKey.accentGreen,
            blueKey: AppStorageKey.accentBlue,
            alphaKey: AppStorageKey.accentAlpha
        )
    }

    private func persistBackgroundColor() {
        persistColor(
            backgroundColor,
            redKey: AppStorageKey.backgroundRed,
            greenKey: AppStorageKey.backgroundGreen,
            blueKey: AppStorageKey.backgroundBlue,
            alphaKey: AppStorageKey.backgroundAlpha
        )
    }

    private func persistTitleColor() {
        persistColor(
            titleColor,
            redKey: AppStorageKey.titleRed,
            greenKey: AppStorageKey.titleGreen,
            blueKey: AppStorageKey.titleBlue,
            alphaKey: AppStorageKey.titleAlpha
        )
    }

    private func persistOptionalColor(
        _ color: NSColor?,
        redKey: String,
        greenKey: String,
        blueKey: String,
        alphaKey: String
    ) {
        guard let color else {
            enqueueDefaultRemove(forKey: redKey)
            enqueueDefaultRemove(forKey: greenKey)
            enqueueDefaultRemove(forKey: blueKey)
            enqueueDefaultRemove(forKey: alphaKey)
            return
        }
        persistColor(color, redKey: redKey, greenKey: greenKey, blueKey: blueKey, alphaKey: alphaKey)
    }

    private func persistOptionalInt(_ value: Int?, key: String) {
        guard let value else {
            enqueueDefaultRemove(forKey: key)
            return
        }
        enqueueDefaultSet(value, forKey: key)
    }

    private func persistOptionalDouble(_ value: Double?, key: String) {
        guard let value else {
            enqueueDefaultRemove(forKey: key)
            return
        }
        enqueueDefaultSet(value, forKey: key)
    }

    private func persistOptionalBool(_ value: Bool?, key: String) {
        guard let value else {
            enqueueDefaultRemove(forKey: key)
            return
        }
        enqueueDefaultSet(value, forKey: key)
    }

    private func persistOptionalString(_ value: String?, key: String) {
        guard let value, !value.isEmpty else {
            enqueueDefaultRemove(forKey: key)
            return
        }
        enqueueDefaultSet(value, forKey: key)
    }

    private func persistColor(_ color: NSColor, redKey: String, greenKey: String, blueKey: String, alphaKey: String) {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        enqueueDefaultSet(Double(rgbColor.redComponent), forKey: redKey)
        enqueueDefaultSet(Double(rgbColor.greenComponent), forKey: greenKey)
        enqueueDefaultSet(Double(rgbColor.blueComponent), forKey: blueKey)
        enqueueDefaultSet(Double(rgbColor.alphaComponent), forKey: alphaKey)
    }

    private static func loadAccentColor(defaults: UserDefaults, fallback: NSColor) -> NSColor {
        loadColor(
            defaults: defaults,
            redKey: AppStorageKey.accentRed,
            greenKey: AppStorageKey.accentGreen,
            blueKey: AppStorageKey.accentBlue,
            alphaKey: AppStorageKey.accentAlpha,
            fallback: fallback
        )
    }

    private static func loadColor(
        defaults: UserDefaults,
        redKey: String,
        greenKey: String,
        blueKey: String,
        alphaKey: String,
        fallback: NSColor
    ) -> NSColor {
        guard let red = defaults.object(forKey: redKey) as? Double,
              let green = defaults.object(forKey: greenKey) as? Double,
              let blue = defaults.object(forKey: blueKey) as? Double,
              let alpha = defaults.object(forKey: alphaKey) as? Double else {
            return fallback
        }
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func loadOptionalColor(
        defaults: UserDefaults,
        redKey: String,
        greenKey: String,
        blueKey: String,
        alphaKey: String
    ) -> NSColor? {
        guard let red = defaults.object(forKey: redKey) as? Double,
              let green = defaults.object(forKey: greenKey) as? Double,
              let blue = defaults.object(forKey: blueKey) as? Double,
              let alpha = defaults.object(forKey: alphaKey) as? Double else {
            return nil
        }
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Reintegrated Settings

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case clip = "Clipboard"
    case jot = "Jot"
    case box = "Box"
    case chrono = "Chrono"
    case calendar = "Calendar"
    case launcherBookmarks = "Launcher/Bookmarks"
    case sharing = "Sharing"
    case advanced = "Advanced"
    case updates = "Updates"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintbrush"
        case .clip: return "doc.on.clipboard"
        case .jot: return "note.text"
        case .box: return "shippingbox.fill"
        case .chrono: return "timer"
        case .calendar: return "calendar"
        case .launcherBookmarks: return "square.grid.2x2"
        case .sharing: return "square.and.arrow.up"
        case .advanced: return "gearshape"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }
}
