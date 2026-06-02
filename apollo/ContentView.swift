//
//  apolloApp.swift
//  apollo
//

import SwiftUI
import AppKit
import Combine
import MediaPlayer

// MARK: - Lightweight Page Models
enum NotchPage: Int, CaseIterable {
    case clipboard = 0
    case nowPlaying = 1
    case box = 2
}

enum TitleAlignmentOption: Int, CaseIterable {
    case left = 0
    case center = 1
    case right = 2

    var label: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

enum ClipboardActionOption: Int, CaseIterable {
    case copy = 0
    case paste = 1

    var label: String {
        switch self {
        case .copy: return "Copy to clipboard"
        case .paste: return "Paste at cursor"
        }
    }
}

enum HoverPreviewFocus {
    case all
    case islandSize
    case notchEdge
    case approach
    case clipboardLimit
    case titleSize
    case cornerRadius
    case sensitivityCarousel
    case sensitivityClose
    case animationNotch
    case animationCarousel
    case animationSwipe
    case delayApproach
    case delayHoverClose
    case delaySwipeClose
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintbrush"
        case .advanced: return "gearshape"
        }
    }
}

struct ClipboardEntry: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let createdAt = Date()
}

struct BoxFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}

struct JotNote: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct ObservedFileToast: Identifiable, Hashable {
    let id = UUID()
    let fileURL: URL
    let folderURL: URL
    let createdAt = Date()
}

final class NowPlayingObserver: ObservableObject {
    @Published var currentTrack: String = "Not Playing"
    @Published var currentArtist: String = ""
    @Published var currentArtwork: NSImage?
    @Published var isPlaying = false

    func updateFromSystem() {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            currentTrack = "Not Playing"
            currentArtist = ""
            currentArtwork = nil
            isPlaying = false
            return
        }

        currentTrack = (info[MPMediaItemPropertyTitle] as? String)?.isEmpty == false ? (info[MPMediaItemPropertyTitle] as? String ?? "Not Playing") : "Not Playing"
        currentArtist = (info[MPMediaItemPropertyArtist] as? String) ?? ""
        if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
            isPlaying = rate > 0
        } else {
            isPlaying = false
        }

        if let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            currentArtwork = artwork.image(at: CGSize(width: 160, height: 160))
        } else {
            currentArtwork = nil
        }
    }
}

// MARK: - App Main Entry
@main
struct NotchHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Shared UI State
final class NotchMenuModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var expansionProgress: CGFloat = 0
    @Published var currentPage = 0
    @Published var clipboardItems: [ClipboardEntry] = []
    @Published var boxFiles: [BoxFile] = []
    @Published var jotNotes: [JotNote] = []
    @Published var activeJotID: UUID?
    @Published var clipboardPulseItemID: UUID?
    @Published var currentTrack: String = "Not Playing"
    @Published var currentArtist: String = ""
    @Published var currentArtwork: NSImage?
    @Published var isPlaying = false
    @Published var observedFileToast: ObservedFileToast?
    @Published var canCloseFromVerticalSwipe = false
    @Published var closeGestureProgress: CGFloat = 0
    @Published var carouselDragOffset: CGFloat = 0
    @Published var isToastDismissing = false
}

private enum AppStorageKey {
    static let clipboardHistory = "clipboardHistory"
    static let accentRed = "accentRed"
    static let accentGreen = "accentGreen"
    static let accentBlue = "accentBlue"
    static let accentAlpha = "accentAlpha"
    static let backgroundRed = "backgroundRed"
    static let backgroundGreen = "backgroundGreen"
    static let backgroundBlue = "backgroundBlue"
    static let backgroundAlpha = "backgroundAlpha"
    static let titleRed = "titleRed"
    static let titleGreen = "titleGreen"
    static let titleBlue = "titleBlue"
    static let titleAlpha = "titleAlpha"
    static let titleUseAccent = "titleUseAccent"
    static let clipboardTitleAlignment = "clipboardTitleAlignment"
    static let clipboardTitleSize = "clipboardTitleSize"
    static let clipboardTitleIconName = "clipboardTitleIconName"
    static let clipboardTitleUseAccent = "clipboardTitleUseAccent"
    static let clipboardTitleRed = "clipboardTitleRed"
    static let clipboardTitleGreen = "clipboardTitleGreen"
    static let clipboardTitleBlue = "clipboardTitleBlue"
    static let clipboardTitleAlpha = "clipboardTitleAlpha"
    static let jotTitleAlignment = "jotTitleAlignment"
    static let jotTitleSize = "jotTitleSize"
    static let jotTitleIconName = "jotTitleIconName"
    static let jotTitleUseAccent = "jotTitleUseAccent"
    static let jotTitleRed = "jotTitleRed"
    static let jotTitleGreen = "jotTitleGreen"
    static let jotTitleBlue = "jotTitleBlue"
    static let jotTitleAlpha = "jotTitleAlpha"
    static let boxTitleAlignment = "boxTitleAlignment"
    static let boxTitleSize = "boxTitleSize"
    static let boxTitleIconName = "boxTitleIconName"
    static let boxTitleUseAccent = "boxTitleUseAccent"
    static let boxTitleRed = "boxTitleRed"
    static let boxTitleGreen = "boxTitleGreen"
    static let boxTitleBlue = "boxTitleBlue"
    static let boxTitleAlpha = "boxTitleAlpha"
    static let notchWidth = "notchWidth"
    static let notchHeight = "notchHeight"
    static let defaultPage = "defaultPage"
    static let rememberClips = "rememberClips"
    static let jotNotes = "jotNotes"
    static let titleAlignment = "titleAlignment"
    static let titleSize = "titleSize"
    static let titleIconName = "titleIconName"
    static let cornerRadius = "cornerRadius"
    static let showPagers = "showPagers"
    static let showBoxFileNames = "showBoxFileNames"
    static let defaultToBoxIfItems = "defaultToBoxIfItems"
    static let clipboardAction = "clipboardAction"
    static let reopenLastPage = "reopenLastPage"
    static let lastVisitedPage = "lastVisitedPage"
    static let animationResponse = "animationResponse"
    static let animationDamping = "animationDamping"
    static let notchAnimationResponse = "notchAnimationResponse"
    static let notchAnimationDamping = "notchAnimationDamping"
    static let carouselAnimationResponse = "carouselAnimationResponse"
    static let carouselAnimationDamping = "carouselAnimationDamping"
    static let swipeAnimationResponse = "swipeAnimationResponse"
    static let swipeAnimationDamping = "swipeAnimationDamping"
    static let observedFolders = "observedFolders"
    static let proximitySensitivity = "proximitySensitivity"
    static let carouselSensitivity = "carouselSensitivity"
    static let closeSensitivity = "closeSensitivity"
    static let approachDelay = "approachDelay"
    static let hoverCloseDelay = "hoverCloseDelay"
    static let swipeCloseDelay = "swipeCloseDelay"
    static let disableApproach = "disableApproach"
    static let notchEdgeThickness = "notchEdgeThickness"
    static let approachWidth = "approachWidth"
    static let approachHeight = "approachHeight"
}

private func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
    return max(minValue, min(maxValue, value))
}

private func safeDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
    guard value.isFinite else { return fallback }
    return max(1, value)
}

private func scaledPanelWidth(for settings: AppSettings) -> CGFloat {
    let widthScale = clamp(settings.clampedNotchWidth / 210, min: 0.75, max: 1.6)
    return safeDimension(380 * widthScale, fallback: 380)
}

private func scaledPanelHeight(for settings: AppSettings) -> CGFloat {
    let heightScale = clamp(settings.clampedNotchHeight / 32, min: 0.75, max: 1.6)
    return safeDimension(160 * heightScale, fallback: 160)
}

private let baseNotchWidth: CGFloat = 210
private let baseNotchHeight: CGFloat = 32
private let toastPanelHeight: CGFloat = 260
private let toastPanelWidth: CGFloat = 180

private func hardwareNotchDimensions(for screen: NSScreen?) -> (width: CGFloat, height: CGFloat) {
    guard let screen else {
        return (baseNotchWidth, baseNotchHeight)
    }
    let topInset = screen.safeAreaInsets.top
    let horizontalDifferential = screen.frame.width - screen.visibleFrame.width
    let width = (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
    let height = topInset > 0 ? topInset : baseNotchHeight
    return (width, height)
}

private struct BottomRoundedRectangle: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = max(0, cornerRadius)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        let tl = CGPoint(x: rect.minX, y: rect.minY)

        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: CGPoint(x: br.x, y: br.y - radius))
        path.addQuadCurve(to: CGPoint(x: br.x - radius, y: br.y), control: br)
        path.addLine(to: CGPoint(x: bl.x + radius, y: bl.y))
        path.addQuadCurve(to: CGPoint(x: bl.x, y: bl.y - radius), control: bl)
        path.addLine(to: tl)
        path.closeSubpath()
        return path
    }
}

final class BoxIconCache {
    static let shared = BoxIconCache()
    private let cache = NSCache<NSURL, NSImage>()

    func icon(for url: URL) -> NSImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let defaultAccent = NSColor.systemGreen
    private let defaultBackground = NSColor.black
    private let defaultTitleColor: NSColor
    private let defaultNotchWidth: CGFloat = 210
    private let defaultNotchHeight: CGFloat = 32

    let notchWidthRange: ClosedRange<CGFloat> = 180...420
    let notchHeightRange: ClosedRange<CGFloat> = 24...80
    let rememberClipsRange: ClosedRange<Double> = 1...200
    let proximitySensitivityRange: ClosedRange<Double> = 0.3...2.4
    let carouselSensitivityRange: ClosedRange<Double> = 0.4...2.5
    let closeSensitivityRange: ClosedRange<Double> = 0.4...2.5
    let titleSizeRange: ClosedRange<CGFloat> = 10...20
    let cornerRadiusRange: ClosedRange<CGFloat> = 6...28
    let animationResponseRange: ClosedRange<Double> = 0.16...0.7
    let animationDampingRange: ClosedRange<Double> = 0.55...0.95
    let approachDelayRange: ClosedRange<Double> = 0...1.6
    let hoverCloseDelayRange: ClosedRange<Double> = 0...2.8
    let swipeCloseDelayRange: ClosedRange<Double> = 0...1.0
    let notchEdgeThicknessRange: ClosedRange<CGFloat> = 2...40
    let approachWidthRange: ClosedRange<CGFloat> = 0...160
    let approachHeightRange: ClosedRange<CGFloat> = 0...220

    private var isUpdating = false

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
            defaults.set(titleUseAccent, forKey: AppStorageKey.titleUseAccent)
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
            defaults.set(Double(notchWidth), forKey: AppStorageKey.notchWidth)
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
            defaults.set(Double(notchHeight), forKey: AppStorageKey.notchHeight)
        }
    }

    @Published var defaultPage: Int {
        didSet {
            let clampedValue = clamp(defaultPage, min: NotchPage.clipboard.rawValue, max: NotchPage.box.rawValue)
            if clampedValue != defaultPage {
                defaultPage = clampedValue
            }
            defaults.set(defaultPage, forKey: AppStorageKey.defaultPage)
        }
    }

    @Published var rememberClips: Int {
        didSet {
            guard !isUpdating else { return }
            let clampedValue: Int
            if rememberClips == 0 {
                clampedValue = 0
            } else {
                clampedValue = Int(clamp(Double(rememberClips), min: rememberClipsRange.lowerBound, max: rememberClipsRange.upperBound))
            }
            if clampedValue != rememberClips {
                isUpdating = true
                rememberClips = clampedValue
                isUpdating = false
                return
            }
            defaults.set(rememberClips, forKey: AppStorageKey.rememberClips)
        }
    }

    @Published var titleAlignment: Int {
        didSet {
            let clampedValue = clamp(titleAlignment, min: TitleAlignmentOption.left.rawValue, max: TitleAlignmentOption.right.rawValue)
            if clampedValue != titleAlignment {
                titleAlignment = clampedValue
            }
            defaults.set(titleAlignment, forKey: AppStorageKey.titleAlignment)
        }
    }

    @Published var titleSize: CGFloat {
        didSet {
            let clampedValue = clamp(titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
            if clampedValue != titleSize {
                titleSize = clampedValue
            }
            defaults.set(Double(titleSize), forKey: AppStorageKey.titleSize)
        }
    }

    @Published var titleIconName: String {
        didSet {
            defaults.set(titleIconName, forKey: AppStorageKey.titleIconName)
        }
    }

    @Published var cornerRadius: CGFloat {
        didSet {
            let clampedValue = clamp(cornerRadius, min: cornerRadiusRange.lowerBound, max: cornerRadiusRange.upperBound)
            if clampedValue != cornerRadius {
                cornerRadius = clampedValue
            }
            defaults.set(Double(cornerRadius), forKey: AppStorageKey.cornerRadius)
        }
    }

    @Published var showPagers: Bool {
        didSet {
            defaults.set(showPagers, forKey: AppStorageKey.showPagers)
        }
    }

    @Published var showBoxFileNames: Bool {
        didSet {
            defaults.set(showBoxFileNames, forKey: AppStorageKey.showBoxFileNames)
        }
    }

    @Published var defaultToBoxIfItems: Bool {
        didSet {
            defaults.set(defaultToBoxIfItems, forKey: AppStorageKey.defaultToBoxIfItems)
        }
    }

    @Published var clipboardAction: Int {
        didSet {
            let clampedValue = clamp(clipboardAction, min: ClipboardActionOption.copy.rawValue, max: ClipboardActionOption.paste.rawValue)
            if clampedValue != clipboardAction {
                clipboardAction = clampedValue
            }
            defaults.set(clipboardAction, forKey: AppStorageKey.clipboardAction)
        }
    }

    @Published var reopenLastPage: Bool {
        didSet {
            defaults.set(reopenLastPage, forKey: AppStorageKey.reopenLastPage)
        }
    }

    @Published var lastVisitedPage: Int {
        didSet {
            let clampedValue = clamp(lastVisitedPage, min: NotchPage.clipboard.rawValue, max: NotchPage.box.rawValue)
            if clampedValue != lastVisitedPage {
                lastVisitedPage = clampedValue
            }
            defaults.set(lastVisitedPage, forKey: AppStorageKey.lastVisitedPage)
        }
    }

    @Published var proximitySensitivity: Double {
        didSet {
            let clampedValue = clamp(proximitySensitivity, min: proximitySensitivityRange.lowerBound, max: proximitySensitivityRange.upperBound)
            if clampedValue != proximitySensitivity {
                proximitySensitivity = clampedValue
            }
            defaults.set(proximitySensitivity, forKey: AppStorageKey.proximitySensitivity)
        }
    }

    @Published var carouselSensitivity: Double {
        didSet {
            let clampedValue = clamp(carouselSensitivity, min: carouselSensitivityRange.lowerBound, max: carouselSensitivityRange.upperBound)
            if clampedValue != carouselSensitivity {
                carouselSensitivity = clampedValue
            }
            defaults.set(carouselSensitivity, forKey: AppStorageKey.carouselSensitivity)
        }
    }

    @Published var closeSensitivity: Double {
        didSet {
            let clampedValue = clamp(closeSensitivity, min: closeSensitivityRange.lowerBound, max: closeSensitivityRange.upperBound)
            if clampedValue != closeSensitivity {
                closeSensitivity = clampedValue
            }
            defaults.set(closeSensitivity, forKey: AppStorageKey.closeSensitivity)
        }
    }

    @Published var approachDelay: Double {
        didSet {
            let clampedValue = clamp(approachDelay, min: approachDelayRange.lowerBound, max: approachDelayRange.upperBound)
            if clampedValue != approachDelay {
                approachDelay = clampedValue
            }
            defaults.set(approachDelay, forKey: AppStorageKey.approachDelay)
        }
    }

    @Published var hoverCloseDelay: Double {
        didSet {
            let clampedValue = clamp(hoverCloseDelay, min: hoverCloseDelayRange.lowerBound, max: hoverCloseDelayRange.upperBound)
            if clampedValue != hoverCloseDelay {
                hoverCloseDelay = clampedValue
            }
            defaults.set(hoverCloseDelay, forKey: AppStorageKey.hoverCloseDelay)
        }
    }

    @Published var swipeCloseDelay: Double {
        didSet {
            let clampedValue = clamp(swipeCloseDelay, min: swipeCloseDelayRange.lowerBound, max: swipeCloseDelayRange.upperBound)
            if clampedValue != swipeCloseDelay {
                swipeCloseDelay = clampedValue
            }
            defaults.set(swipeCloseDelay, forKey: AppStorageKey.swipeCloseDelay)
        }
    }

    @Published var disableApproach: Bool {
        didSet {
            defaults.set(disableApproach, forKey: AppStorageKey.disableApproach)
        }
    }

    @Published var notchEdgeThickness: CGFloat {
        didSet {
            let clampedValue = clamp(notchEdgeThickness, min: notchEdgeThicknessRange.lowerBound, max: notchEdgeThicknessRange.upperBound)
            if clampedValue != notchEdgeThickness {
                notchEdgeThickness = clampedValue
            }
            defaults.set(Double(notchEdgeThickness), forKey: AppStorageKey.notchEdgeThickness)
        }
    }

    @Published var approachWidth: CGFloat {
        didSet {
            let clampedValue = clamp(approachWidth, min: approachWidthRange.lowerBound, max: approachWidthRange.upperBound)
            if clampedValue != approachWidth {
                approachWidth = clampedValue
            }
            defaults.set(Double(approachWidth), forKey: AppStorageKey.approachWidth)
        }
    }

    @Published var approachHeight: CGFloat {
        didSet {
            let clampedValue = clamp(approachHeight, min: approachHeightRange.lowerBound, max: approachHeightRange.upperBound)
            if clampedValue != approachHeight {
                approachHeight = clampedValue
            }
            defaults.set(Double(approachHeight), forKey: AppStorageKey.approachHeight)
        }
    }

    @Published var showHoverPreviews: Bool = false
    @Published var hoverPreviewFocus: HoverPreviewFocus = .all
    @Published var hoverPreviewTitlePage: NotchPage = .clipboard

    @Published var animationResponse: Double {
        didSet {
            let clampedValue = clamp(animationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != animationResponse {
                animationResponse = clampedValue
            }
            defaults.set(animationResponse, forKey: AppStorageKey.animationResponse)
        }
    }

    @Published var animationDamping: Double {
        didSet {
            let clampedValue = clamp(animationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != animationDamping {
                animationDamping = clampedValue
            }
            defaults.set(animationDamping, forKey: AppStorageKey.animationDamping)
        }
    }

    @Published var notchAnimationResponse: Double {
        didSet {
            let clampedValue = clamp(notchAnimationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != notchAnimationResponse {
                notchAnimationResponse = clampedValue
            }
            defaults.set(notchAnimationResponse, forKey: AppStorageKey.notchAnimationResponse)
        }
    }

    @Published var notchAnimationDamping: Double {
        didSet {
            let clampedValue = clamp(notchAnimationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != notchAnimationDamping {
                notchAnimationDamping = clampedValue
            }
            defaults.set(notchAnimationDamping, forKey: AppStorageKey.notchAnimationDamping)
        }
    }

    @Published var carouselAnimationResponse: Double {
        didSet {
            let clampedValue = clamp(carouselAnimationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != carouselAnimationResponse {
                carouselAnimationResponse = clampedValue
            }
            defaults.set(carouselAnimationResponse, forKey: AppStorageKey.carouselAnimationResponse)
        }
    }

    @Published var carouselAnimationDamping: Double {
        didSet {
            let clampedValue = clamp(carouselAnimationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != carouselAnimationDamping {
                carouselAnimationDamping = clampedValue
            }
            defaults.set(carouselAnimationDamping, forKey: AppStorageKey.carouselAnimationDamping)
        }
    }

    @Published var swipeAnimationResponse: Double {
        didSet {
            let clampedValue = clamp(swipeAnimationResponse, min: animationResponseRange.lowerBound, max: animationResponseRange.upperBound)
            if clampedValue != swipeAnimationResponse {
                swipeAnimationResponse = clampedValue
            }
            defaults.set(swipeAnimationResponse, forKey: AppStorageKey.swipeAnimationResponse)
        }
    }

    @Published var swipeAnimationDamping: Double {
        didSet {
            let clampedValue = clamp(swipeAnimationDamping, min: animationDampingRange.lowerBound, max: animationDampingRange.upperBound)
            if clampedValue != swipeAnimationDamping {
                swipeAnimationDamping = clampedValue
            }
            defaults.set(swipeAnimationDamping, forKey: AppStorageKey.swipeAnimationDamping)
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
            defaults.set(observedFolders, forKey: AppStorageKey.observedFolders)
        }
    }

    var clampedNotchWidth: CGFloat {
        let safeValue = notchWidth.isFinite ? notchWidth : defaultNotchWidth
        return clamp(safeValue, min: notchWidthRange.lowerBound, max: notchWidthRange.upperBound)
    }

    var clampedNotchHeight: CGFloat {
        let safeValue = notchHeight.isFinite ? notchHeight : defaultNotchHeight
        return clamp(safeValue, min: notchHeightRange.lowerBound, max: notchHeightRange.upperBound)
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

    var springAnimation: Animation {
        .spring(response: notchAnimationResponse, dampingFraction: notchAnimationDamping)
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

    func titleAlignment(for page: NotchPage) -> TitleAlignmentOption {
        switch page {
        case .clipboard:
            return TitleAlignmentOption(rawValue: clipboardTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .nowPlaying:
            return TitleAlignmentOption(rawValue: jotTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .box:
            return TitleAlignmentOption(rawValue: boxTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        }
    }

    func titleSize(for page: NotchPage) -> CGFloat {
        switch page {
        case .clipboard:
            return clamp(clipboardTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .nowPlaying:
            return clamp(jotTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .box:
            return clamp(boxTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        }
    }

    func titleColor(for page: NotchPage) -> NSColor {
        let mainColor = effectiveTitleColor
        switch page {
        case .clipboard:
            if clipboardTitleUseAccent == true {
                return accentColor
            }
            if let override = clipboardTitleColor {
                return override
            }
            if clipboardTitleUseAccent == false {
                return titleColor
            }
            return mainColor
        case .nowPlaying:
            if jotTitleUseAccent == true {
                return accentColor
            }
            if let override = jotTitleColor {
                return override
            }
            if jotTitleUseAccent == false {
                return titleColor
            }
            return mainColor
        case .box:
            if boxTitleUseAccent == true {
                return accentColor
            }
            if let override = boxTitleColor {
                return override
            }
            if boxTitleUseAccent == false {
                return titleColor
            }
            return mainColor
        }
    }

    func titleSymbol(for page: NotchPage, fallback: String) -> String {
        let mainSymbol = titleIconName.isEmpty ? fallback : titleIconName
        switch page {
        case .clipboard:
            if let override = clipboardTitleIconName, !override.isEmpty {
                return override
            }
        case .nowPlaying:
            if let override = jotTitleIconName, !override.isEmpty {
                return override
            }
        case .box:
            if let override = boxTitleIconName, !override.isEmpty {
                return override
            }
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
            defaultPage = NotchPage.clipboard.rawValue
        } else {
            defaultPage = clamp(defaults.integer(forKey: AppStorageKey.defaultPage), min: NotchPage.clipboard.rawValue, max: NotchPage.box.rawValue)
        }
        if defaults.object(forKey: AppStorageKey.rememberClips) == nil {
            rememberClips = 40
        } else {
            let storedValue = defaults.integer(forKey: AppStorageKey.rememberClips)
            if storedValue == 0 {
                rememberClips = 0
            } else {
                rememberClips = clamp(storedValue, min: Int(rememberClipsRange.lowerBound), max: Int(rememberClipsRange.upperBound))
            }
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

        if defaults.object(forKey: AppStorageKey.lastVisitedPage) == nil {
            lastVisitedPage = NotchPage.clipboard.rawValue
        } else {
            lastVisitedPage = clamp(defaults.integer(forKey: AppStorageKey.lastVisitedPage), min: NotchPage.clipboard.rawValue, max: NotchPage.box.rawValue)
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
            disableApproach = false
        } else {
            disableApproach = defaults.bool(forKey: AppStorageKey.disableApproach)
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

        persistAccentColor()
        persistBackgroundColor()
        persistTitleColor()
    }

    func applySystemNotchDefaultsIfNeeded(width: CGFloat, height: CGFloat) {
        if defaults.object(forKey: AppStorageKey.notchWidth) == nil {
            notchWidth = width
        }
        if defaults.object(forKey: AppStorageKey.notchHeight) == nil {
            notchHeight = height
        }
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
            defaults.removeObject(forKey: redKey)
            defaults.removeObject(forKey: greenKey)
            defaults.removeObject(forKey: blueKey)
            defaults.removeObject(forKey: alphaKey)
            return
        }
        persistColor(color, redKey: redKey, greenKey: greenKey, blueKey: blueKey, alphaKey: alphaKey)
    }

    private func persistOptionalInt(_ value: Int?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    private func persistOptionalDouble(_ value: Double?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    private func persistOptionalBool(_ value: Bool?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    private func persistOptionalString(_ value: String?, key: String) {
        guard let value, !value.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    private func persistColor(_ color: NSColor, redKey: String, greenKey: String, blueKey: String, alphaKey: String) {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        defaults.set(Double(rgbColor.redComponent), forKey: redKey)
        defaults.set(Double(rgbColor.greenComponent), forKey: greenKey)
        defaults.set(Double(rgbColor.blueComponent), forKey: blueKey)
        defaults.set(Double(rgbColor.alphaComponent), forKey: alphaKey)
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

private struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selection: SettingsSection? = .general
    @State private var selectedTitlePage: NotchPage = .clipboard
    @State private var showTitleOverrides = false
    @State private var showAdvancedAnimation = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        let _ = formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 200
        return formatter
    }()

    var body: some View {
        let accent = Color(settings.accentColor)
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbolName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .finderSidebarStyle()
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    generalSettings
                case .appearance:
                    appearanceSettings
                case .advanced:
                    advancedSettings
                }
            }
            .scrollContentBackground(.hidden)
            .finderDetailStyle()
            .navigationSplitViewColumnWidth(min: 520, ideal: 700, max: 900)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 620)
        .tint(accent)
        .controlSize(.regular)
        .toggleStyle(.switch)
        .background(
            LinearGradient(
                colors: [
                    Color(settings.backgroundColor).opacity(0.35),
                    Color(settings.backgroundColor).opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            settings.showHoverPreviews = true
        }
        .onDisappear {
            settings.showHoverPreviews = false
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
                    ForEach(NotchPage.allCases, id: \.rawValue) { page in
                        Text(page == .clipboard ? "Clip" : page == .nowPlaying ? "Jot" : "")
                            .tag(page.rawValue)
                    }
                }
                .disabled(settings.reopenLastPage)

                Toggle("Reopen last page", isOn: $settings.reopenLastPage)
                    .help("Overrides Default Page when enabled")

                Toggle("Default to Box if it has items", isOn: $settings.defaultToBoxIfItems)
            }

            Section("Clipboard") {
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
                    TextField("Limit", value: $settings.rememberClips, formatter: Self.numberFormatter)
                        .frame(width: 60)
                }
                Text("Set to 0 for unlimited")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Clip action", selection: $settings.clipboardAction) {
                    ForEach(ClipboardActionOption.allCases, id: \.rawValue) { action in
                        Text(action.label)
                            .tag(action.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if settings.clipboardActionOption == .paste {
                    Text("Paste requires Accessibility permission for NotchHub")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Box") {
                Toggle("Show file names in Box", isOn: $settings.showBoxFileNames)
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
                }
            }
        }
        .finderFormStyle()
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

                DisclosureGroup("Titles", isExpanded: $showTitleOverrides) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Page", selection: $selectedTitlePage) {
                            ForEach(NotchPage.allCases, id: \.rawValue) { page in
                                Text(titlePageLabel(page))
                                    .tag(page)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Alignment", selection: pageTitleAlignmentBinding(selectedTitlePage)) {
                            ForEach(TitleAlignmentOption.allCases, id: \.rawValue) { option in
                                Text(option.label)
                                    .tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("Size")
                            Slider(value: pageTitleSizeBinding(selectedTitlePage), in: settings.titleSizeRange, onEditingChanged: { isEditing in
                                setTitlePreviewFocus(isEditing: isEditing, page: selectedTitlePage)
                            })
                            Text("\(Int(settings.titleSize(for: selectedTitlePage)))")
                                .frame(width: 36, alignment: .trailing)
                        }

                        HStack {
                            Spacer()
                            ColorPicker("Color", selection: pageTitleColorBinding(selectedTitlePage))
                                .disabled(pageTitleUseAccentBinding(selectedTitlePage).wrappedValue)
                            Toggle("Use accent", isOn: pageTitleUseAccentBinding(selectedTitlePage))
                                .toggleStyle(.switch)
                        }

                        HStack(spacing: 10) {
                            TextField("SF Symbol", text: pageTitleSymbolBinding(selectedTitlePage))
                                .textFieldStyle(.roundedBorder)
                            Image(systemName: settings.titleSymbol(for: selectedTitlePage, fallback: "textformat"))
                                .foregroundColor(Color(settings.titleColor(for: selectedTitlePage)))
                        }

                        HStack {
                            Button("Reset page overrides") {
                                resetTitleOverrides(for: selectedTitlePage)
                            }
                            .buttonStyle(.bordered)

                            Text("Overrides stay empty until you change them.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 6)
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

                Toggle("Show pagers", isOn: $settings.showPagers)
            }
        }
        .finderFormStyle()
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

                Toggle("Disable approach", isOn: $settings.disableApproach)
                    .help("Only opens when directly hovering over the notch")
            }
        }
        .finderFormStyle()
    }

    private func setPreviewFocus(_ focus: HoverPreviewFocus, isEditing: Bool) {
        settings.hoverPreviewFocus = isEditing ? focus : .all
    }

    private func setTitlePreviewFocus(isEditing: Bool, page: NotchPage? = nil) {
        if let page {
            settings.hoverPreviewTitlePage = page
        }
        setPreviewFocus(.titleSize, isEditing: isEditing)
    }

    private func titlePageLabel(_ page: NotchPage) -> String {
        switch page {
        case .clipboard: return "Clipboard"
        case .nowPlaying: return "Jot"
        case .box: return "Box"
        }
    }

    private func pageTitleAlignmentBinding(_ page: NotchPage) -> Binding<Int> {
        Binding(
            get: { settings.titleAlignment(for: page).rawValue },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleAlignment = newValue
                case .nowPlaying:
                    settings.jotTitleAlignment = newValue
                case .box:
                    settings.boxTitleAlignment = newValue
                }
            }
        )
    }

    private func pageTitleSizeBinding(_ page: NotchPage) -> Binding<CGFloat> {
        Binding(
            get: { settings.titleSize(for: page) },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleSize = newValue
                case .nowPlaying:
                    settings.jotTitleSize = newValue
                case .box:
                    settings.boxTitleSize = newValue
                }
            }
        )
    }

    private func pageTitleColorBinding(_ page: NotchPage) -> Binding<Color> {
        Binding(
            get: { Color(settings.titleColor(for: page)) },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleColor = NSColor(newValue)
                case .nowPlaying:
                    settings.jotTitleColor = NSColor(newValue)
                case .box:
                    settings.boxTitleColor = NSColor(newValue)
                }
            }
        )
    }

    private func pageTitleUseAccentBinding(_ page: NotchPage) -> Binding<Bool> {
        Binding(
            get: {
                switch page {
                case .clipboard:
                    return settings.clipboardTitleUseAccent ?? false
                case .nowPlaying:
                    return settings.jotTitleUseAccent ?? false
                case .box:
                    return settings.boxTitleUseAccent ?? false
                }
            },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleUseAccent = newValue
                case .nowPlaying:
                    settings.jotTitleUseAccent = newValue
                case .box:
                    settings.boxTitleUseAccent = newValue
                }
            }
        )
    }

    private func pageTitleSymbolBinding(_ page: NotchPage) -> Binding<String> {
        Binding(
            get: {
                switch page {
                case .clipboard:
                    return settings.clipboardTitleIconName ?? ""
                case .nowPlaying:
                    return settings.jotTitleIconName ?? ""
                case .box:
                    return settings.boxTitleIconName ?? ""
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmed.isEmpty ? nil : trimmed
                switch page {
                case .clipboard:
                    settings.clipboardTitleIconName = value
                case .nowPlaying:
                    settings.jotTitleIconName = value
                case .box:
                    settings.boxTitleIconName = value
                }
            }
        )
    }

    private func resetTitleOverrides(for page: NotchPage) {
        switch page {
        case .clipboard:
            settings.clipboardTitleAlignment = nil
            settings.clipboardTitleSize = nil
            settings.clipboardTitleIconName = nil
            settings.clipboardTitleUseAccent = nil
            settings.clipboardTitleColor = nil
        case .nowPlaying:
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
}

private func loadClipboardHistory() -> [ClipboardEntry] {
    let savedTexts = UserDefaults.standard.stringArray(forKey: AppStorageKey.clipboardHistory) ?? []
    return savedTexts.map { ClipboardEntry(text: $0) }
}

private extension View {
    func finderSidebarStyle() -> some View {
        background(.thinMaterial)
            .overlay(alignment: .trailing) {
                Divider().opacity(0.6)
            }
            .padding(.leading, 6)
            .padding(.vertical, 6)
    }

    func finderDetailStyle() -> some View {
        background(.regularMaterial)
            .overlay(alignment: .top) {
                Divider().opacity(0.5)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
    }

    func finderFormStyle() -> some View {
        formStyle(.grouped)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }
}

private func persistClipboardHistory(_ entries: [ClipboardEntry]) {
    UserDefaults.standard.set(entries.map(\.text), forKey: AppStorageKey.clipboardHistory)
}

private func loadJotNotes() -> [JotNote] {
    guard let data = UserDefaults.standard.data(forKey: AppStorageKey.jotNotes),
          let notes = try? JSONDecoder().decode([JotNote].self, from: data) else {
        return []
    }
    return notes
}

private func persistJotNotes(_ notes: [JotNote]) {
    guard let data = try? JSONEncoder().encode(notes) else { return }
    UserDefaults.standard.set(data, forKey: AppStorageKey.jotNotes)
}

// MARK: - Global Coordinate Proximity Driver
class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchPanel!
    private var mouseTimer: DispatchSourceTimer?
    private var mousePollingInterval: TimeInterval = 0.2
    private var lastMousePoint = NSPoint.zero
    private var clipboardTimer: DispatchSourceTimer?
    private var nowPlayingTimer: Timer?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private let model = NotchMenuModel()
    private let settings = AppSettings.shared
    private var settingsCancellables = Set<AnyCancellable>()
    private var lastMouseEvaluationTime: TimeInterval = 0
    private let mouseEvaluationInterval: TimeInterval = 0.1
    private var approachStartTime: TimeInterval?
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var swipeCloseWorkItem: DispatchWorkItem?
    private var notchPreviewWorkItem: DispatchWorkItem?
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private var folderMonitors: [String: FolderMonitor] = [:]
    private var folderSnapshots: [String: Set<String>] = [:]
    private var suppressProximityUntilExit = false
    
    // Dynamic structural dimensions
    private var notchWidth: CGFloat = 210
    private var notchHeight: CGFloat = 32
    private var panelWidth: CGFloat = 380
    private var panelHeight: CGFloat = 160
    
    // Proximity variables
    private let activationYBuffer: CGFloat = 80
    private let exactTriggerPadding: CGFloat = 20
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        calculateScreenNotchDimensions()
        model.currentPage = settings.reopenLastPage ? settings.lastVisitedPage : settings.defaultPage
        setupNotchWindow()
        setupStatusItem()
        observeSettings()
        startGlobalProximityTracking()
        startBackgroundStateTracking()
        if settings.reopenLastPage {
            model.currentPage = settings.lastVisitedPage
        } else {
            model.currentPage = settings.defaultPage
        }
        model.clipboardItems = loadClipboardHistory()
        model.jotNotes = loadJotNotes()
        applyClipboardLimitIfNeeded()
        persistClipboardHistory(model.clipboardItems)
        persistJotNotes(model.jotNotes)
        refreshNativeState()
    }
    
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchHub")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        item.menu = makeStatusMenu()
        statusItem = item
    }
    
    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Notch", action: #selector(showNotchFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pin Notch", action: #selector(togglePinnedState), keyEquivalent: ""))
        let settingsItem = NSMenuItem()
        settingsItem.view = NSHostingView(rootView: SettingsLink {
            Text("Settings...")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
        })
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }
    
    @objc private func statusItemClicked(_ sender: Any?) {
        togglePinnedState()
    }
    
    @objc private func showNotchFromMenu() {
        showPanel(expanded: true, pinned: true)
    }

    @objc private func togglePinnedState() {
        model.isPinned.toggle()
        if model.isPinned {
            showPanel(expanded: true, pinned: true)
        } else if !model.isExpanded {
            hidePanel()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func calculateScreenNotchDimensions() {
        guard let screen = NSScreen.screens.first else { return }
        let topInset = screen.safeAreaInsets.top
        let horizontalDifferential = screen.frame.width - screen.visibleFrame.width
        if topInset > 0 {
            let defaultWidth = (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : notchWidth
            settings.applySystemNotchDefaultsIfNeeded(width: defaultWidth, height: topInset)
        }
        applySettingsNotchSize()
    }

    private func applySettingsNotchSize() {
        notchWidth = settings.clampedNotchWidth
        notchHeight = settings.clampedNotchHeight
        panelWidth = scaledPanelWidth(for: settings)
        panelHeight = scaledPanelHeight(for: settings)
    }

    private func observeSettings() {
        settings.$notchWidth
            .combineLatest(settings.$notchHeight)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.applySettingsNotchSize()
                self.updateNotchWindowFrame()
                self.previewNotchResize()
            }
            .store(in: &settingsCancellables)

        settings.$rememberClips
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyClipboardLimitIfNeeded()
                persistClipboardHistory(self.model.clipboardItems)
            }
            .store(in: &settingsCancellables)

        settings.$defaultPage
            .sink { [weak self] _ in
                guard let self, !self.model.isExpanded, !self.settings.reopenLastPage else { return }
                self.model.currentPage = self.settings.defaultPage
            }
            .store(in: &settingsCancellables)

        model.$currentPage
            .sink { [weak self] page in
                self?.settings.lastVisitedPage = page
            }
            .store(in: &settingsCancellables)

        settings.$observedFolders
            .sink { [weak self] folders in
                self?.configureFolderMonitors(with: folders)
            }
            .store(in: &settingsCancellables)

        model.$jotNotes
            .sink { notes in
                persistJotNotes(notes)
            }
            .store(in: &settingsCancellables)

        settings.$hoverPreviewFocus
            .sink { [weak self] focus in
                guard let self else { return }
                if focus == .all {
                    if !self.model.isExpanded && !self.model.isPinned {
                        self.hidePanel()
                    }
                } else {
                    self.showSettingsPreview()
                }
            }
            .store(in: &settingsCancellables)
    }

    private func showSettingsPreview() {
        guard let window = notchWindow else { return }
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
        approachStartTime = nil
        model.isExpanded = false
        model.isPinned = false
        model.expansionProgress = 0.0
        model.closeGestureProgress = 0
        model.carouselDragOffset = 0
        updateNotchWindowFrame(heightOverride: panelHeight)
        window.alphaValue = 1.0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
    }

    private func notchTopAnchorY(for screen: NSScreen) -> CGFloat {
        screen.frame.maxY
    }

    private func windowY(for screen: NSScreen, windowHeight: CGFloat, collapsedNotchHeight: CGFloat, isExpanded: Bool) -> CGFloat {
        let anchorTop = notchTopAnchorY(for: screen)
        return isExpanded ? (anchorTop - windowHeight) : (anchorTop - collapsedNotchHeight)
    }

    private func updateNotchWindowFrame(widthOverride: CGFloat? = nil, heightOverride: CGFloat? = nil) {
        guard let screen = NSScreen.screens.first, let window = notchWindow else { return }
        let screenRect = screen.frame
        let defaultWidth = max(panelWidth, notchWidth)
        let windowWidth = widthOverride ?? defaultWidth
        let windowHeight = heightOverride ?? panelHeight
        let windowX = (screenRect.width - windowWidth) / 2
        let hardware = hardwareNotchDimensions(for: screen)
        let windowY = windowY(
            for: screen,
            windowHeight: windowHeight,
            collapsedNotchHeight: hardware.height,
            isExpanded: model.isExpanded
        )

        window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true)
    }

    private func previewNotchResize() {
        notchPreviewWorkItem?.cancel()
        notchPreviewWorkItem = nil

        if model.isPinned {
            showPanel(expanded: true, pinned: true)
            return
        }

        showPanel(expanded: true, pinned: false)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isPinned else { return }
            self.hidePanel()
        }
        notchPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
    
    private func setupNotchWindow() {
        guard let screen = NSScreen.screens.first else { return }
        let screenRect = screen.frame

        let windowWidth = max(panelWidth, notchWidth)
        let windowHeight = panelHeight
        let windowX = (screenRect.width - windowWidth) / 2
        let hardware = hardwareNotchDimensions(for: screen)
        let windowY = windowY(
            for: screen,
            windowHeight: windowHeight,
            collapsedNotchHeight: hardware.height,
            isExpanded: false
        )

        let initialRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        notchWindow = NotchPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        notchWindow.backgroundColor = .clear
        notchWindow.isOpaque = false
        notchWindow.hasShadow = false
        notchWindow.level = .statusBar + 2
        notchWindow.alphaValue = 0.0
        notchWindow.ignoresMouseEvents = true
        notchWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        notchWindow.isActiveProvider = { [weak self] in
            guard let self else { return false }
            return self.model.isExpanded || self.model.isPinned
        }
        notchWindow.canTriggerVertical = { [weak self] in
            self?.model.canCloseFromVerticalSwipe ?? false
        }
        notchWindow.onSwipeLeft = { [weak self] in
            self?.advancePage(direction: 1)
        }
        notchWindow.onSwipeRight = { [weak self] in
            self?.advancePage(direction: -1)
        }
        notchWindow.onSwipeUp = { [weak self] in
            self?.closeNotchFromSwipe()
        }
        notchWindow.onCloseProgressLegacy = { [weak self] progress, animate in
            guard let self else { return }
            let clamped = max(0, min(1, progress))
            if animate {
                if clamped == 0 {
                    withAnimation(.easeOut(duration: 0.05)) {
                        self.model.closeGestureProgress = clamped
                    }
                } else {
                    withAnimation(self.settings.swipeAnimation) {
                        self.model.closeGestureProgress = clamped
                    }
                }
            } else {
                self.model.closeGestureProgress = clamped
            }
        }
        notchWindow.onCarouselOffset = { [weak self] offset, animate in
            guard let self else { return }
            if animate {
                withAnimation(.easeOut(duration: 0.05)) {
                    self.model.carouselDragOffset = offset
                }
            } else {
                self.model.carouselDragOffset = offset
            }
        }
        notchWindow.carouselSensitivityProvider = { [weak self] in
            self?.settings.clampedCarouselSensitivity ?? 1.0
        }
        notchWindow.closeSensitivityProvider = { [weak self] in
            self?.settings.clampedCloseSensitivity ?? 1.0
        }
        
        let rootHubView = UnifiedNotchContainer(model: model, settings: settings)
        
        notchWindow.contentView = NSHostingView(rootView: rootHubView)
        notchWindow.orderFrontRegardless()
    }

    private func advancePage(direction: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.carouselDragOffset = 0
            withAnimation(self.settings.carouselAnimation) {
                let next = clamp(self.model.currentPage + direction, min: NotchPage.clipboard.rawValue, max: NotchPage.box.rawValue)
                self.model.currentPage = next
            }
        }
    }

    private func startBackgroundStateTracking() {
        startClipboardObservation()
    }

    private func startClipboardObservation() {
        if clipboardTimer != nil { return }
        pollClipboard()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 0.4, repeating: 0.8, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.pollClipboard()
        }
        timer.resume()
        clipboardTimer = timer
    }

    func updateObservationState(for page: Int) {
        _ = page
    }

    private func refreshNativeState() {
        pollClipboard()
        refreshNowPlayingState()
    }

    private func pollClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentChangeCount

        guard let rawText = pasteboard.string(forType: .string) else { return }
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard model.clipboardItems.first?.text != trimmedText else { return }

        model.clipboardItems.removeAll { $0.text == trimmedText }
        model.clipboardItems.insert(ClipboardEntry(text: trimmedText), at: 0)
        applyClipboardLimitIfNeeded()
        persistClipboardHistory(model.clipboardItems)
    }

    private func refreshNowPlayingState() {
        if let info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           let title = info[MPMediaItemPropertyTitle] as? String,
           !title.isEmpty {
            model.currentTrack = title
            model.currentArtist = (info[MPMediaItemPropertyArtist] as? String) ?? ""
            if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
                model.isPlaying = rate > 0
            } else {
                model.isPlaying = true
            }
        } else {
            model.currentTrack = "Not Playing"
            model.currentArtist = ""
            model.isPlaying = false
        }
    }

    func copyClipboardEntry(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        model.clipboardPulseItemID = entry.id
        model.clipboardItems.removeAll { $0.text == entry.text }
        model.clipboardItems.insert(ClipboardEntry(text: entry.text), at: 0)
        applyClipboardLimitIfNeeded()
        persistClipboardHistory(model.clipboardItems)
    }

    private func applyClipboardLimitIfNeeded() {
        guard let limit = settings.effectiveRememberClips else { return }
        if model.clipboardItems.count > limit {
            model.clipboardItems = Array(model.clipboardItems.prefix(limit))
        }
    }

    func addBoxItems(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls.reversed() {
            if !model.boxFiles.contains(where: { $0.url == url }) {
                model.boxFiles.insert(BoxFile(url: url), at: 0)
            }
        }
        showPanel(expanded: true, pinned: false, preferredPage: NotchPage.box.rawValue)
    }

    func openBoxPage() {
        showPanel(expanded: true, pinned: false, preferredPage: NotchPage.box.rawValue)
    }

    func closeNotchFromSwipe() {
        guard !model.isPinned else { return }
        suppressProximityUntilExit = true
        swipeCloseWorkItem?.cancel()
        swipeCloseWorkItem = nil
        let delay = settings.swipeCloseDelay
        if delay <= 0 {
            hidePanel()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.hidePanel()
        }
        swipeCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func togglePlayback() {
        postMediaPlayPauseKey()
        refreshNowPlayingState()
    }

    func postPasteCommand() {
        let keyCodeV: CGKeyCode = 9
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func runAppleScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                _ = appleScript.executeAndReturnError(&err)
            }
        }
    }

    func postMediaNext() {
        runAppleScript("tell application \"Music\" to next track")
        runAppleScript("tell application \"Spotify\" to next track")
    }

    func postMediaPrevious() {
        runAppleScript("tell application \"Music\" to previous track")
        runAppleScript("tell application \"Spotify\" to previous track")
    }

    private func postMediaPlayPauseKey() {
        let playPauseKeyCode = 16
        let keyDownData = (playPauseKeyCode << 16) | (0x0A << 8)
        let keyUpData = (playPauseKeyCode << 16) | (0x0B << 8)
        let modifierFlags = NSEvent.ModifierFlags(rawValue: 0xA00)

        let keyDownEvent = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyDownData,
            data2: -1
        )
        let keyUpEvent = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyUpData,
            data2: -1
        )

        keyDownEvent?.cgEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.cgEvent?.post(tap: .cghidEventTap)
    }
    
    private func startGlobalProximityTracking() {
        startMousePolling()
    }

    private func startMousePolling() {
        if mouseTimer != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + mousePollingInterval, repeating: mousePollingInterval, leeway: .milliseconds(140))
        timer.setEventHandler { [weak self] in
            self?.pollMouseLocation()
        }
        timer.resume()
        clipboardTimer = timer
    }

    private func pollMouseLocation() {
        guard let screen = NSScreen.screens.first else { return }
        let globalPoint = NSEvent.mouseLocation
        let screenRect = screen.frame
        let mouseX = globalPoint.x
        let mouseY = globalPoint.y

        let deltaX = abs(mouseX - lastMousePoint.x)
        let deltaY = abs(mouseY - lastMousePoint.y)
        if deltaX < 0.75 && deltaY < 0.75 && !model.isExpanded {
            if (model.observedFileToast != nil || model.isToastDismissing) {
                return
            }

            let edge = settings.clampedNotchEdgeThickness
            let approachWidth = settings.clampedApproachWidth
            let approachHeight = settings.clampedApproachHeight
            let topInset = screen.safeAreaInsets.top
            let horizontalDifferential = screenRect.width - screen.visibleFrame.width
            let edgeNotchWidth = (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
            let edgeNotchHeight = topInset > 0 ? topInset : baseNotchHeight
            let edgeNotchLeft = (screenRect.width - edgeNotchWidth) / 2
            let notchRect = CGRect(
                x: edgeNotchLeft,
                y: screenRect.height - edgeNotchHeight,
                width: edgeNotchWidth,
                height: edgeNotchHeight
            )
            let notchEdgeRect = notchRect.insetBy(dx: -edge, dy: -edge)
            let isHoveringEdge = isPointInNotchEdge(globalPoint, notchRect: notchRect, edge: edge)
            let approachRect = CGRect(
                x: notchEdgeRect.minX - approachWidth,
                y: notchEdgeRect.minY - approachHeight,
                width: notchEdgeRect.width + approachWidth * 2,
                height: approachHeight
            )
            let shouldTrack = settings.disableApproach
                ? isHoveringEdge
                : (approachRect.contains(globalPoint) || isHoveringEdge)
            if !shouldTrack, !model.isPinned, model.expansionProgress > 0 {
                approachStartTime = nil
                if let window = notchWindow {
                    window.ignoresMouseEvents = true
                    window.alphaValue = 1.0
                }
                withAnimation(settings.notchOpenAnimation) {
                    model.expansionProgress = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, !self.model.isExpanded, self.model.expansionProgress == 0 else { return }
                    self.notchWindow?.alphaValue = 0.0
                }
            }
            return
        }
        lastMousePoint = globalPoint

        if suppressProximityUntilExit {
            if isMouseWithinReopenZone(mouseX: mouseX, mouseY: mouseY, screenRect: screenRect) {
                return
            }
            suppressProximityUntilExit = false
        }

        if model.isPinned {
            return
        }

        let distanceToTop = screenRect.height - mouseY
        let edge = settings.clampedNotchEdgeThickness
        let approachHeight = settings.clampedApproachHeight
        let nearTop = distanceToTop <= (activationYBuffer + edge + approachHeight + 220)
        let desiredInterval: TimeInterval
        if model.isExpanded || model.isPinned {
            desiredInterval = 0.14
        } else if nearTop {
            desiredInterval = 0.08
        } else {
            desiredInterval = 0.25
        }
        let targetInterval = (!model.isExpanded && model.expansionProgress > 0 && !model.isPinned)
            ? min(desiredInterval, 0.05)
            : desiredInterval
        if targetInterval != mousePollingInterval {
            mousePollingInterval = targetInterval
            mouseTimer?.schedule(deadline: .now() + mousePollingInterval, repeating: mousePollingInterval, leeway: .milliseconds(140))
        }

        if !model.isPinned && !model.isExpanded {
            let edge = settings.clampedNotchEdgeThickness
            let approachWidth = settings.clampedApproachWidth
            let approachHeight = settings.clampedApproachHeight
            let topInset = screen.safeAreaInsets.top
            let horizontalDifferential = screenRect.width - screen.visibleFrame.width
            let edgeNotchWidth = (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
            let edgeNotchHeight = topInset > 0 ? topInset : baseNotchHeight
            let edgeNotchLeft = (screenRect.width - edgeNotchWidth) / 2
            let notchRect = CGRect(
                x: edgeNotchLeft,
                y: screenRect.height - edgeNotchHeight,
                width: edgeNotchWidth,
                height: edgeNotchHeight
            )
            let notchEdgeRect = notchRect.insetBy(dx: -edge, dy: -edge)
            let isHoveringEdge = isPointInNotchEdge(globalPoint, notchRect: notchRect, edge: edge)
            let approachRect = CGRect(
                x: notchEdgeRect.minX - approachWidth,
                y: notchEdgeRect.minY - approachHeight,
                width: notchEdgeRect.width + approachWidth * 2,
                height: approachHeight
            )

            let shouldTrack = settings.disableApproach
                ? isHoveringEdge
                : (approachRect.contains(globalPoint) || isHoveringEdge)
            if !shouldTrack {
                return
            }
        }

        evaluateMouseCoordinates(globalPoint)
    }

    private func isMouseWithinReopenZone(mouseX: CGFloat, mouseY: CGFloat, screenRect: CGRect) -> Bool {
        let notchLeft = (screenRect.width - notchWidth) / 2
        let notchRight = notchLeft + notchWidth
        let distanceToTop = screenRect.height - mouseY
        let edge = settings.clampedNotchEdgeThickness
        let approachHeight = settings.clampedApproachHeight
        let activationBuffer = activationYBuffer + edge + approachHeight
        let proximityX = exactTriggerPadding + 80
        let isNearNotchX = mouseX >= (notchLeft - proximityX) && mouseX <= (notchRight + proximityX)
        return isNearNotchX && distanceToTop <= (activationBuffer + 160)
    }

    private func isPointInNotchEdge(_ point: NSPoint, notchRect: CGRect, edge: CGFloat) -> Bool {
        let thickness = max(0, edge)
        guard thickness > 0 else { return false }
        let hitThickness = max(6, thickness)
        let outerRect = notchRect.insetBy(dx: -hitThickness, dy: -hitThickness)
        return outerRect.contains(point)
    }

    private func isDraggingFile() -> Bool {
        if (NSEvent.pressedMouseButtons & 1) == 0 {
            return false
        }
        let dragPasteboard = NSPasteboard(name: .drag)
        return dragPasteboard.types?.contains(.fileURL) == true
    }

    private func scheduleHoverCloseIfNeeded() {
        if hoverCloseWorkItem != nil {
            return
        }
        let delay = settings.hoverCloseDelay
        if delay <= 0 {
            hidePanel()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.hidePanel()
        }
        hoverCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func evaluateMouseCoordinates(_ globalPoint: NSPoint) {
        guard let screen = NSScreen.screens.first, let window = notchWindow else { return }
        if (model.observedFileToast != nil || model.isToastDismissing) && !model.isExpanded {
            return
        }

        guard globalPoint.x.isFinite, globalPoint.y.isFinite else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMouseEvaluationTime < mouseEvaluationInterval {
            return
        }
        lastMouseEvaluationTime = now
        
        let screenRect = screen.frame
        let mouseX = globalPoint.x
        let mouseY = globalPoint.y
        
        let edge = settings.clampedNotchEdgeThickness
        let approachWidth = settings.clampedApproachWidth
        let approachHeight = settings.clampedApproachHeight
        let topInset = screen.safeAreaInsets.top
        let horizontalDifferential = screenRect.width - screen.visibleFrame.width
        let edgeNotchWidth = (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
        let edgeNotchHeight = topInset > 0 ? topInset : baseNotchHeight
        let edgeNotchLeft = (screenRect.width - edgeNotchWidth) / 2
        let notchRect = CGRect(
            x: edgeNotchLeft,
            y: screenRect.height - edgeNotchHeight,
            width: edgeNotchWidth,
            height: edgeNotchHeight
        )
        let notchEdgeRect = notchRect.insetBy(dx: -edge, dy: -edge)
        let isHoveringEdge = isPointInNotchEdge(globalPoint, notchRect: notchRect, edge: edge)
        let approachRect = CGRect(
            x: notchEdgeRect.minX - approachWidth,
            y: notchEdgeRect.minY - approachHeight,
            width: notchEdgeRect.width + approachWidth * 2,
            height: approachHeight
        )
        let isDirectHoverOverNotch = isHoveringEdge
        let panelLeft = (screenRect.width - panelWidth) / 2
        let panelRight = panelLeft + panelWidth
        let isWithinExpandedPanel = mouseX >= panelLeft && mouseX <= panelRight && mouseY >= (screenRect.height - panelHeight)

        if settings.disableApproach {
            if model.isPinned {
                showPanel(expanded: true, pinned: true)
                return
            }
            if model.isExpanded {
                if isWithinExpandedPanel || isDirectHoverOverNotch {
                    hoverCloseWorkItem?.cancel()
                    return
                }
                scheduleHoverCloseIfNeeded()
                return
            }
            if isDirectHoverOverNotch {
                let isFileDrag = isDraggingFile()
                let preferredPage = isFileDrag ? NotchPage.box.rawValue : nil
                showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
            }
            return
        }

        if !model.isPinned && !model.isExpanded {
            if !(approachRect.contains(globalPoint) || isHoveringEdge) {
                approachStartTime = nil
                hidePanel()
                return
            }
            if !isHoveringEdge {
                if approachStartTime == nil {
                    approachStartTime = now
                }
                let elapsed = now - (approachStartTime ?? now)
                if elapsed < settings.approachDelay {
                    return
                }
            } else {
                approachStartTime = nil
            }
        }

        if model.isPinned {
            showPanel(expanded: true, pinned: true)
            return
        }
        
        if model.isExpanded {
            if isWithinExpandedPanel || isDirectHoverOverNotch {
                hoverCloseWorkItem?.cancel()
                return
            }
            scheduleHoverCloseIfNeeded()
            return
        }
        
        if approachRect.contains(globalPoint) || isHoveringEdge {
            let totalHeight = max(1, approachHeight)
            let distance = max(0, notchEdgeRect.minY - mouseY)
            let baseProgress = min(1.0, max(0.0, 1.0 - (distance / totalHeight)))
            let targetProgress = isHoveringEdge ? 1.0 : baseProgress
            if abs(model.expansionProgress - targetProgress) > 0.01 {
                model.expansionProgress = targetProgress
            }
            if window.alphaValue != 1.0 {
                window.alphaValue = 1.0
            }
            window.ignoresMouseEvents = true

            if isDirectHoverOverNotch {
                let isFileDrag = isDraggingFile()
                let preferredPage = isFileDrag ? NotchPage.box.rawValue : nil
                showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
            }
        } else {
            hidePanel()
        }
    }
    
    private func showPanel(expanded: Bool, pinned: Bool, preferredPage: Int? = nil) {
        guard let window = notchWindow else { return }
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
        swipeCloseWorkItem?.cancel()
        swipeCloseWorkItem = nil
        approachStartTime = nil
        model.isExpanded = expanded
        model.isPinned = pinned
        model.expansionProgress = 1.0
        model.closeGestureProgress = 0
        model.carouselDragOffset = 0
        if let preferredPage {
            model.currentPage = preferredPage
        } else if expanded {
            if settings.reopenLastPage {
                model.currentPage = settings.lastVisitedPage
            } else if settings.defaultToBoxIfItems, !model.boxFiles.isEmpty {
                model.currentPage = NotchPage.box.rawValue
            } else {
                model.currentPage = settings.defaultPage
            }
        }
        updateNotchWindowFrame(heightOverride: panelHeight)
        window.alphaValue = 1.0
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
    }
    
    private func hidePanel(preserveCloseProgress: Bool = false) {
        guard let window = notchWindow else { return }
        if (model.observedFileToast != nil || model.isToastDismissing) && !model.isExpanded {
            return
        }
        if model.isPinned { return }
        pendingHideWorkItem?.cancel()
        swipeCloseWorkItem?.cancel()
        swipeCloseWorkItem = nil
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
        approachStartTime = nil
        withAnimation(settings.springAnimation) {
            model.isExpanded = false
            model.expansionProgress = 0.0
            if !preserveCloseProgress {
                model.closeGestureProgress = 0
            }
            model.carouselDragOffset = 0
        }
        // UNIFIED FIX: Enforce continuous frame tracking sync on state shifts
        updateNotchWindowFrame()
        
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isPinned else { return }
            window.alphaValue = 0.0
            window.ignoresMouseEvents = true
        }
        pendingHideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: hideWorkItem)
    }

    private func configureFolderMonitors(with folders: [String]) {
        let desired = Set(folders)
        let existing = Set(folderMonitors.keys)

        let toRemove = existing.subtracting(desired)
        let toAdd = desired.subtracting(existing)

        for path in toRemove {
            folderMonitors[path]?.stop()
            folderMonitors.removeValue(forKey: path)
            folderSnapshots.removeValue(forKey: path)
        }

        for path in toAdd {
            let url = URL(fileURLWithPath: path)
            folderSnapshots[path] = snapshotFiles(in: url)
            let monitor = FolderMonitor(url: url) { [weak self] in
                self?.handleFolderChange(for: url)
            }
            monitor.start()
            folderMonitors[path] = monitor
        }
    }

    private func snapshotFiles(in folder: URL) -> Set<String> {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let filtered = files.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory != true
        }

        return Set(filtered.map { $0.path })
    }

    private func handleFolderChange(for folder: URL) {
        let path = folder.path
        let previous = folderSnapshots[path] ?? []
        let current = snapshotFiles(in: folder)
        folderSnapshots[path] = current

        let added = current.subtracting(previous)
        guard !added.isEmpty else { return }

        let newURLs = added.map { URL(fileURLWithPath: $0) }
        let newest = newURLs.max { lhs, rhs in
            let lhsValues = try? lhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let rhsValues = try? rhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let lhsDate = lhsValues?.creationDate ?? lhsValues?.contentModificationDate ?? .distantPast
            let rhsDate = rhsValues?.creationDate ?? rhsValues?.contentModificationDate ?? .distantPast
            return lhsDate < rhsDate
        }

        guard let fileURL = newest else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showObservedFileToast(fileURL: fileURL, folderURL: folder)
        }
    }

    private func showObservedFileToast(fileURL: URL, folderURL: URL) {
        withAnimation(settings.notchOpenAnimation) {
            model.observedFileToast = ObservedFileToast(fileURL: fileURL, folderURL: folderURL)
        }
        showToastPanel()
    }

    private func showToastPanel() {
        guard let window = notchWindow else { return }
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        model.isToastDismissing = false
        model.isExpanded = false
        model.isPinned = false
        model.expansionProgress = 0.0
        updateNotchWindowFrame(heightOverride: max(panelHeight, toastPanelHeight))
        window.alphaValue = 1.0
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
        withAnimation(settings.notchOpenAnimation) {
            model.expansionProgress = 1.0
        }
    }

    func dismissToastAndHideNotch() {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        suppressProximityUntilExit = true
        model.isToastDismissing = true
        model.observedFileToast = nil
        model.isExpanded = false
        model.isPinned = false
        model.expansionProgress = 0.0
        model.closeGestureProgress = 0
        updateNotchWindowFrame(heightOverride: panelHeight)
        if let window = notchWindow {
            window.alphaValue = 0.0
            window.ignoresMouseEvents = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.suppressProximityUntilExit = true
            self?.model.isToastDismissing = false
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        mouseTimer?.cancel()
        clipboardTimer?.cancel()
        nowPlayingTimer?.invalidate()
        for monitor in folderMonitors.values {
            monitor.stop()
        }
    }
}

final class FolderMonitor {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
            }
            self.fileDescriptor = -1
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

// MARK: - Trackpad Swipe Interceptor
struct TrackpadSwipeReader: NSViewRepresentable {
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    var onSwipeUp: () -> Void
    var canTriggerVertical: () -> Bool
    var isActive: Bool
    
    class Coordinator: NSObject {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        var onSwipeUp: () -> Void
        var canTriggerVertical: () -> Bool
        var isActive: Bool
        private var accumulatedDeltaX: CGFloat = 0
        private var accumulatedDeltaY: CGFloat = 0
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var didTriggerPage = false
        private var didTriggerClose = false
        private var lastEventTimestamp: TimeInterval = 0
        private let horizontalThreshold: CGFloat = 40
        private let verticalThreshold: CGFloat = 70
        
        init(
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void,
            onSwipeUp: @escaping () -> Void,
            canTriggerVertical: @escaping () -> Bool,
            isActive: Bool
        ) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            self.onSwipeUp = onSwipeUp
            self.canTriggerVertical = canTriggerVertical
            self.isActive = isActive
            super.init()
        }
        
        deinit {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
            }
        }

        func startMonitoring() {
            guard localMonitor == nil, globalMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                self?.handleEvent(event)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                self?.handleEvent(event)
            }
        }

        func handleEvent(_ event: NSEvent) {
            guard isActive else { return }
            guard isPointerOverNotch() else { return }
            let timestamp = event.timestamp
            if timestamp == lastEventTimestamp { return }
            lastEventTimestamp = timestamp

            if event.type == .swipe {
                let swipeX = event.deltaX
                let swipeY = event.deltaY
                if abs(swipeX) >= abs(swipeY) {
                    if swipeX < 0 {
                        onSwipeLeft()
                    } else if swipeX > 0 {
                        onSwipeRight()
                    }
                } else if swipeY > 0, canTriggerVertical() {
                    onSwipeUp()
                }
                return
            }

            let rawDeltaX = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
            let rawDeltaY = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
            guard rawDeltaX != 0 || rawDeltaY != 0 else { return }

            let isTrackpadLike = event.hasPreciseScrollingDeltas || event.phase != [] || event.momentumPhase != []
            if !isTrackpadLike {
                guard abs(rawDeltaX) > abs(rawDeltaY) else { return }
            }

            let fingerDeltaX = event.isDirectionInvertedFromDevice ? -rawDeltaX : rawDeltaX
            let fingerDeltaY = event.isDirectionInvertedFromDevice ? -rawDeltaY : rawDeltaY

            if event.phase == .began || event.phase == .mayBegin || event.momentumPhase == .began {
                resetAccumulation()
            }

            if abs(fingerDeltaX) >= abs(fingerDeltaY) {
                guard !didTriggerPage else { return }
                accumulatedDeltaX += fingerDeltaX
                if abs(accumulatedDeltaX) > horizontalThreshold {
                    if accumulatedDeltaX < 0 {
                        onSwipeLeft()
                    } else {
                        onSwipeRight()
                    }
                    didTriggerPage = true
                }
            } else {
                guard isTrackpadLike, !didTriggerClose else { return }
                accumulatedDeltaY += fingerDeltaY
                if accumulatedDeltaY > verticalThreshold, canTriggerVertical() {
                    onSwipeUp()
                    didTriggerClose = true
                }
            }

            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                resetAccumulation()
            }
        }

        private func resetAccumulation() {
            accumulatedDeltaX = 0
            accumulatedDeltaY = 0
            didTriggerPage = false
            didTriggerClose = false
        }

        private func isPointerOverNotch() -> Bool {
            guard let delegate = NSApp.delegate as? AppDelegate else { return false }
            guard let window = delegate.notchWindow else { return false }
            return window.frame.contains(NSEvent.mouseLocation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onSwipeUp: onSwipeUp,
            canTriggerVertical: canTriggerVertical,
            isActive: isActive
        )
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.startMonitoring()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.onSwipeUp = onSwipeUp
        context.coordinator.canTriggerVertical = canTriggerVertical
    }
}

final class NotchPanel: NSPanel {
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    var onSwipeUp: (() -> Void)?
    var isActiveProvider: (() -> Bool)?
    var canTriggerVertical: (() -> Bool)?
    var onCloseProgress: ((NSDirectionalRectEdge, CGFloat, Bool) -> Void)?
    var onCloseProgressLegacy: ((CGFloat, Bool) -> Void)?
    var onCarouselOffset: ((CGFloat, Bool) -> Void)?
    var carouselSensitivityProvider: (() -> CGFloat)?
    var closeSensitivityProvider: (() -> CGFloat)?

    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private let baseHorizontalThreshold: CGFloat = 80
    private let baseVerticalThreshold: CGFloat = 110
    private let axisLockThreshold: CGFloat = 4
    private let maxCarouselGive: CGFloat = 36
    private var snapBackWorkItem: DispatchWorkItem?
    private var ignoreScrollUntil: TimeInterval = 0
    private var didCommitThisGesture = false
    private var lastCarouselCommitTime: TimeInterval = 0
    private var verticalCloseArmed = false
    private enum GestureAxis {
        case horizontal
        case vertical
    }
    private var gestureAxis: GestureAxis?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel || event.type == .swipe {
            if handleGestureEvent(event) {
                return
            }
        }
        super.sendEvent(event)
    }

    private func handleGestureEvent(_ event: NSEvent) -> Bool {
        guard isActiveProvider?() == true else { return false }
        guard frame.contains(NSEvent.mouseLocation) else { return false }
        if event.timestamp < ignoreScrollUntil {
            return true
        }

        if event.phase == .began || event.phase == .mayBegin || event.momentumPhase == .began {
            resetAccumulation(resetProgress: false)
            gestureAxis = nil
            snapBackWorkItem?.cancel()
            didCommitThisGesture = false
            verticalCloseArmed = false
        }

        if event.type == .swipe {
            let swipeX = event.deltaX
            let swipeY = event.deltaY
            if abs(swipeX) >= abs(swipeY) {
                if swipeX < 0 {
                    onSwipeRight?()
                } else if swipeX > 0 {
                    onSwipeLeft?()
                }
                onCloseProgressLegacy?(0, true)
                return true
            }
            if swipeY > 0, canTriggerVertical?() == true {
                onSwipeUp?()
                onCloseProgressLegacy?(0, true)
                return true
            }
            onCloseProgressLegacy?(0, true)
            return false
        }

        let rawDeltaX = event.scrollingDeltaX
        let rawDeltaY = event.scrollingDeltaY
        guard rawDeltaX != 0 || rawDeltaY != 0 else { return false }

        let isTrackpadLike = event.hasPreciseScrollingDeltas || event.phase != [] || event.momentumPhase != []
        let fingerDeltaX = event.isDirectionInvertedFromDevice ? -rawDeltaX : rawDeltaX
        let fingerDeltaY = event.isDirectionInvertedFromDevice ? -rawDeltaY : rawDeltaY
        let absX = abs(fingerDeltaX)
        let absY = abs(fingerDeltaY)

        let carouselSensitivity = max(0.2, carouselSensitivityProvider?() ?? 1.0)
        let closeSensitivity = max(0.2, closeSensitivityProvider?() ?? 1.0)
        let horizontalThreshold = baseHorizontalThreshold / carouselSensitivity
        let verticalThreshold = baseVerticalThreshold / closeSensitivity

        if gestureAxis == nil {
            if max(absX, absY) < axisLockThreshold {
                scheduleSnapBack()
                if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                    scheduleSnapBack(immediate: true)
                }
                return false
            }
            gestureAxis = absX >= absY ? .horizontal : .vertical
        }

        if gestureAxis == .horizontal {
            if !isTrackpadLike && abs(rawDeltaX) <= abs(rawDeltaY) {
                return false
            }
            if didCommitThisGesture {
                return true
            }
            accumulatedDeltaX += fingerDeltaX
            let rawOffset = (accumulatedDeltaX / max(1, horizontalThreshold)) * maxCarouselGive
            let clampedOffset = clamp(-rawOffset, min: -maxCarouselGive, max: maxCarouselGive)
            onCarouselOffset?(clampedOffset, false)
            if abs(accumulatedDeltaX) > horizontalThreshold {
                if event.timestamp - lastCarouselCommitTime < 0.08 {
                    return true
                }
                lastCarouselCommitTime = event.timestamp
                didCommitThisGesture = true
                if accumulatedDeltaX < 0 {
                    onSwipeRight?()
                } else {
                    onSwipeLeft?()
                }
                onCarouselOffset?(0, true)
                snapBackWorkItem?.cancel()
                resetAccumulation(resetProgress: true)
                gestureAxis = nil
                ignoreScrollUntil = event.timestamp + 0.18
                return true
            }
            onCloseProgressLegacy?(0, false)
            scheduleSnapBack()
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                onCarouselOffset?(0, true)
                resetAccumulation(resetProgress: true)
                gestureAxis = nil
                scheduleSnapBack(immediate: true)
            }
            return true
        }

        onCarouselOffset?(0, true)

        if canTriggerVertical?() == true && fingerDeltaY > 0 {
            if !verticalCloseArmed {
                if event.phase == .began || event.phase == .mayBegin || event.momentumPhase == .began {
                    verticalCloseArmed = true
                } else {
                    return false
                }
            }
            accumulatedDeltaY = max(0, accumulatedDeltaY + fingerDeltaY)
            let progress = max(0, min(1, accumulatedDeltaY / verticalThreshold))
            onCloseProgressLegacy?(progress, false)
            if progress >= 1 {
                onSwipeUp?()
                accumulatedDeltaY = 0
                gestureAxis = nil
                verticalCloseArmed = false
                ignoreScrollUntil = event.timestamp + 0.12
                return true
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                onCloseProgressLegacy?(0, true)
                accumulatedDeltaY = 0
                gestureAxis = nil
                didCommitThisGesture = false
                verticalCloseArmed = false
                scheduleSnapBack(immediate: true)
            }
            return true
        } else {
            if accumulatedDeltaY > 0 {
                onCloseProgressLegacy?(0, true)
                accumulatedDeltaY = 0
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                gestureAxis = nil
                didCommitThisGesture = false
                verticalCloseArmed = false
            }
            return false
        }
    }

    private func resetAccumulation(resetProgress: Bool = true) {
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        if resetProgress {
            onCloseProgressLegacy?(0, true)
        }
    }

    private func scheduleSnapBack(immediate: Bool = false) {
        snapBackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onCarouselOffset?(0, true)
            self.onCloseProgressLegacy?(0, true)
        }
        snapBackWorkItem = workItem
        if immediate {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
        }
    }
}

// MARK: - Master Container Structural Layout
struct UnifiedNotchContainer: View {
    @ObservedObject var model: NotchMenuModel
    @ObservedObject var settings: AppSettings

    @StateObject private var nowPlaying = NowPlayingObserver()
    @FocusState private var isJotEditorFocused: Bool
    
    @State private var highlightedClipboardID: UUID?
    @State private var isNotchFileDropTargeted = false
    @State private var isBoxDropTargeted = false
    @State private var selectedBoxFileIDs = Set<UUID>()
    @State private var isHoveringNotch = false
    @State private var clipboardScrollOffset: CGFloat = 0
    @State private var clipboardContentHeight: CGFloat = 0
    @State private var clipboardViewportHeight: CGFloat = 0
    @State private var jotScrollOffset: CGFloat = 0
    @State private var jotContentHeight: CGFloat = 0
    @State private var jotViewportHeight: CGFloat = 0
    @State private var boxScrollOffset: CGFloat = 0
    @State private var boxContentHeight: CGFloat = 0
    @State private var boxViewportHeight: CGFloat = 0
    @State private var jotEditorScrollOffset: CGFloat = 0
    @State private var jotEditorContentHeight: CGFloat = 0
    @State private var jotEditorViewportHeight: CGFloat = 0
    @State private var jotEditorAtBottom = false
    @State private var showShapeHandles = false
    private let clipboardColumns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8), count: 3)
    private let scrollBottomTolerance: CGFloat = 24

    private func isAtScrollBottom(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        if contentHeight <= viewportHeight { return true }
        return (scrollOffset + viewportHeight) >= (contentHeight - scrollBottomTolerance)
    }

    private var clipboardCanCloseFromSwipe: Bool {
        model.clipboardItems.isEmpty || isAtScrollBottom(scrollOffset: clipboardScrollOffset, contentHeight: clipboardContentHeight, viewportHeight: clipboardViewportHeight)
    }

    private var boxCanCloseFromSwipe: Bool {
        isAtScrollBottom(scrollOffset: boxScrollOffset, contentHeight: boxContentHeight, viewportHeight: boxViewportHeight)
    }

    private var jotCanCloseFromSwipe: Bool {
        model.jotNotes.isEmpty || isAtScrollBottom(scrollOffset: jotScrollOffset, contentHeight: jotContentHeight, viewportHeight: jotViewportHeight)
    }

    private var jotEditorCanCloseFromSwipe: Bool {
        jotEditorAtBottom
    }

    private var canCloseFromVerticalSwipe: Bool {
        guard model.isExpanded, !model.isPinned else { return false }
        switch model.currentPage {
        case NotchPage.clipboard.rawValue:
            return clipboardCanCloseFromSwipe
        case NotchPage.nowPlaying.rawValue:
            return model.activeJotID != nil ? jotEditorCanCloseFromSwipe : jotCanCloseFromSwipe
        case NotchPage.box.rawValue:
            return model.boxFiles.isEmpty || boxCanCloseFromSwipe
        default:
            return true
        }
    }

    private func syncVerticalSwipeGate() {
        let newValue = canCloseFromVerticalSwipe
        guard model.canCloseFromVerticalSwipe != newValue else { return }
        model.canCloseFromVerticalSwipe = newValue
    }

    private func updateCloseProgress(_ progress: CGFloat, animate: Bool) {
        let clamped = max(0, min(1, progress))
        if clamped >= 1, model.isExpanded, !model.isPinned {
            DispatchQueue.main.async {
                closeNotchFromSwipe()
            }
        }
        if animate {
            if clamped == 0 {
                withAnimation(.easeOut(duration: 0.05)) {
                    model.closeGestureProgress = clamped
                }
            } else {
                withAnimation(settings.swipeAnimation) {
                    model.closeGestureProgress = clamped
                }
            }
        } else {
            model.closeGestureProgress = clamped
        }
    }

    private func updateClipboardScrollGate(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        DispatchQueue.main.async {
            clipboardScrollOffset = scrollOffset
            clipboardContentHeight = contentHeight
            clipboardViewportHeight = viewportHeight
            syncVerticalSwipeGate()
        }
    }

    private func updateJotScrollGate(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        DispatchQueue.main.async {
            jotScrollOffset = scrollOffset
            jotContentHeight = contentHeight
            jotViewportHeight = viewportHeight
            syncVerticalSwipeGate()
        }
    }

    private func updateBoxScrollGate(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        DispatchQueue.main.async {
            boxScrollOffset = scrollOffset
            boxContentHeight = contentHeight
            boxViewportHeight = viewportHeight
            syncVerticalSwipeGate()
        }
    }

    private func updateJotEditorScrollGate(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        DispatchQueue.main.async {
            jotEditorScrollOffset = scrollOffset
            jotEditorContentHeight = contentHeight
            jotEditorViewportHeight = viewportHeight
            jotEditorAtBottom = isAtScrollBottom(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
            syncVerticalSwipeGate()
        }
    }

    private func closeNotchFromSwipe() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.closeNotchFromSwipe()
        }
    }

    private func previewBadge(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.35)))
            .overlay(Capsule().stroke(accent.opacity(0.7), lineWidth: 1))
    }

    private func previewTitleSample(page: NotchPage, width: CGFloat) -> some View {
        let size = settings.titleSize(for: page)
        let color = Color(settings.titleColor(for: page))
        let alignment = settings.titleAlignment(for: page).alignment
        return Text("Title")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
            .frame(width: width, alignment: alignment)
    }

    private var boxMenuBarControls: some View {
        let showControls = model.isExpanded && !model.boxFiles.isEmpty
        return GeometryReader { geo in
            let screen = NSScreen.screens.first
            let screenRect = screen?.frame ?? .zero
            let visibleRect = screen?.visibleFrame ?? .zero
            let horizontalDifferential = screenRect.width - visibleRect.width
            let edgeNotchWidth = (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
            let notchLeft = (geo.size.width - edgeNotchWidth) / 2
            let controlWidth: CGFloat = 180
            let xOffset = notchLeft - controlWidth

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        if selectedBoxFileIDs.count == model.boxFiles.count {
                            selectedBoxFileIDs.removeAll()
                        } else {
                            selectedBoxFileIDs = Set(model.boxFiles.map { $0.id })
                        }
                    }
                } label: {
                    Text(selectedBoxFileIDs.count == model.boxFiles.count ? "Deselect" : "Select All")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation {
                        model.boxFiles.removeAll()
                        selectedBoxFileIDs.removeAll()
                    }
                } label: {
                    Text("Clear")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
            .frame(width: controlWidth, alignment: .trailing)
            .offset(x: xOffset, y: 6)
            .opacity(showControls ? 1.0 : 0.0)
            .zIndex(5)
        }
    }
    
    var body: some View {
        let panelWidth = scaledPanelWidth(for: settings)
        let panelHeight = scaledPanelHeight(for: settings)

        let hardware = hardwareNotchDimensions(for: NSScreen.screens.first)
        let notchWidth = hardware.width
        let notchHeight = hardware.height
        let rawProgress = model.expansionProgress
        let progress = rawProgress.isFinite ? max(0, min(1, rawProgress)) : 0
        let easedProgress = progress * progress * (3 - 2 * progress)
        let rawShellWidth = toastPanelWidth + ((panelWidth - toastPanelWidth) * easedProgress)
        let rawShellHeight = notchHeight + ((panelHeight - notchHeight) * easedProgress)
        let shellWidth = safeDimension(rawShellWidth, fallback: panelWidth)
        let shellHeight = safeDimension(rawShellHeight, fallback: panelHeight)
        let islandWidth = notchWidth + ((panelWidth - notchWidth) * easedProgress * 0.35)
        let islandHeight = notchHeight
        let cornerRadius = safeDimension(max(4, settings.cornerRadius * (0.6 + 0.4 * easedProgress)), fallback: 8)
        let contentProgress = easedProgress.isFinite ? max(0, min(1, (easedProgress - 0.18) / 0.82)) : 0
        let showToastOnly = (model.observedFileToast != nil || model.isToastDismissing) && !model.isExpanded && !model.isPinned
        let containerHeight = safeDimension(showToastOnly ? max(panelHeight, toastPanelHeight) : panelHeight, fallback: panelHeight)
        let toastWidth = toastPanelWidth
        let containerWidth = safeDimension(panelWidth, fallback: panelWidth)
        let closeProgress = max(0, min(1, model.closeGestureProgress))
        let closeEase = closeProgress * closeProgress * (3 - 2 * closeProgress)
        let closeOffset = -44 * closeEase
        let closeScale = 1 - (0.14 * closeEase)
        
        ZStack(alignment: .top) {
            if settings.showHoverPreviews {
                GeometryReader { geo in
                    let notchWidth = settings.clampedNotchWidth
                    let notchHeight = settings.clampedNotchHeight
                    let screen = NSScreen.screens.first
                    let screenRect = screen?.frame ?? .zero
                    let visibleRect = screen?.visibleFrame ?? .zero
                    let topInset = screen?.safeAreaInsets.top ?? 0
                    let horizontalDifferential = screenRect.width - visibleRect.width
                    let edgeNotchWidth = (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
                    let edgeNotchHeight = topInset > 0 ? topInset : baseNotchHeight
                    let edge = settings.clampedNotchEdgeThickness
                    let approachWidth = settings.clampedApproachWidth
                    let approachHeight = settings.clampedApproachHeight
                    let focus = settings.hoverPreviewFocus
                    let accent = Color(settings.accentColor)
                    let notchX = (geo.size.width - notchWidth) / 2
                    let edgeNotchX = (geo.size.width - edgeNotchWidth) / 2
                    let notchRect = CGRect(x: notchX, y: 0, width: notchWidth, height: notchHeight)
                    let edgeNotchRect = CGRect(x: edgeNotchX, y: 0, width: edgeNotchWidth, height: edgeNotchHeight)
                    let edgeInset = max(0, edge)
                    let outerRect = edgeNotchRect.insetBy(dx: -edgeInset, dy: -edgeInset)
                    let approachRect = CGRect(
                        x: edgeNotchRect.minX - edgeInset - approachWidth,
                        y: edgeNotchRect.maxY + edgeInset,
                        width: edgeNotchRect.width + (edgeInset * 2) + approachWidth * 2,
                        height: approachHeight
                    )
                    let clipboardLimitText = settings.clampedRememberClips == 0 ? "Unlimited" : "\(settings.clampedRememberClips)"
                    let previewY = edgeNotchRect.maxY + 28

                    ZStack(alignment: .topLeading) {
                        Group {
                            switch focus {
                            case .all:
                                if approachHeight > 0 || approachWidth > 0 {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                                        .frame(width: approachRect.width, height: approachRect.height)
                                        .position(x: approachRect.midX, y: approachRect.midY)
                                }
                                if edgeInset > 0 {
                                    Capsule()
                                        .fill(accent.opacity(0.45))
                                        .frame(width: outerRect.width, height: outerRect.height)
                                        .position(x: outerRect.midX, y: outerRect.midY)
                                }
                                Capsule()
                                    .fill(Color(settings.backgroundColor))
                                    .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                                    .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                                    .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                            case .islandSize:
                                Capsule()
                                    .fill(Color(settings.backgroundColor))
                                    .frame(width: notchRect.width, height: notchRect.height)
                                    .position(x: notchRect.midX, y: notchRect.midY)
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    .frame(width: notchRect.width, height: notchRect.height)
                                    .position(x: notchRect.midX, y: notchRect.midY)
                            case .notchEdge:
                                if edgeInset > 0 {
                                    Capsule()
                                        .fill(accent.opacity(0.55))
                                        .frame(width: outerRect.width, height: outerRect.height)
                                        .position(x: outerRect.midX, y: outerRect.midY)
                                }
                                Capsule()
                                    .fill(Color(settings.backgroundColor))
                                    .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                                    .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                                    .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                            case .approach:
                                if approachHeight > 0 || approachWidth > 0 {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                                        .frame(width: approachRect.width, height: approachRect.height)
                                        .position(x: approachRect.midX, y: approachRect.midY)
                                }
                            case .clipboardLimit:
                                previewBadge("Clip limit \(clipboardLimitText)", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .titleSize:
                                previewTitleSample(page: settings.hoverPreviewTitlePage, width: notchRect.width)
                                    .position(x: notchRect.midX, y: previewY)
                            case .cornerRadius:
                                RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.7), lineWidth: 2)
                                    .frame(width: 140, height: 52)
                                    .position(x: notchRect.midX, y: previewY)
                            case .sensitivityCarousel:
                                previewBadge("Carousel sensitivity \(String(format: "%.2f", settings.carouselSensitivity))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .sensitivityClose:
                                previewBadge("Close sensitivity \(String(format: "%.2f", settings.closeSensitivity))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .animationNotch:
                                previewBadge("Notch anim r \(String(format: "%.2f", settings.notchAnimationResponse)) d \(String(format: "%.2f", settings.notchAnimationDamping))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .animationCarousel:
                                previewBadge("Carousel anim r \(String(format: "%.2f", settings.carouselAnimationResponse)) d \(String(format: "%.2f", settings.carouselAnimationDamping))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .animationSwipe:
                                previewBadge("Swipe anim r \(String(format: "%.2f", settings.swipeAnimationResponse)) d \(String(format: "%.2f", settings.swipeAnimationDamping))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .delayApproach:
                                previewBadge("Approach delay \(String(format: "%.2fs", settings.approachDelay))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .delayHoverClose:
                                previewBadge("Hover close \(String(format: "%.2fs", settings.hoverCloseDelay))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            case .delaySwipeClose:
                                previewBadge("Swipe close \(String(format: "%.2fs", settings.swipeCloseDelay))", accent: accent)
                                    .position(x: notchRect.midX, y: previewY)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .opacity(0.8)
                .padding(.top, 4)
            }
            if let toast = model.observedFileToast {
                ObservedFileToastView(
                    toast: toast,
                    progress: easedProgress,
                    onClose: {
                        withAnimation(settings.notchOpenAnimation) {
                            model.expansionProgress = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if let delegate = NSApp.delegate as? AppDelegate {
                                delegate.dismissToastAndHideNotch()
                            } else {
                                model.observedFileToast = nil
                            }
                        }
                    },
                    baseWidth: toastWidth,
                    baseHeight: notchHeight,
                    expandedHeight: toastPanelHeight,
                    backgroundColor: Color(settings.backgroundColor),
                    cornerRadius: settings.cornerRadius
                )
                .offset(y: baseNotchHeight - 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }

            if !showToastOnly {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // UNIFIED FIX: Pad internal layouts to offset default top window inset masking values
                        ZStack {
                            Capsule()
                                .fill(Color(nsColor: settings.backgroundColor.withAlphaComponent(1.0)))
                                .frame(width: islandWidth, height: islandHeight)

                            if showShapeHandles {
                                shapeIndicatorStrip(axis: .horizontal, length: islandWidth * 0.18)
                                    .offset(y: (islandHeight / 2) - 3)
                                shapeIndicatorStrip(axis: .vertical, length: islandHeight * 0.45)
                                    .offset(x: -(islandWidth / 2) + 3)
                                shapeIndicatorStrip(axis: .vertical, length: islandHeight * 0.45)
                                    .offset(x: (islandWidth / 2) - 3)
                            }

                            NotchResizeHandle(
                                edge: .left,
                                currentWidth: settings.clampedNotchWidth,
                                currentHeight: settings.clampedNotchHeight,
                                onResize: { newWidth, newHeight in
                                    settings.notchWidth = newWidth
                                    settings.notchHeight = newHeight
                                }
                            )
                            .frame(width: 16, height: islandHeight)
                            .offset(x: -(islandWidth / 2) + 8)
                            .opacity(showShapeHandles ? 0.001 : 0.0)
                            .allowsHitTesting(showShapeHandles)

                            NotchResizeHandle(
                                edge: .right,
                                currentWidth: settings.clampedNotchWidth,
                                currentHeight: settings.clampedNotchHeight,
                                onResize: { newWidth, newHeight in
                                    settings.notchWidth = newWidth
                                    settings.notchHeight = newHeight
                                }
                            )
                            .frame(width: 16, height: islandHeight)
                            .offset(x: (islandWidth / 2) - 8)
                            .opacity(showShapeHandles ? 0.001 : 0.0)
                            .allowsHitTesting(showShapeHandles)

                            NotchResizeHandle(
                                edge: .bottom,
                                currentWidth: settings.clampedNotchWidth,
                                currentHeight: settings.clampedNotchHeight,
                                onResize: { newWidth, newHeight in
                                    settings.notchWidth = newWidth
                                    settings.notchHeight = newHeight
                                }
                            )
                            .frame(width: islandWidth, height: 14)
                            .offset(y: (islandHeight / 2) - 7)
                            .opacity(showShapeHandles ? 0.001 : 0.0)
                            .allowsHitTesting(showShapeHandles)

                            if contentProgress > 0.01 {
                                globalTitleOverlay(islandWidth: islandWidth, islandHeight: islandHeight)
                                    .opacity(contentProgress)
                                globalControlsOverlay(islandWidth: islandWidth, islandHeight: islandHeight)
                                    .opacity(contentProgress)
                            }
                        }
                        .frame(width: islandWidth, height: islandHeight)
                        .padding(.top, 0) // PULLED FLUSH

                        if contentProgress > 0.01 {
                            GeometryReader { geo in
                                let pageWidth = safeDimension(geo.size.width, fallback: 1)
                                HStack(spacing: 0) {
                                    clipboardPage.frame(width: pageWidth)
                                    sidebarPage.frame(width: pageWidth)
                                    boxPage.frame(width: pageWidth)
                                }
                                .offset(x: -CGFloat(model.currentPage) * pageWidth + model.carouselDragOffset)
                            }
                            .opacity(contentProgress)
                            .offset(y: (1.0 - contentProgress) * 12)
                            .clipped()
                        } else {
                            Color.clear.frame(height: 1)
                        }
                        
                        if settings.showPagers {
                            HStack(spacing: 8) {
                                ForEach(0..<3) { index in
                                    Button {
                                        withAnimation(settings.carouselAnimation) {
                                            model.currentPage = index
                                        }
                                    } label: {
                                        Capsule(style: .continuous)
                                            .fill(model.currentPage == index ? Color.white : Color.white.opacity(0.28))
                                            .frame(width: model.currentPage == index ? 24 : 14, height: 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .opacity(contentProgress)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: shellWidth, height: shellHeight, alignment: .top)
                    .background(Color(settings.backgroundColor))
                    .clipShape(BottomRoundedRectangle(cornerRadius: cornerRadius))
                    .shadow(color: Color.black.opacity(0.22 * contentProgress), radius: 18 * contentProgress, x: 0, y: 10 * contentProgress)
                    .animation(settings.notchOpenAnimation, value: model.expansionProgress)
                }
            }
        }
        .frame(width: containerWidth, height: containerHeight, alignment: .top)
        .overlay(alignment: .topLeading) {
            boxMenuBarControls
                .zIndex(50)
        }
        .scaleEffect(closeScale, anchor: .top)
        .offset(y: closeOffset)
        .onHover { isHoveringNotch = $0 }
        .onAppear {
            syncVerticalSwipeGate()
        }
        .onChange(of: canCloseFromVerticalSwipe) { _, newValue in
            model.canCloseFromVerticalSwipe = newValue
        }
        .highPriorityGesture(horizontalPagingGesture)
        .contextMenu {
            Button {
                showShapeHandles.toggle()
            } label: {
                Label("Shape", systemImage: showShapeHandles ? "checkmark" : "square")
            }
            SettingsLink {
                Text("Settings")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isNotchFileDropTargeted, perform: handleNotchFileDrop)
        .onChange(of: isNotchFileDropTargeted) { _, targeted in
            if targeted {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.openBoxPage()
                }
            }
        }
        .onAppear {
            refreshMediaState()
            nowPlaying.updateFromSystem()
            syncVerticalSwipeGate()
        }
        .onReceive(model.$currentPage) { newValue in
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.updateObservationState(for: newValue)
            }
            syncVerticalSwipeGate()
        }
        .onReceive(model.$activeJotID) { _ in
            syncVerticalSwipeGate()
        }
        .onReceive(model.$isExpanded) { _ in
            syncVerticalSwipeGate()
        }
        .onReceive(model.$isPinned) { _ in
            syncVerticalSwipeGate()
        }
    }
    
    private var horizontalPagingGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 40 else { return }
                withAnimation(settings.carouselAnimation) {
                    if value.translation.width < 0 {
                        model.currentPage = min(2, model.currentPage + 1)
                    } else {
                        model.currentPage = max(0, model.currentPage - 1)
                    }
                }
            }
    }

    private func emptyDismissableScrollView<Content: View>(
        onMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DismissableScrollView(
            closeSensitivity: settings.clampedCloseSensitivity,
            onOverscrollProgress: { progress, animate in
                updateCloseProgress(progress, animate: animate)
            },
            onBottomOverscroll: { closeNotchFromSwipe() },
            onMetricsChange: { offset, contentHeight, viewportHeight in
                onMetricsChange(offset, contentHeight, viewportHeight)
            }
        ) {
            content()
        }
    }

    // MARK: - Clipboard Page
    private var clipboardPage: some View {
        GeometryReader { geo in
            let width = safeDimension(geo.size.width, fallback: 1)
            let height = safeDimension(geo.size.height, fallback: 1)
            
            DismissableScrollView(
                closeSensitivity: settings.clampedCloseSensitivity,
                onOverscrollProgress: { progress, animate in
                    updateCloseProgress(progress, animate: animate)
                },
                onBottomOverscroll: { closeNotchFromSwipe() },
                onMetricsChange: { scrollOffset, contentHeight, viewportHeight in
                    updateClipboardScrollGate(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
                }
            ) {
                LazyVGrid(columns: clipboardColumns, spacing: 8) {
                    ForEach(model.clipboardItems) { item in
                        clipboardCell(item)
                    }
                }
                .padding(.vertical, 0)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: width, height: height, alignment: .center)
            .clipped()
        }
    }
    
    private func clipboardCell(_ item: ClipboardEntry) -> some View {
        let isHighlighted = highlightedClipboardID == item.id
        let accentColor = Color(settings.accentColor)
        return Button {
            copyClipboard(item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.text)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption2)
                    Spacer()
                }
                .foregroundColor(.white.opacity(0.65))
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isHighlighted ? 0.18 : 0.10))
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .center) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accentColor.opacity(isHighlighted ? 0.85 : 0), lineWidth: 1.5)
                .scaleEffect(isHighlighted ? 1.03 : 1.0)
                .opacity(isHighlighted ? 1.0 : 0.0)
        }
        .overlay(alignment: .topTrailing) {
            if isHighlighted {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 22, height: 22)
                    .scaleEffect(isHighlighted ? 2.0 : 0.7)
                    .opacity(isHighlighted ? 0.9 : 0.0)
                    .animation(.easeOut(duration: 0.35), value: isHighlighted)
                    .padding(6)
            }
        }
    }
    
    private func copyClipboard(_ item: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        if settings.clipboardActionOption == .paste, let delegate = NSApp.delegate as? AppDelegate {
            delegate.postPasteCommand()
        }
        withAnimation(settings.springAnimation) {
            highlightedClipboardID = item.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if highlightedClipboardID == item.id {
                withAnimation(.easeOut(duration: 0.2)) {
                    highlightedClipboardID = nil
                }
            }
        }
    }

    // MARK: - Jot Page
    private var sidebarPage: some View {
        jotPage
    }

    @ViewBuilder
    private func jotPageContent(width: CGFloat, height: CGFloat) -> some View {
        if let activeID = model.activeJotID {
            jotEditor(activeID: activeID, width: width, height: height)
        } else if model.jotNotes.isEmpty {
            emptyDismissableScrollView(
                onMetricsChange: { scrollOffset, contentHeight, viewportHeight in
                    updateJotScrollGate(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
                }
            ) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: max(120, height * 0.6))
            }
        } else {
            let columnCount = max(1, min(3, model.jotNotes.count))
            let columns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8), count: columnCount)
            let cellWidth = max(1, (width - CGFloat(max(0, columnCount - 1)) * 8) / CGFloat(columnCount))
            DismissableScrollView(
                closeSensitivity: settings.clampedCloseSensitivity,
                onOverscrollProgress: { progress, animate in
                    updateCloseProgress(progress, animate: animate)
                },
                onBottomOverscroll: { closeNotchFromSwipe() },
                onMetricsChange: { scrollOffset, contentHeight, viewportHeight in
                    updateJotScrollGate(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
                }
            ) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.jotNotes) { note in
                        jotCard(note, cellWidth: cellWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
            }
        }
    }

    private var jotPage: some View {
        GeometryReader { geo in
            let w = safeDimension(geo.size.width, fallback: 1)
            let h = safeDimension(geo.size.height, fallback: 1)

            VStack(spacing: 8) {
                jotPageContent(width: w, height: h)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: w, height: h, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createJot() {
        let note = JotNote()
        var notes = model.jotNotes
        notes.insert(note, at: 0)
        model.jotNotes = notes
        model.activeJotID = note.id
        isJotEditorFocused = true
    }

    private func closeActiveJot() {
        model.activeJotID = nil
        isJotEditorFocused = false
    }

    private func jotBinding(for noteID: UUID) -> Binding<String> {
        Binding(
            get: {
                model.jotNotes.first(where: { $0.id == noteID })?.text ?? ""
            },
            set: { newValue in
                guard let index = model.jotNotes.firstIndex(where: { $0.id == noteID }) else { return }
                var notes = model.jotNotes
                notes[index].text = newValue
                notes[index].updatedAt = Date()
                model.jotNotes = notes
            }
        )
    }

    private func jotNoteTitle(_ note: JotNote) -> String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }
        return trimmed.components(separatedBy: .newlines).first ?? "Untitled"
    }

    private func jotNotePreview(_ note: JotNote) -> String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Tap to start writing" }
        return trimmed
    }

    private func estimatedJotCardHeight(for note: JotNote, cellWidth: CGFloat) -> CGFloat {
        let text = jotNotePreview(note)
        let availableWidth = max(1, cellWidth - 20)
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let cappedTextHeight = min(lineHeight * 2, ceil(boundingRect.height))
        return max(72, cappedTextHeight + 30)
    }

    private func jotCard(_ note: JotNote, cellWidth: CGFloat) -> some View {
        let accentColor = Color(settings.accentColor)
        let cardHeight = estimatedJotCardHeight(for: note, cellWidth: cellWidth)
        return Button {
            model.activeJotID = note.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(jotNotePreview(note))
                    .font(.subheadline)
                    .fontWeight(note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .regular : .semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .topLeading)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accentColor.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func jotEditor(activeID: UUID, width: CGFloat, height: CGFloat) -> some View {
        JotTextEditorView(
            text: jotBinding(for: activeID),
            isFocused: $isJotEditorFocused,
            closeSensitivity: settings.clampedCloseSensitivity,
            onOverscrollProgress: { progress, animate in
                updateCloseProgress(progress, animate: animate)
            },
            onBottomOverscroll: { closeNotchFromSwipe() },
            onScrollMetricsChange: { scrollOffset, contentHeight, viewportHeight in
                updateJotEditorScrollGate(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
            }
        )
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(
            width: safeDimension(width - 16, fallback: 1),
            height: max(120, safeDimension(height - 16, fallback: 120)),
            alignment: .top
        )
        .onAppear {
            isJotEditorFocused = true
        }
    }

    private struct JotTextEditorView: NSViewRepresentable {
        @Binding var text: String
        var isFocused: FocusState<Bool>.Binding
        let closeSensitivity: CGFloat
        let onOverscrollProgressLegacy: (CGFloat, Bool) -> Void
        let onBottomOverscroll: () -> Void
        let onScrollMetricsChange: (CGFloat, CGFloat, CGFloat) -> Void

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, closeSensitivity: CGFloat, onOverscrollProgress: @escaping (CGFloat, Bool) -> Void, onBottomOverscroll: @escaping () -> Void, onScrollMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
            self._text = text
            self.isFocused = isFocused
            self.closeSensitivity = closeSensitivity
            self.onOverscrollProgressLegacy = onOverscrollProgress
            self.onBottomOverscroll = onBottomOverscroll
            self.onScrollMetricsChange = onScrollMetricsChange
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, isFocused: isFocused, onScrollMetricsChange: onScrollMetricsChange)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = OverscrollDismissScrollView()
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
            scrollView.onOverscrollProgress = onOverscrollProgressLegacy
            scrollView.onBottomOverscroll = onBottomOverscroll
            scrollView.closeSensitivity = closeSensitivity

            let textView = NSTextView()
            textView.delegate = context.coordinator
            textView.string = text
            textView.drawsBackground = false
            textView.backgroundColor = .clear
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.isEditable = true
            textView.isSelectable = true
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.textContainerInset = NSSize(width: 0, height: 6)
            textView.textColor = .white
            textView.insertionPointColor = .white
            textView.font = .systemFont(ofSize: 13)

            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            }

            scrollView.documentView = textView
            context.coordinator.attach(textView: textView, scrollView: scrollView)
            DispatchQueue.main.async {
                context.coordinator.updateMetrics()
            }
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            if let overscrollView = scrollView as? OverscrollDismissScrollView {
                overscrollView.onOverscrollProgress = onOverscrollProgressLegacy
                overscrollView.onBottomOverscroll = onBottomOverscroll
                overscrollView.closeSensitivity = closeSensitivity
            }

            if textView.string != text {
                let selection = textView.selectedRange()
                textView.string = text
                textView.selectedRange = selection
            }

            if let textContainer = textView.textContainer {
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            }

            if isFocused.wrappedValue, scrollView.window?.firstResponder !== textView {
                scrollView.window?.makeFirstResponder(textView)
            }

            DispatchQueue.main.async {
                context.coordinator.updateMetrics()
            }
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            @Binding var text: String
            var isFocused: FocusState<Bool>.Binding
            var onScrollMetricsChange: (CGFloat, CGFloat, CGFloat) -> Void
            weak var textView: NSTextView?
            weak var scrollView: NSScrollView?

            init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onScrollMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
                _text = text
                self.isFocused = isFocused
                self.onScrollMetricsChange = onScrollMetricsChange
            }

            func attach(textView: NSTextView, scrollView: NSScrollView) {
                self.textView = textView
                self.scrollView = scrollView
                scrollView.contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange(_:)), name: NSView.frameDidChangeNotification, object: textView)
                scrollView.documentView?.postsFrameChangedNotifications = true
            }

            // Fix compiler error: Remove explicit deinit workspace tracking constraints from standard object lifecycles
            deinit {
                NotificationCenter.default.removeObserver(self)
            }

            func textDidChange(_ notification: Notification) {
                text = textView?.string ?? text
                updateMetrics()
            }

            @objc private func boundsDidChange(_ notification: Notification) {
                updateMetrics()
            }

            @objc private func frameDidChange(_ notification: Notification) {
                updateMetrics()
            }

            func updateMetrics() {
                guard let textView, let scrollView else { return }
                let visibleHeight = scrollView.contentView.bounds.height
                let visibleOriginY = scrollView.contentView.bounds.origin.y
                let layoutHeight: CGFloat
                if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                    layoutHeight = layoutManager.usedRect(for: textContainer).height + (textView.textContainerInset.height * 2)
                } else {
                    layoutHeight = textView.bounds.height
                }
                let contentHeight = max(visibleHeight, ceil(layoutHeight))
                onScrollMetricsChange(visibleOriginY, contentHeight, visibleHeight)
            }
        }
    }

    private final class OverscrollDismissScrollView: NSScrollView {
        var onBottomOverscroll: (() -> Void)?
        var onOverscrollProgress: ((CGFloat, Bool) -> Void)?
        var onMetricsChange: ((CGFloat, CGFloat, CGFloat) -> Void)?
        var closeSensitivity: CGFloat = 1.0
        private var accumulatedOverscroll: CGFloat = 0
        private var didTriggerClose = false
        private var lastOverscrollProgress: CGFloat = 0
        private let baseTriggerThreshold: CGFloat = 110
        private let bottomTolerance: CGFloat = 20
        private var observationTokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureMetricsObservationIfNeeded()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureMetricsObservationIfNeeded()
        }

        deinit {
            observationTokens.forEach(NotificationCenter.default.removeObserver)
        }

        private func configureMetricsObservationIfNeeded() {
            guard observationTokens.isEmpty else { return }
            contentView.postsBoundsChangedNotifications = true
            documentView?.postsFrameChangedNotifications = true

            let center = NotificationCenter.default
            observationTokens.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
                self?.reportMetricsIfPossible()
            })
            if let documentView {
                observationTokens.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: documentView, queue: .main) { [weak self] _ in
                    self?.reportMetricsIfPossible()
                })
            }

            reportMetricsIfPossible()
        }

        func reportMetricsIfPossible() {
            let viewportHeight = contentView.bounds.height
            let scrollOffset = contentView.bounds.origin.y
            let contentHeight = documentView?.frame.height ?? viewportHeight
            onMetricsChange?(scrollOffset, contentHeight, viewportHeight)
        }

        override func scrollWheel(with event: NSEvent) {
            guard let documentView else {
                super.scrollWheel(with: event)
                return
            }

            if didTriggerClose {
                if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                    didTriggerClose = false
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    onOverscrollProgress?(0, true)
                }
                return
            }

            let fingerDeltaY = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            let viewportHeight = contentView.bounds.height
            let contentHeight = documentView.bounds.height
            let atBottom = contentHeight <= viewportHeight + bottomTolerance || contentView.bounds.maxY >= contentHeight - bottomTolerance
            let triggerThreshold = baseTriggerThreshold / max(0.2, closeSensitivity)

            if fingerDeltaY > 0 && atBottom {
                accumulatedOverscroll += fingerDeltaY
                let progress = min(1, accumulatedOverscroll / max(1, triggerThreshold))
                lastOverscrollProgress = progress
                onOverscrollProgress?(progress, false)
                if progress >= 1 {
                    accumulatedOverscroll = 0
                    didTriggerClose = true
                    lastOverscrollProgress = 1
                    onOverscrollProgress?(1, true)
                    onBottomOverscroll?()
                    return
                }
            } else {
                if accumulatedOverscroll > 0 {
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    onOverscrollProgress?(0, true)
                } else if lastOverscrollProgress > 0 {
                    lastOverscrollProgress = 0
                    onOverscrollProgress?(0, true)
                }
            }

            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .began || event.momentumPhase == .ended {
                if accumulatedOverscroll > 0 {
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    onOverscrollProgress?(0, true)
                } else if lastOverscrollProgress > 0 {
                    lastOverscrollProgress = 0
                    onOverscrollProgress?(0, true)
                }
            }

            super.scrollWheel(with: event)
            reportMetricsIfPossible()
        }
    }

    private struct DismissableScrollView<Content: View> : NSViewRepresentable {
        let closeSensitivity: CGFloat
        let onOverscrollProgress: (CGFloat, Bool) -> Void
        let onBottomOverscroll: () -> Void
        let onMetricsChange: (CGFloat, CGFloat, CGFloat) -> Void
        let content: Content

        init(
            closeSensitivity: CGFloat,
            onOverscrollProgress: @escaping (CGFloat, Bool) -> Void,
            onBottomOverscroll: @escaping () -> Void,
            onMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
            @ViewBuilder content: () -> Content
        ) {
            self.closeSensitivity = closeSensitivity
            self.onOverscrollProgress = onOverscrollProgress
            self.onBottomOverscroll = onBottomOverscroll
            self.onMetricsChange = onMetricsChange
            self.content = content()
        }

        func makeNSView(context: Context) -> OverscrollDismissScrollView {
            let scrollView = OverscrollDismissScrollView()
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
            scrollView.usesPredominantAxisScrolling = true
            scrollView.onBottomOverscroll = onBottomOverscroll
            scrollView.onOverscrollProgress = onOverscrollProgress
            scrollView.onMetricsChange = onMetricsChange
            scrollView.closeSensitivity = closeSensitivity

            let hostingView = NSHostingView(rootView: content)
            hostingView.translatesAutoresizingMaskIntoConstraints = true
            hostingView.autoresizingMask = [.width]
            scrollView.documentView = hostingView
            scheduleHostingViewFrameUpdate(hostingView, in: scrollView)

            return scrollView
        }

        func updateNSView(_ nsView: OverscrollDismissScrollView, context: Context) {
            nsView.closeSensitivity = closeSensitivity
            nsView.onBottomOverscroll = onBottomOverscroll
            nsView.onOverscrollProgress = onOverscrollProgress
            nsView.onMetricsChange = onMetricsChange
            if let hostingView = nsView.documentView as? NSHostingView<Content> {
                hostingView.rootView = content
                scheduleHostingViewFrameUpdate(hostingView, in: nsView)
            }
        }

        private func scheduleHostingViewFrameUpdate(_ hostingView: NSHostingView<Content>, in scrollView: NSScrollView) {
            DispatchQueue.main.async {
                let hostingWidth = safeDimension(scrollView.contentSize.width, fallback: 1)
                let hostingHeight = safeDimension(hostingView.fittingSize.height, fallback: 1)
                hostingView.frame = NSRect(x: 0, y: 0, width: hostingWidth, height: hostingHeight)
            }
        }
    }

    // MARK: - Box Page
    private var boxPage: some View {
        GeometryReader { geo in
            let w = safeDimension(geo.size.width, fallback: 1)
            let h = safeDimension(geo.size.height, fallback: 1)
            let safeW = max(1, w)
            let safeH = max(1, h)
            VStack(spacing: 10) {
                Group {
                    if model.boxFiles.isEmpty {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: min(safeW, safeH) * 0.22, weight: .semibold))
                            .foregroundColor(.brown.opacity(0.55))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)
                        let maxSize = max(1, min((safeW - 16) / 5, safeH * 0.38))
                        DismissableScrollView(
                            closeSensitivity: settings.clampedCloseSensitivity,
                            onOverscrollProgress: { progress, animate in
                                updateCloseProgress(progress, animate: animate)
                            },
                            onBottomOverscroll: { closeNotchFromSwipe() },
                            onMetricsChange: { scrollOffset, contentHeight, viewportHeight in
                                updateBoxScrollGate(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
                            }
                        ) {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(model.boxFiles) { file in
                                    boxItemView(file: file, maxSize: maxSize)
                                }
                            }
                            .frame(width: w, alignment: .center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(width: w, height: h, alignment: .top)
            .onDrop(of: [.fileURL], isTargeted: $isBoxDropTargeted, perform: handleBoxDrop)
        }
    }

    private func boxItemView(file: BoxFile, maxSize: CGFloat) -> some View {
        let size = max(1, maxSize)
        let icon = BoxIconCache.shared.icon(for: file.url)
        icon.size = NSSize(width: size, height: size)
        let isSelected = selectedBoxFileIDs.contains(file.id)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 6) {
                BoxIconView(nsImage: icon)
                    .frame(width: size, height: size)
                if settings.showBoxFileNames {
                    VStack(spacing: 4) {
                        Text(file.url.lastPathComponent)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        if isSelected {
                            Capsule()
                                .fill(Color(settings.accentColor))
                                .frame(width: max(12, size * 0.7), height: 2)
                        }
                    }
                    .frame(width: size + 6)
                }
            }

            HoverRemoveButton {
                DispatchQueue.main.async {
                    withAnimation {
                        model.boxFiles.removeAll { $0.id == file.id }
                        selectedBoxFileIDs.remove(file.id)
                    }
                }
            }

            BoxSelectableDragSurface(
                file: file,
                isSelected: isSelected,
                urlsForDrag: {
                    let selectedURLs = model.boxFiles.compactMap { selectedBoxFileIDs.contains($0.id) ? $0.url : nil }
                    return selectedURLs.isEmpty ? [file.url] : selectedURLs
                },
                selectForDrag: {
                    if !selectedBoxFileIDs.contains(file.id) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            _ = selectedBoxFileIDs.insert(file.id)
                        }
                    }
                },
                toggleSelection: {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        if selectedBoxFileIDs.contains(file.id) {
                            selectedBoxFileIDs.remove(file.id)
                        } else {
                            selectedBoxFileIDs.insert(file.id)
                        }
                    }
                },
                removeHotSpotSize: 22
            )
        }
        .frame(width: size + 8, height: settings.showBoxFileNames ? size + 36 : size, alignment: .center)
    }

    private struct ObservedFileToastView: View {
        let toast: ObservedFileToast
        let progress: CGFloat
        let onClose: () -> Void
        let baseWidth: CGFloat
        let baseHeight: CGFloat
        let expandedHeight: CGFloat
        let backgroundColor: Color
        let cornerRadius: CGFloat
        @State private var isSelected = false
        @State private var contentHeight: CGFloat = 0

        private struct ContentHeightKey: PreferenceKey {
            static var defaultValue: CGFloat = 0
            static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
                value = max(value, nextValue())
            }
        }

        private var locationName: String {
            let name = toast.folderURL.lastPathComponent
            return name.isEmpty ? "location" : name
        }

        var body: some View {
            let clampedProgress = progress.isFinite ? max(0, min(1, progress)) : 0
            let easedProgress = clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
            let measuredHeight = contentHeight > 0 ? contentHeight : expandedHeight
            let targetHeight = min(max(baseHeight, measuredHeight), expandedHeight)
            let contentScale = measuredHeight > expandedHeight ? expandedHeight / measuredHeight : 1
            let panelHeight = baseHeight + (targetHeight - baseHeight) * easedProgress
            let icon = NSImage(contentsOf: toast.fileURL) ?? NSWorkspace.shared.icon(forFile: toast.fileURL.path)
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 10) {
                    VStack(spacing: 8) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(toast.fileURL.lastPathComponent)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .overlay(
                        ToastDragSurface(
                            url: toast.fileURL,
                            onClick: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    isSelected.toggle()
                                }
                            },
                            onDoubleClick: {
                                NSWorkspace.shared.open(toast.fileURL)
                                onClose()
                            }
                        )
                    )

                    HStack {
                        Text("in \(locationName)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                            .onTapGesture {
                                NSWorkspace.shared.activateFileViewerSelecting([toast.fileURL])
                                onClose()
                            }
                        Spacer()
                    }
                }
                .padding(12)
                .scaleEffect(contentScale, anchor: .top)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .frame(width: baseWidth, height: panelHeight, alignment: .top)
            .background(backgroundColor)
            .clipShape(BottomRoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
            .onPreferenceChange(ContentHeightKey.self) { value in
                if value.isFinite {
                    contentHeight = value
                }
            }
        }
    }

    private struct NotchResizeHandle: NSViewRepresentable {
        enum Edge {
            case left
            case right
            case bottom
        }

        let edge: Edge
        let currentWidth: CGFloat
        let currentHeight: CGFloat
        let onResize: (CGFloat, CGFloat) -> Void

        func makeNSView(context: Context) -> ResizeHandleView {
            let view = ResizeHandleView()
            view.edge = edge
            view.currentWidth = currentWidth
            view.currentHeight = currentHeight
            view.onResize = onResize
            return view
        }

        func updateNSView(_ nsView: ResizeHandleView, context: Context) {
            nsView.edge = edge
            nsView.currentWidth = currentWidth
            nsView.currentHeight = currentHeight
            nsView.onResize = onResize
        }

        final class ResizeHandleView: NSView {
            var edge: Edge = .right
            var currentWidth: CGFloat = 0
            var currentHeight: CGFloat = 0
            var onResize: ((CGFloat, CGFloat) -> Void)?
            private var startPoint: NSPoint = .zero
            private var startWidth: CGFloat = 0
            private var startHeight: CGFloat = 0
            private var isResizing = false

            override func hitTest(_ point: NSPoint) -> NSView? {
                return self
            }

            override func mouseDown(with event: NSEvent) {
                startPoint = event.locationInWindow
                startWidth = currentWidth
                startHeight = currentHeight
                isResizing = true
            }

            override func mouseDragged(with event: NSEvent) {
                guard isResizing else { return }
                let currentPoint = event.locationInWindow
                let deltaX = currentPoint.x - startPoint.x
                let deltaY = currentPoint.y - startPoint.y
                let widthDelta: CGFloat
                let heightDelta: CGFloat
                switch edge {
                case .left:
                    widthDelta = -deltaX * 2
                    heightDelta = 0
                case .right:
                    widthDelta = deltaX * 2
                    heightDelta = 0
                case .bottom:
                    widthDelta = 0
                    heightDelta = -deltaY * 2
                }
                let newWidth = max(1, startWidth + widthDelta)
                let newHeight = max(1, startHeight + heightDelta)
                onResize?(newWidth, newHeight)
            }

            override func mouseUp(with event: NSEvent) {
                isResizing = false
            }
        }
    }

    private enum ShapeIndicatorAxis {
        case horizontal
        case vertical
    }

    private func shapeIndicatorStrip(axis: ShapeIndicatorAxis, length: CGFloat) -> some View {
        let thickness: CGFloat = 3
        let size = max(6, length)
        return Capsule(style: .continuous)
            .fill(Color.white.opacity(0.55))
            .frame(width: axis == .horizontal ? size : thickness, height: axis == .horizontal ? thickness : size)
            .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 0)
    }

    private struct ClipboardScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private struct ClipboardContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct ClipboardViewportHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct JotScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private struct JotContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct JotViewportHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct BoxScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private struct BoxContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct BoxViewportHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct ToastDragSurface: NSViewRepresentable {
        let url: URL
        let onClick: () -> Void
        let onDoubleClick: () -> Void

        func makeNSView(context: Context) -> DragSurfaceView {
            let view = DragSurfaceView()
            view.url = url
            view.onClick = onClick
            view.onDoubleClick = onDoubleClick
            return view
        }

        func updateNSView(_ nsView: DragSurfaceView, context: Context) {
            nsView.url = url
            nsView.onClick = onClick
            nsView.onDoubleClick = onDoubleClick
        }

        final class DragSurfaceView: NSView, NSDraggingSource {
            var url: URL?
            var onClick: (() -> Void)?
            var onDoubleClick: (() -> Void)?
            private var mouseDownPoint: NSPoint = .zero
            private var didStartDrag = false

            override func mouseDown(with event: NSEvent) {
                mouseDownPoint = convert(event.locationInWindow, from: nil)
                didStartDrag = false
            }

            override func mouseDragged(with event: NSEvent) {
                guard !didStartDrag, let url else { return }
                let currentPoint = convert(event.locationInWindow, from: nil)
                let deltaX = currentPoint.x - mouseDownPoint.x
                let deltaY = currentPoint.y - mouseDownPoint.y
                if hypot(deltaX, deltaY) > 3 {
                    beginDrag(url: url, event: event)
                    didStartDrag = true
                }
            }

            override func mouseUp(with event: NSEvent) {
                guard !didStartDrag else { return }
                if event.clickCount > 1 {
                    onDoubleClick?()
                } else {
                    onClick?()
                }
            }

            private func beginDrag(url: URL, event: NSEvent) {
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 48, height: 48)
                draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48), contents: icon)
                beginDraggingSession(with: [draggingItem], event: event, source: self)
            }

            func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
                [.copy, .move]
            }
        }
    }

    private struct BoxIconView: View {
        let nsImage: NSImage
        var body: some View {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private struct HoverRemoveButton: View {
        var action: () -> Void
        @State private var hovering = false
        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .onHover { hovering = $0 }
                if hovering {
                    Button {
                        action()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
        }
    }

    private struct BoxSelectableDragSurface: NSViewRepresentable {
        let file: BoxFile
        let isSelected: Bool
        let urlsForDrag: () -> [URL]
        let selectForDrag: () -> Void
        let toggleSelection: () -> Void
        let removeHotSpotSize: CGFloat

        func makeNSView(context: Context) -> DragView {
            let view = DragView()
            view.urlsForDrag = urlsForDrag
            view.selectForDrag = selectForDrag
            view.toggleSelection = toggleSelection
            view.removeHotSpotSize = removeHotSpotSize
            view.isSelected = isSelected
            return view
        }

        func updateNSView(_ nsView: DragView, context: Context) {
            nsView.urlsForDrag = urlsForDrag
            nsView.selectForDrag = selectForDrag
            nsView.toggleSelection = toggleSelection
            nsView.removeHotSpotSize = removeHotSpotSize
            nsView.isSelected = isSelected
        }

        final class DragView: NSView, NSDraggingSource {
            var urlsForDrag: (() -> [URL])?
            var selectForDrag: (() -> Void)?
            var toggleSelection: (() -> Void)?
            var removeHotSpotSize: CGFloat = 22
            var isSelected: Bool = false
            private var mouseDownPoint: NSPoint = .zero
            private var mouseDownActive = false
            private var didStartDrag = false
            private var didSelectOnMouseDown = false

            override func hitTest(_ point: NSPoint) -> NSView? {
                let removeRect = NSRect(x: 0, y: bounds.height - removeHotSpotSize, width: removeHotSpotSize, height: removeHotSpotSize)
                if removeRect.contains(point) {
                    return nil
                }
                return self
            }

            override func mouseDown(with event: NSEvent) {
                mouseDownPoint = convert(event.locationInWindow, from: nil)
                mouseDownActive = true
                didStartDrag = false
                if !isSelected {
                    selectForDrag?()
                    didSelectOnMouseDown = true
                } else {
                    didSelectOnMouseDown = false
                }
            }

            override func mouseDragged(with event: NSEvent) {
                guard mouseDownActive, !didStartDrag else { return }
                let currentPoint = convert(event.locationInWindow, from: nil)
                let deltaX = currentPoint.x - mouseDownPoint.x
                let deltaY = currentPoint.y - mouseDownPoint.y
                if hypot(deltaX, deltaY) > 3 {
                    beginDrag(with: event)
                    didStartDrag = true
                }
            }

            override func mouseUp(with event: NSEvent) {
                defer {
                    mouseDownActive = false
                    didStartDrag = false
                }

                guard mouseDownActive, !didStartDrag else { return }
                if didSelectOnMouseDown { return }
                toggleSelection?()
            }

            private func beginDrag(with event: NSEvent) {
                guard let urls = urlsForDrag?(), !urls.isEmpty else { return }

                let draggingItems: [NSDraggingItem] = urls.map { url in
                    let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 32, height: 32)
                    draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: icon)
                    return draggingItem
                }

                beginDraggingSession(with: draggingItems, event: event, source: self)
            }

            func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
                [.copy, .move]
            }
        }
    }
    
    private var emptyBoxState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundColor(.orange)
            Text("Drop files here to keep them in Box")
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(isBoxDropTargeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(Color.white.opacity(0.08))
        )
    }
    
    private func boxFileRow(_ file: BoxFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundColor(.orange)
                .frame(width: 26)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(file.url.path)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrag {
            NSItemProvider(object: file.url as NSURL)
        }
    }

    // MARK: - Native Data Refresh
    private func refreshMediaState() {
        if let info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            model.currentTrack = (info[MPMediaItemPropertyTitle] as? String) ?? "Not Playing"
            model.currentArtist = (info[MPMediaItemPropertyArtist] as? String) ?? ""
            if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
                model.isPlaying = rate > 0
            } else {
                model.isPlaying = false
            }

            if let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
                if let img = artwork.image(at: CGSize(width: 160, height: 160)) {
                    model.currentArtwork = img
                } else {
                    model.currentArtwork = nil
                }
            } else {
                model.currentArtwork = nil
            }
        } else {
            model.currentTrack = "Not Playing"
            model.currentArtist = ""
            model.isPlaying = false
            model.currentArtwork = nil
        }
    }

    // MARK: - Drop Handling
    private func handleNotchFileDrop(providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers: providers, openBoxPage: true)
    }
    
    private func handleBoxDrop(providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers: providers, openBoxPage: false)
    }

    private func handleFileDrop(providers: [NSItemProvider], openBoxPage: Bool) -> Bool {
        var didAccept = false
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            didAccept = true
            let _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let fileUrl = url else { return }
                DispatchQueue.main.async {
                    if !model.boxFiles.contains(where: { $0.url == fileUrl }) {
                        model.boxFiles.insert(BoxFile(url: fileUrl), at: 0)
                    }
                    if openBoxPage {
                        model.currentPage = 2
                        model.isExpanded = true
                        model.expansionProgress = 1.0
                    }
                }
            }
        }
        return didAccept
    }

    // MARK: - Shared UI
    @ViewBuilder
    private func headerControls<Content: View>(@ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Spacer()
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func globalControlsOverlay(islandWidth: CGFloat, islandHeight: CGFloat) -> some View {
        let page = NotchPage(rawValue: model.currentPage) ?? .clipboard

        return Color.clear
            .overlay(alignment: .topTrailing) {
                HStack {
                    switch page {
                    case .clipboard:
                        if !model.clipboardItems.isEmpty {
                            Button {
                                model.clipboardItems.removeAll()
                                persistClipboardHistory(model.clipboardItems)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    case .nowPlaying:
                        Button {
                            if model.activeJotID == nil {
                                createJot()
                            } else {
                                closeActiveJot()
                            }
                        } label: {
                            Image(systemName: model.activeJotID == nil ? "plus" : "chevron.left")
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    case .box:
                        EmptyView()
                    }
                }
                .padding(.trailing, 14)
                .padding(.top, 2)
            }
            .frame(width: islandWidth, height: islandHeight)
    }

    private func globalTitleOverlay(islandWidth: CGFloat, islandHeight: CGFloat) -> some View {
        let page = NotchPage(rawValue: model.currentPage) ?? .clipboard
        let title: String
        let symbol: String
        switch page {
        case .clipboard:
            title = "Clip"
            symbol = "doc.on.clipboard"
        case .nowPlaying:
            title = "Jot"
            symbol = "note.text"
        case .box:
            title = ""
            symbol = "empty"
        }
        
        return Color.clear
            .overlay(alignment: .topLeading) {
                if symbol != "empty" {
                    header(title: title, symbol: symbol, page: page)
                        .padding(.leading, 14)
                        .padding(.top, 2)
                }
            }
            .frame(width: islandWidth, height: islandHeight)
    }

    private func header(title: String, symbol: String, page: NotchPage) -> some View {
        let displaySymbol = settings.titleSymbol(for: page, fallback: symbol)
        return Label(title, systemImage: displaySymbol)
            .font(.system(size: settings.titleSize(for: page), weight: .bold))
            .foregroundColor(Color(settings.titleColor(for: page)))
    }
}