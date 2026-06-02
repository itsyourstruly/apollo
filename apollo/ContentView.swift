//
//  apolloApp.swift
//  apollo
//

import SwiftUI
import AppKit
import Combine
import MediaPlayer
import ImageIO
import AVFoundation

// MARK: - Lightweight Page Models
enum IslandPage: Int, CaseIterable {
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

struct ClipboardEntry: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var text: String?
    var filePaths: [String] = []
    var createdAt: Date = Date()

    init(text: String) {
        self.text = text
        self.filePaths = []
    }

    init(text: String?, fileURLs: [URL]) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = (trimmed?.isEmpty == false) ? trimmed : nil
        self.filePaths = fileURLs
            .filter { $0.isFileURL }
            .map(\.path)
        self.createdAt = Date()
    }

    var normalizedText: String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var fileURLs: [URL] {
        filePaths.map { URL(fileURLWithPath: $0) }
    }

    var hasFiles: Bool {
        !filePaths.isEmpty
    }

    var hasText: Bool {
        !normalizedText.isEmpty
    }

    var isTextOnly: Bool {
        hasText && !hasFiles
    }

    var signature: String {
        let textPart = normalizedText
        let filesPart = filePaths.sorted().joined(separator: "|")
        return "t:\(textPart)#f:\(filesPart)"
    }
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
struct ApolloApp: App {
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
    static let alwaysUseApproachWhenDraggingFile = "alwaysUseApproachWhenDraggingFile"
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

private func hardwareNotchDimensions(for screen: NSScreen?) -> (x: CGFloat, width: CGFloat, height: CGFloat) {
    guard let screen else {
        return (0, baseNotchWidth, baseNotchHeight)
    }
    let screenRect = screen.frame
    let topInset = screen.safeAreaInsets.top
    let leftAux = screen.auxiliaryTopLeftArea
    let rightAux = screen.auxiliaryTopRightArea

    let auxGapWidth: CGFloat = {
        guard let leftAux, let rightAux else { return 0 }
        let leftMax = leftAux.maxX
        let rightMin = rightAux.minX
        let gap = rightMin - leftMax
        return gap.isFinite && gap > 0 ? gap : 0
    }()
    
    let x = leftAux?.maxX ?? (screenRect.width - baseNotchWidth) / 2

    let width = auxGapWidth > 0 ? auxGapWidth : {
        let horizontalDifferential = screenRect.width - screen.visibleFrame.width
        return (horizontalDifferential > 0 && horizontalDifferential < 500) ? horizontalDifferential : baseNotchWidth
    }()

    let height = topInset > 0 ? topInset : baseNotchHeight
    return (x, safeDimension(width, fallback: baseNotchWidth), safeDimension(height, fallback: baseNotchHeight))
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
    private let iconCache = NSCache<NSURL, NSImage>()
    private let previewCache = NSCache<NSString, NSImage>()
    private var knownIconKeys = Set<NSURL>()
    private var knownPreviewKeys = Set<String>()
    private let stateLock = NSLock()
    private let prewarmQueue = DispatchQueue(label: "apollo.box.prewarm", qos: .utility)

    private init() {
        iconCache.countLimit = 64
        iconCache.totalCostLimit = 8 * 1024 * 1024
        previewCache.countLimit = 64
        previewCache.totalCostLimit = 24 * 1024 * 1024
    }

    func icon(for url: URL) -> NSImage {
        let key = url as NSURL
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let pixelWidth = Int(icon.size.width * 2)
        let pixelHeight = Int(icon.size.height * 2)
        let cost = max(1, pixelWidth * pixelHeight * 4)
        iconCache.setObject(icon, forKey: key, cost: cost)
        stateLock.lock()
        knownIconKeys.insert(key)
        stateLock.unlock()
        return icon
    }

    func displayImage(for url: URL, targetSize: CGFloat) -> NSImage {
        let px = max(24, Int(targetSize.rounded()))
        let previewKey = "\(url.path)|\(px)"
        let nsKey = previewKey as NSString

        if let cached = previewCache.object(forKey: nsKey) {
            return cached
        }

        if let thumbnail = downsampledImage(at: url, maxPixelSize: px) {
            let cost = max(1, px * px * 4)
            previewCache.setObject(thumbnail, forKey: nsKey, cost: cost)
            stateLock.lock()
            knownPreviewKeys.insert(previewKey)
            stateLock.unlock()
            return thumbnail
        }

        if let videoThumbnail = videoThumbnailImage(at: url, maxPixelSize: px) {
            let cost = max(1, px * px * 4)
            previewCache.setObject(videoThumbnail, forKey: nsKey, cost: cost)
            stateLock.lock()
            knownPreviewKeys.insert(previewKey)
            stateLock.unlock()
            return videoThumbnail
        }

        return icon(for: url)
    }

    private func downsampledImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        let options: CFDictionary = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
    }

    private func videoThumbnailImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard isLikelyVideoURL(url) else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        let sampleTime = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: sampleTime, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
    }

    private func isLikelyVideoURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "ts", "m2ts":
            return true
        default:
            return false
        }
    }

    func trim(keeping urls: [URL]) {
        let keep = Set(urls.map { $0 as NSURL })
        stateLock.lock()
        let iconKeysSnapshot = knownIconKeys
        let previewKeysSnapshot = knownPreviewKeys
        stateLock.unlock()

        for key in iconKeysSnapshot where !keep.contains(key) {
            iconCache.removeObject(forKey: key)
        }

        let keepPaths = Set(urls.map(\.path))
        for key in previewKeysSnapshot {
            guard let pathEnd = key.firstIndex(of: "|") else { continue }
            let path = String(key[..<pathEnd])
            if !keepPaths.contains(path) {
                previewCache.removeObject(forKey: key as NSString)
            }
        }

        let nextIconKeys = iconKeysSnapshot.intersection(keep)
        let nextPreviewKeys = Set(previewKeysSnapshot.filter { key in
            guard let pathEnd = key.firstIndex(of: "|") else { return false }
            let path = String(key[..<pathEnd])
            return keepPaths.contains(path)
        })
        stateLock.lock()
        knownIconKeys = nextIconKeys
        knownPreviewKeys = nextPreviewKeys
        stateLock.unlock()
    }

    func removeAll() {
        iconCache.removeAllObjects()
        previewCache.removeAllObjects()
        stateLock.lock()
        knownIconKeys.removeAll()
        knownPreviewKeys.removeAll()
        stateLock.unlock()
    }

    func prewarmDisplayImages(for urls: [URL], targetSize: CGFloat) {
        let previewableURLs = urls.filter(isLikelyPreviewableURL(_:))
        guard !previewableURLs.isEmpty else { return }
        let size = max(24, targetSize)
        prewarmQueue.async { [weak self] in
            guard let self else { return }
            for url in previewableURLs {
                autoreleasepool {
                    _ = self.displayImage(for: url, targetSize: size)
                }
            }
        }
    }

    func shouldAttemptPreview(for url: URL) -> Bool {
        isLikelyPreviewableURL(url)
    }

    private func isLikelyPreviewableURL(_ url: URL) -> Bool {
        isLikelyImageURL(url) || isLikelyVideoURL(url)
    }

    private func isLikelyImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif", "icns":
            return true
        default:
            return false
        }
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
            let clampedValue = clamp(defaultPage, min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
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
            let clampedValue = clamp(lastVisitedPage, min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
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

    @Published var alwaysUseApproachWhenDraggingFile: Bool {
        didSet {
            defaults.set(alwaysUseApproachWhenDraggingFile, forKey: AppStorageKey.alwaysUseApproachWhenDraggingFile)
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
    @Published var hoverPreviewTitlePage: IslandPage = .clipboard

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

    /*
    // This is the old implementation. The new one respects the useDefaultNotchSize toggle.
    */

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

func titleAlignment(for page: IslandPage) -> TitleAlignmentOption {
        switch page {
        case .clipboard:
            return TitleAlignmentOption(rawValue: clipboardTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .nowPlaying:
            return TitleAlignmentOption(rawValue: jotTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .box:
            return TitleAlignmentOption(rawValue: boxTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        }
    }

    func titleSize(for page: IslandPage) -> CGFloat {
        switch page {
        case .clipboard:
            return clamp(clipboardTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .nowPlaying:
            return clamp(jotTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        case .box:
            return clamp(boxTitleSize ?? titleSize, min: titleSizeRange.lowerBound, max: titleSizeRange.upperBound)
        }
    }

    func titleColor(for page: IslandPage) -> NSColor {
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

    func titleSymbol(for page: IslandPage, fallback: String) -> String {
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
            defaultPage = IslandPage.clipboard.rawValue
        } else {
            defaultPage = clamp(defaults.integer(forKey: AppStorageKey.defaultPage), min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
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
            lastVisitedPage = IslandPage.clipboard.rawValue
        } else {
            lastVisitedPage = clamp(defaults.integer(forKey: AppStorageKey.lastVisitedPage), min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
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

        persistAccentColor()
        persistBackgroundColor()
        persistTitleColor()
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
@State private var selectedTitlePage: IslandPage = .clipboard
    @State private var showTitleOverrides = false
    @State private var showAdvancedAnimation = false

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        let _ = formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 200
        return formatter
    }()

    var body: some View {
        let accent = Color(settings.accentColor)
        HSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbolName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140, idealWidth: 210, maxWidth: 250)

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
            .frame(minWidth: 320, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 520, minHeight: 420)
        .tint(accent)
        .controlSize(.regular)
        .toggleStyle(.switch)
        .background(SettingsWindowChromeConfigurator())
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
                    ForEach(IslandPage.allCases, id: \.rawValue) { page in
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
                    Text("Paste requires Accessibility permission for Apollo")
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
        .nativeSettingsFormStyle()
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
                            ForEach(IslandPage.allCases, id: \.rawValue) { page in
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
        .nativeSettingsFormStyle()
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

                Toggle("Always use approach when dragging file", isOn: $settings.alwaysUseApproachWhenDraggingFile)
                    .help("For file drags, approach is enabled even if disabled, and its width/height are doubled")
            }
        }
        .nativeSettingsFormStyle()
    }

    private func setPreviewFocus(_ focus: HoverPreviewFocus, isEditing: Bool) {
        settings.hoverPreviewFocus = isEditing ? focus : .all
    }

    private func setTitlePreviewFocus(isEditing: Bool, page: IslandPage? = nil) {
        if let page {
            settings.hoverPreviewTitlePage = page
        }
        setPreviewFocus(.titleSize, isEditing: isEditing)
    }

    private func titlePageLabel(_ page: IslandPage) -> String {
        switch page {
        case .clipboard: return "Clipboard"
        case .nowPlaying: return "Jot"
        case .box: return "Box"
        }
    }

    private func pageTitleAlignmentBinding(_ page: IslandPage) -> Binding<Int> {
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

    private func pageTitleSizeBinding(_ page: IslandPage) -> Binding<CGFloat> {
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

    private func pageTitleColorBinding(_ page: IslandPage) -> Binding<Color> {
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

    private func pageTitleUseAccentBinding(_ page: IslandPage) -> Binding<Bool> {
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

    private func pageTitleSymbolBinding(_ page: IslandPage) -> Binding<String> {
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

    private func resetTitleOverrides(for page: IslandPage) {
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

private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    private static var focusedWindowNumbers = Set<Int>()

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: nsView)
        }
    }

    private func configureWindowIfAvailable(from view: NSView) {
        guard let window = view.window else { return }
        let standardWindowMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        window.styleMask.formUnion(standardWindowMask)

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.toolbarButton)?.isHidden = true
        window.toolbar = nil
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        if !Self.focusedWindowNumbers.contains(window.windowNumber) {
            Self.focusedWindowNumbers.insert(window.windowNumber)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private func loadClipboardHistory() -> [ClipboardEntry] {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: AppStorageKey.clipboardHistory),
       let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
        return entries
    }
    let savedTexts = defaults.stringArray(forKey: AppStorageKey.clipboardHistory) ?? []
    return savedTexts.map { ClipboardEntry(text: $0) }
}

private extension View {
    func nativeSettingsFormStyle() -> some View {
        formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
    }
}

private func persistClipboardHistory(_ entries: [ClipboardEntry]) {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: AppStorageKey.clipboardHistory)
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
    var islandWindow: IslandPanel!
    var notchWindow: IslandPanel! { islandWindow }
    private var mouseTimer: DispatchSourceTimer?
    private var mousePollingInterval: TimeInterval = 0.2
    private var lastMousePoint = NSPoint.zero
    private var clipboardTimer: DispatchSourceTimer?
    private var nowPlayingTimer: Timer?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var idleCompactionWorkItem: DispatchWorkItem?
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
    private let mouseFastInterval: TimeInterval = 0.08
    private let mouseOpenInterval: TimeInterval = 0.14
    private let mouseApproachInterval: TimeInterval = 0.12
    private let mouseNearInterval: TimeInterval = 0.25
    private let mouseHardSleepInterval: TimeInterval = 0.45
    private let idleCompactionDelay: TimeInterval = 4.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        calculateScreenNotchDimensions()
        model.currentPage = settings.reopenLastPage ? settings.lastVisitedPage : settings.defaultPage
        setupNotchWindow()
        setupStatusItem()
        observeSettings()
        startMemoryPressureMonitoring()
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
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Apollo")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        item.menu = makeStatusMenu()
        statusItem = item
    }
    
private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Island", action: #selector(showNotchFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pin Island", action: #selector(togglePinnedState), keyEquivalent: ""))
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
        let (x, width, height) = hardwareNotchDimensions(for: NSScreen.screens.first)
        settings.updateHardwareNotchDimensions(x: x, width: width, height: height)
        applySettingsNotchSize()
    }

    private func applySettingsNotchSize() {
        notchWidth = settings.effectiveNotchWidth
        notchHeight = settings.effectiveNotchHeight
        panelWidth = scaledPanelWidth(for: settings)
        panelHeight = scaledPanelHeight(for: settings)
    }

    private func observeSettings() {
        settings.$notchWidth
            .combineLatest(settings.$notchHeight)
            .sink { [weak self] _ in
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

        model.$boxFiles
            .sink { files in
                let urls = files.map(\.url)
                if urls.isEmpty {
                    BoxIconCache.shared.removeAll()
                } else {
                    BoxIconCache.shared.trim(keeping: urls)
                }
            }
            .store(in: &settingsCancellables)

        model.$jotNotes
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
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

    private func startMemoryPressureMonitoring() {
        guard memoryPressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self] in
            self?.purgeCachesForMemoryPressure()
        }
        source.resume()
        memoryPressureSource = source
    }

    private func purgeCachesForMemoryPressure() {
        let urls = model.boxFiles.map(\.url)
        if urls.isEmpty {
            BoxIconCache.shared.removeAll()
        } else {
            BoxIconCache.shared.trim(keeping: urls)
        }
    }

    private func showSettingsPreview() {
        guard let window = islandWindow else { return }
        cancelIdleCompaction()
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

    private func updateNotchWindowFrame(widthOverride: CGFloat? = nil, heightOverride: CGFloat? = nil) {
        guard let screen = NSScreen.screens.first, let window = notchWindow else { return }
        let screenRect = screen.frame
        let defaultWidth = max(panelWidth, notchWidth)
        let windowWidth = widthOverride ?? defaultWidth
        let windowHeight = heightOverride ?? window.frame.height
        
        // Correct window positioning: Center the window's midpoint on the hardware notch's midpoint
        let notchX = settings.hardwareNotchX
        let notchWidth = settings.effectiveNotchWidth
        let windowX = notchX - (windowWidth - notchWidth) / 2
        let windowY = screenRect.maxY - windowHeight

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
        let windowHeight = settings.effectiveNotchHeight
        
        let notchX = settings.hardwareNotchX
        let notchWidthActual = settings.effectiveNotchWidth
        let windowX = notchX - (windowWidth - notchWidthActual) / 2
        let windowY = screenRect.maxY - settings.effectiveNotchHeight

        let initialRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        islandWindow = IslandPanel(
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
            .onPreferenceChange(UnifiedNotchContainer.ShellHeightKey.self) { [weak self] newHeight in
                guard let self else { return }
                // This is the new central point for animating the window frame's height.
                // It's driven by the view's own animated size.
                self.updateWindowFrameForNewHeight(newHeight)
            }
        
        notchWindow.contentView = NSHostingView(rootView: rootHubView)
        notchWindow.orderFrontRegardless()
    }

    private func advancePage(direction: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.carouselDragOffset = 0
            withAnimation(self.settings.carouselAnimation) {
                let next = clamp(self.model.currentPage + direction, min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
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

        let rawText = pasteboard.string(forType: .string)
        let trimmedText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)

        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? [])
        .filter(\.isFileURL)

        guard (trimmedText?.isEmpty == false) || !fileURLs.isEmpty else { return }

        let entry = ClipboardEntry(text: trimmedText, fileURLs: fileURLs)
        guard model.clipboardItems.first?.signature != entry.signature else { return }

        model.clipboardItems.removeAll { $0.signature == entry.signature }
        model.clipboardItems.insert(entry, at: 0)
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
        if entry.hasText {
            pasteboard.setString(entry.normalizedText, forType: .string)
        }
        if entry.hasFiles {
            _ = pasteboard.writeObjects(entry.fileURLs as [NSURL])
        }
        model.clipboardPulseItemID = entry.id
        model.clipboardItems.removeAll { $0.signature == entry.signature }
        model.clipboardItems.insert(entry, at: 0)
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
        showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
    }

    func openBoxPage() {
        showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
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

    private func stopMousePolling() {
        mouseTimer?.cancel()
        mouseTimer = nil
    }

    private func startMousePolling() {
        if mouseTimer != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + mousePollingInterval, repeating: mousePollingInterval, leeway: .milliseconds(140))
        timer.setEventHandler { [weak self] in
            self?.pollMouseLocation()
        }
        timer.resume()
        mouseTimer = timer
    }

    private struct ProximityZones {
        let notchRect: CGRect
        let notchEdgeRect: CGRect
        let approachRect: CGRect
        let isHoveringEdge: Bool
    }

    private func makeProximityZones(screenRect: CGRect, point: NSPoint) -> ProximityZones {
        let edge = settings.clampedNotchEdgeThickness
        let isFileDrag = isDraggingFile()
        let forceApproachForDrag = isFileDrag && settings.alwaysUseApproachWhenDraggingFile
        let disableApproachForCurrentInput = settings.disableApproach && !forceApproachForDrag
        let approachScale: CGFloat = forceApproachForDrag ? 2.0 : 1.0
        let approachWidth = disableApproachForCurrentInput ? 0 : settings.clampedApproachWidth * approachScale
        let approachHeight = disableApproachForCurrentInput ? 0 : settings.clampedApproachHeight * approachScale
        let edgeNotchWidth = settings.effectiveNotchWidth
        let edgeNotchHeight = settings.effectiveNotchHeight
        let edgeNotchLeft = settings.hardwareNotchX

        let notchRect = CGRect(
            x: edgeNotchLeft,
            y: screenRect.height - edgeNotchHeight,
            width: edgeNotchWidth,
            height: edgeNotchHeight
        )
        let notchEdgeRect = notchRect.insetBy(dx: -edge, dy: -edge)
        let approachRect = CGRect(
            x: notchEdgeRect.minX - approachWidth,
            y: notchEdgeRect.minY - approachHeight,
            width: notchEdgeRect.width + approachWidth * 2,
            height: approachHeight
        )
        let isHoveringEdge = isPointInNotchEdge(point, notchRect: notchRect, edge: edge)

        return ProximityZones(
            notchRect: notchRect,
            notchEdgeRect: notchEdgeRect,
            approachRect: approachRect,
            isHoveringEdge: isHoveringEdge
        )
    }

    private func shouldTrack(point: NSPoint, zones: ProximityZones) -> Bool {
        zones.isHoveringEdge || zones.approachRect.contains(point)
    }

    private func updateMousePollingInterval(for point: NSPoint, screenRect: CGRect, isTrackingZone: Bool, isHoveringEdge: Bool) {
        let distanceToTop = screenRect.height - point.y
        let edge = settings.clampedNotchEdgeThickness
        let approachHeight = settings.disableApproach ? 0 : settings.clampedApproachHeight
        let nearTopBand = distanceToTop <= (activationYBuffer + edge + approachHeight + 220)

        let desiredInterval: TimeInterval
        if model.isExpanded || model.isPinned {
            desiredInterval = mouseOpenInterval
        } else if isHoveringEdge {
            desiredInterval = mouseFastInterval
        } else if isTrackingZone {
            desiredInterval = mouseApproachInterval
        } else if nearTopBand {
            desiredInterval = mouseNearInterval
        } else {
            desiredInterval = mouseHardSleepInterval
        }

        let targetInterval = (!model.isExpanded && model.expansionProgress > 0 && !model.isPinned)
            ? min(desiredInterval, 0.05)
            : desiredInterval

        if targetInterval != mousePollingInterval {
            mousePollingInterval = targetInterval
            mouseTimer?.schedule(
                deadline: .now() + mousePollingInterval,
                repeating: mousePollingInterval,
                leeway: .milliseconds(180)
            )
        }
    }

    private func pollMouseLocation() {
        guard let screen = NSScreen.screens.first else { return }
        let globalPoint = NSEvent.mouseLocation
        let screenRect = screen.frame
        let mouseX = globalPoint.x
        let mouseY = globalPoint.y

        let deltaX = abs(mouseX - lastMousePoint.x)
        let deltaY = abs(mouseY - lastMousePoint.y)
        let zones = makeProximityZones(screenRect: screenRect, point: globalPoint)
        let isTrackingZone = shouldTrack(point: globalPoint, zones: zones)

        if deltaX < 0.75 && deltaY < 0.75 && !model.isExpanded {
            if (model.observedFileToast != nil || model.isToastDismissing) {
                return
            }

            if !isTrackingZone, !model.isPinned, model.expansionProgress > 0 {
                approachStartTime = nil
                if let window = notchWindow {
                    window.ignoresMouseEvents = true
                    window.alphaValue = 1.0
                }
                withAnimation(settings.notchOpenAnimation) {
                    model.expansionProgress = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, !self.model.isExpanded, self.model.expansionProgress == 0 else { return }
                    self.notchWindow?.alphaValue = 0.0
                }
            }
            return
        }
        lastMousePoint = globalPoint

        if suppressProximityUntilExit {
            if isMouseWithinReopenZone(point: globalPoint, zones: zones) {
                return
            }
            suppressProximityUntilExit = false
        }

        if model.isPinned {
            return
        }
        updateMousePollingInterval(for: globalPoint, screenRect: screenRect, isTrackingZone: isTrackingZone, isHoveringEdge: zones.isHoveringEdge)

        // Stay alive in hard-sleep mode so the app can wake proximity checks without an external monitor.
        if !isTrackingZone && !model.isExpanded && model.expansionProgress == 0 && !model.isPinned {
            return
        }

        if !model.isPinned && !model.isExpanded {
            if !isTrackingZone {
                return
            }
        }

        evaluateMouseCoordinates(globalPoint, zones: zones)
    }

    private func isMouseWithinReopenZone(point: NSPoint, zones: ProximityZones) -> Bool {
        if settings.disableApproach {
            return zones.isHoveringEdge
        }
        return zones.approachRect.contains(point)
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
            guard let self else { return }
            self.hoverCloseWorkItem = nil
            self.hidePanel()
        }
        hoverCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func evaluateMouseCoordinates(_ globalPoint: NSPoint, zones: ProximityZones) {
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

        let notchEdgeRect = zones.notchEdgeRect
        let isDirectHoverOverNotch = zones.isHoveringEdge
        let approachRect = zones.approachRect
        let isFileDrag = isDraggingFile()
        let forceApproachForDrag = isFileDrag && settings.alwaysUseApproachWhenDraggingFile
        let disableApproachForCurrentInput = settings.disableApproach && !forceApproachForDrag
        let approachHeight = max(0, approachRect.height)
        let isWithinExpandedPanel = window.frame.contains(globalPoint)

        if disableApproachForCurrentInput {
            if model.isPinned {
                showPanel(expanded: true, pinned: true)
                return
            }
            if model.isExpanded {
                if isWithinExpandedPanel || isDirectHoverOverNotch {
                    hoverCloseWorkItem?.cancel()
                    hoverCloseWorkItem = nil
                    return
                }
                scheduleHoverCloseIfNeeded()
                return
            }
            if isDirectHoverOverNotch {
                let isFileDrag = isDraggingFile()
                let preferredPage = isFileDrag ? IslandPage.box.rawValue : nil
                showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
            }
            return
        }

        if !model.isPinned && !model.isExpanded {
            if !(approachRect.contains(globalPoint) || zones.isHoveringEdge) {
                approachStartTime = nil
                hidePanel()
                return
            }
            if !zones.isHoveringEdge {
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
                hoverCloseWorkItem = nil
                return
            }
            scheduleHoverCloseIfNeeded()
            return
        }
        
        if approachRect.contains(globalPoint) || zones.isHoveringEdge {
            let totalHeight = max(1, approachHeight)
            let distance = max(0, notchEdgeRect.minY - mouseY)
            let baseProgress = min(1.0, max(0.0, 1.0 - (distance / totalHeight)))
            let targetProgress = zones.isHoveringEdge ? 1.0 : baseProgress
            if abs(model.expansionProgress - targetProgress) > 0.01 {
                model.expansionProgress = targetProgress
            }
            if window.alphaValue != 1.0 {
                window.alphaValue = 1.0
            }
            window.ignoresMouseEvents = !(isFileDrag && approachRect.contains(globalPoint))

            if isDirectHoverOverNotch {
                let isFileDrag = isDraggingFile()
                let preferredPage = isFileDrag ? IslandPage.box.rawValue : nil
                showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
            }
        } else {
            hidePanel()
        }
    }
    
    private func showPanel(expanded: Bool, pinned: Bool, preferredPage: Int? = nil) {
        guard let window = islandWindow else { return }
        cancelIdleCompaction()
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
                model.currentPage = IslandPage.box.rawValue
            } else {
                model.currentPage = settings.defaultPage
            }
        }
        window.alphaValue = 1.0
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
    }
    
    private func hidePanel(preserveCloseProgress: Bool = false) {
        guard let window = islandWindow else { return }
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
        
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isPinned else { return }
            window.alphaValue = 0.0
            window.ignoresMouseEvents = true
            self.scheduleIdleCompactionIfNeeded()
        }
        pendingHideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: hideWorkItem)
    }

    private func cancelIdleCompaction() {
        idleCompactionWorkItem?.cancel()
        idleCompactionWorkItem = nil
    }

    private func scheduleIdleCompactionIfNeeded() {
        cancelIdleCompaction()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.model.isExpanded,
                  !self.model.isPinned,
                  self.model.observedFileToast == nil,
                  !self.model.isToastDismissing,
                  !(self.settings.showHoverPreviews && self.settings.hoverPreviewFocus != .all) else {
                return
            }
            self.performIdleCompaction()
        }
        idleCompactionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + idleCompactionDelay, execute: workItem)
    }

    private func performIdleCompaction() {
        BoxIconCache.shared.removeAll()
        if !model.isExpanded && !model.isPinned {
            model.carouselDragOffset = 0
            model.closeGestureProgress = 0
            approachStartTime = nil
        }
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
        guard let window = islandWindow else { return }
        cancelIdleCompaction()
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        model.isToastDismissing = false
        model.isExpanded = false
        model.isPinned = false
        model.expansionProgress = 0.0
        window.alphaValue = 1.0
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
        withAnimation(settings.notchOpenAnimation) {
            model.expansionProgress = 1.0
        }
    }

    func dismissToastAndHideNotch() {
        scheduleIdleCompactionIfNeeded()
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
    
    private func updateWindowFrameForNewHeight(_ newHeight: CGFloat) {
        guard let screen = NSScreen.screens.first, let window = notchWindow else { return }
        
        // Don't interfere when settings previews are active, as they use a fixed large frame.
        if settings.showHoverPreviews && settings.hoverPreviewFocus != .all {
            return
        }
        
        guard newHeight.isFinite, newHeight > 1 else { return }

        // Keep the window width fixed at the maximum possible panel width to avoid clipping content during animation.
        let windowWidth = max(self.panelWidth, self.notchWidth)
        let windowHeight = newHeight

        // Correct window positioning: Center the window's midpoint on the hardware notch's midpoint
        let notchX = settings.hardwareNotchX
        let notchWidth = settings.effectiveNotchWidth
        let windowX = notchX - (windowWidth - notchWidth) / 2
        let windowY = screen.frame.maxY - windowHeight

        let newFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cancelIdleCompaction()
        stopMousePolling()
        clipboardTimer?.cancel()
        nowPlayingTimer?.invalidate()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
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

final class IslandPanel: NSPanel {
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
    @State private var clipboardTapFeedbackProgress: CGFloat = 0
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
    @State private var boxPreviewImages: [URL: NSImage] = [:]
    @State private var boxPreviewLoadingURLs = Set<URL>()
    @State private var clipboardFilePreviews: [String: NSImage] = [:]
    @State private var clipboardFilePreviewLoadingPaths = Set<String>()
    @State private var showShapeHandles = false
    private let clipboardColumns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8), count: 3)

    // This preference key is used to report the animated height of the island back to the AppDelegate.
    struct ShellHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

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
        case IslandPage.clipboard.rawValue:
            return clipboardCanCloseFromSwipe
        case IslandPage.nowPlaying.rawValue:
            return model.activeJotID != nil ? jotEditorCanCloseFromSwipe : jotCanCloseFromSwipe
        case IslandPage.box.rawValue:
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
        let didChange = abs(clipboardScrollOffset - scrollOffset) > 0.5
            || abs(clipboardContentHeight - contentHeight) > 0.5
            || abs(clipboardViewportHeight - viewportHeight) > 0.5
        guard didChange else { return }
        clipboardScrollOffset = scrollOffset
        clipboardContentHeight = contentHeight
        clipboardViewportHeight = viewportHeight
        syncVerticalSwipeGate()
    }

    private func updateJotScrollGate(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let didChange = abs(jotScrollOffset - scrollOffset) > 0.5
            || abs(jotContentHeight - contentHeight) > 0.5
            || abs(jotViewportHeight - viewportHeight) > 0.5
        guard didChange else { return }
        jotScrollOffset = scrollOffset
        jotContentHeight = contentHeight
        jotViewportHeight = viewportHeight
        syncVerticalSwipeGate()
    }

    private func updateBoxScrollGate(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let didChange = abs(boxScrollOffset - scrollOffset) > 0.5
            || abs(boxContentHeight - contentHeight) > 0.5
            || abs(boxViewportHeight - viewportHeight) > 0.5
        guard didChange else { return }
        boxScrollOffset = scrollOffset
        boxContentHeight = contentHeight
        boxViewportHeight = viewportHeight
        syncVerticalSwipeGate()
    }

    private func updateJotEditorScrollGate(scrollOffset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        let nextAtBottom = isAtScrollBottom(scrollOffset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
        let didChange = abs(jotEditorScrollOffset - scrollOffset) > 0.5
            || abs(jotEditorContentHeight - contentHeight) > 0.5
            || abs(jotEditorViewportHeight - viewportHeight) > 0.5
            || jotEditorAtBottom != nextAtBottom
        guard didChange else { return }
        jotEditorScrollOffset = scrollOffset
        jotEditorContentHeight = contentHeight
        jotEditorViewportHeight = viewportHeight
        jotEditorAtBottom = nextAtBottom
        syncVerticalSwipeGate()
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

    private func previewTitleSample(page: IslandPage, width: CGFloat) -> some View {
        let size = settings.titleSize(for: page)
        let color = Color(settings.titleColor(for: page))
        let alignment = settings.titleAlignment(for: page).alignment
        return Text("Title")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
            .frame(width: width, alignment: alignment)
    }

    private var boxMenuBarControls: some View {
        let isBoxPage = (IslandPage(rawValue: model.currentPage) ?? .clipboard) == .box
        let showControls = model.isExpanded && isBoxPage && !model.boxFiles.isEmpty
        return GeometryReader { geo in
            let edgeNotchWidth = settings.effectiveNotchWidth
            let notchRight = (geo.size.width + edgeNotchWidth) / 2
            let controlWidth: CGFloat = 180
            let xOffset = notchRight + 10

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
            .frame(width: controlWidth, alignment: .leading)
            .offset(x: xOffset, y: 6)
            .opacity(showControls ? 1.0 : 0.0)
            .zIndex(5)
        }
    }
    
    var body: some View {
        let panelWidth = scaledPanelWidth(for: settings)
        let panelHeight = scaledPanelHeight(for: settings)

        let notchWidth = settings.effectiveNotchWidth
        let notchHeight = settings.effectiveNotchHeight
        let rawProgress = model.expansionProgress
        let progress = rawProgress.isFinite ? max(0, min(1, rawProgress)) : 0
        let easedProgress = progress * progress * (3 - 2 * progress)
        let rawShellWidth = notchWidth + ((panelWidth - notchWidth) * easedProgress)
        let rawShellHeight = notchHeight + ((panelHeight - notchHeight) * easedProgress)
        let shellWidth = safeDimension(rawShellWidth, fallback: panelWidth)
        let shellHeight = safeDimension(rawShellHeight, fallback: panelHeight)
        let islandWidth = notchWidth + ((panelWidth - notchWidth) * easedProgress * 0.4)
        let islandHeight = notchHeight
        let cornerRadius = safeDimension(max(4, settings.cornerRadius * (0.6 + 0.4 * easedProgress)), fallback: 8)
        let contentProgress = easedProgress.isFinite ? max(0, min(1, (easedProgress - 0.18) / 0.82)) : 0
        let showToastOnly = (model.observedFileToast != nil || model.isToastDismissing) && !model.isExpanded && !model.isPinned
        let containerHeight = safeDimension(showToastOnly ? max(panelHeight, toastPanelHeight) : panelHeight, fallback: panelHeight)
        let toastWidth = toastPanelWidth
        let containerWidth = max(panelWidth, notchWidth)
        let closeProgress = max(0, min(1, model.closeGestureProgress))
        let closeEase = closeProgress * closeProgress * (3 - 2 * closeProgress)
        let closeOffset = -44 * closeEase
        let closeScale = 1 - (0.14 * closeEase)
        let shouldRenderExpandedContent = model.isExpanded || model.isPinned
        
        ZStack(alignment: .top) {
            // Overlay previews so they don't impact the measured height of the island body
            if settings.showHoverPreviews {
                settingsPreviewOverlay
                    .zIndex(100)
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
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ShellHeightKey.self, value: proxy.size.height + (baseNotchHeight - 2))
                })
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

                            if showShapeHandles {
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
                                .opacity(0.001)

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
                                .opacity(0.001)

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
                                .opacity(0.001)
                            }

                            if shouldRenderExpandedContent && contentProgress > 0.01 {
                                globalTitleOverlay(islandWidth: islandWidth, islandHeight: islandHeight)
                                    .opacity(contentProgress)
                                globalControlsOverlay(islandWidth: islandWidth, islandHeight: islandHeight)
                                    .opacity(contentProgress)
                            }
                        }
                        .frame(width: islandWidth, height: islandHeight)
                        .padding(.top, 0) // PULLED FLUSH

                        if shouldRenderExpandedContent && contentProgress > 0.01 {
                            GeometryReader { geo in
                                let pageWidth = safeDimension(geo.size.width, fallback: 1)
                                HStack(spacing: 0) {
                                    Group {
                                        if shouldRenderPage(IslandPage.clipboard.rawValue) {
                                            clipboardPage
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: pageWidth)
                                    Group {
                                        if shouldRenderPage(IslandPage.nowPlaying.rawValue) {
                                            sidebarPage
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: pageWidth)
                                    Group {
                                        if shouldRenderPage(IslandPage.box.rawValue) {
                                            boxPage
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: pageWidth)
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
                    .frame(width: shellWidth, height: shellHeight, alignment: .top)
                    .background(Color(settings.backgroundColor))
                    .clipShape(BottomRoundedRectangle(cornerRadius: cornerRadius))
                    .shadow(color: Color.black.opacity(0.22 * contentProgress), radius: 18 * contentProgress, x: 0, y: 10 * contentProgress)
                    .animation(settings.notchOpenAnimation, value: model.expansionProgress)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ShellHeightKey.self, value: proxy.size.height)
                    })
                } // End if !showToastOnly
            } // End ZStack
        } // End ZStack
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
        .onReceive(model.$isExpanded) { expanded in
            if !expanded {
                selectedBoxFileIDs.removeAll()
                highlightedClipboardID = nil
            }
            syncVerticalSwipeGate()
        }
        .onReceive(model.$isPinned) { _ in
            syncVerticalSwipeGate()
        }
        .onReceive(model.$clipboardItems) { items in
            pruneClipboardPreviewState(keeping: items)
        }
        .onReceive(model.$boxFiles) { files in
            pruneBoxPreviewState(keeping: files.map(\.url))
        }
    }
    
    @ViewBuilder
    private var settingsPreviewOverlay: some View {
        GeometryReader { geo in
            let expandedWidth = settings.clampedNotchWidth
            let expandedHeight = settings.clampedNotchHeight
            let edgeNotchWidth = settings.effectiveNotchWidth
            let edgeNotchHeight = settings.effectiveNotchHeight
            let edge = settings.clampedNotchEdgeThickness
            let approachWidth = settings.clampedApproachWidth
            let approachHeight = settings.clampedApproachHeight
            let focus = settings.hoverPreviewFocus
            let accent = Color(settings.accentColor)
            let expandedX = (geo.size.width - expandedWidth) / 2
            let edgeNotchX = (geo.size.width - edgeNotchWidth) / 2
            let expandedRect = CGRect(x: expandedX, y: 0, width: expandedWidth, height: expandedHeight)
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
            let innerRadius = settings.cornerRadius * 0.6

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
                            BottomRoundedRectangle(cornerRadius: innerRadius + edgeInset)
                                .fill(accent.opacity(0.45))
                                .frame(width: outerRect.width, height: outerRect.height)
                                .position(x: outerRect.midX, y: outerRect.midY)
                        }
                        BottomRoundedRectangle(cornerRadius: innerRadius)
                            .fill(Color(settings.backgroundColor))
                            .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                            .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                        BottomRoundedRectangle(cornerRadius: innerRadius)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                            .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                    case .islandSize:
                        BottomRoundedRectangle(cornerRadius: settings.cornerRadius)
                            .fill(Color(settings.backgroundColor))
                            .frame(width: expandedRect.width, height: expandedRect.height)
                            .position(x: expandedRect.midX, y: expandedRect.midY)
                        BottomRoundedRectangle(cornerRadius: settings.cornerRadius)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            .frame(width: expandedRect.width, height: expandedRect.height)
                            .position(x: expandedRect.midX, y: expandedRect.midY)
                    case .notchEdge:
                        if edgeInset > 0 {
                            BottomRoundedRectangle(cornerRadius: innerRadius + edgeInset)
                                .fill(accent.opacity(0.55))
                                .frame(width: outerRect.width, height: outerRect.height)
                                .position(x: outerRect.midX, y: outerRect.midY)
                        }
                        BottomRoundedRectangle(cornerRadius: innerRadius)
                            .fill(Color(settings.backgroundColor))
                            .frame(width: edgeNotchRect.width, height: edgeNotchRect.height)
                            .position(x: edgeNotchRect.midX, y: edgeNotchRect.midY)
                        BottomRoundedRectangle(cornerRadius: innerRadius)
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
                            .position(x: edgeNotchRect.midX, y: previewY)
                    case .titleSize:
                        previewTitleSample(page: settings.hoverPreviewTitlePage, width: edgeNotchRect.width)
                            .position(x: edgeNotchRect.midX, y: previewY)
                    case .cornerRadius:
                        RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 2)
                            .frame(width: 140, height: 52)
                            .position(x: edgeNotchRect.midX, y: previewY)
                    case .sensitivityCarousel:
                        previewBadge("Carousel sensitivity \(String(format: "%.2f", settings.carouselSensitivity))", accent: accent)
                            .position(x: edgeNotchRect.midX, y: previewY)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .opacity(0.8)
        .padding(.top, 4)
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

    private func shouldRenderPage(_ index: Int) -> Bool {
        if abs(model.carouselDragOffset) > 1 {
            if model.carouselDragOffset < 0 {
                return index == model.currentPage || index == min(IslandPage.box.rawValue, model.currentPage + 1)
            }
            if model.carouselDragOffset > 0 {
                return index == model.currentPage || index == max(IslandPage.clipboard.rawValue, model.currentPage - 1)
            }
        }
        return index == model.currentPage
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
                clipboardCellContent(item)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .center) {
            if item.isTextOnly {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accentColor.opacity(0.85), lineWidth: 1.2)
            }
        }
        .overlay(alignment: .center) {
            if isHighlighted {
                ClipboardTapFeedbackGlyph(color: .green, progress: clipboardTapFeedbackProgress)
            }
        }
    }

    private struct ClipboardTapFeedbackGlyph: View {
        let color: Color
        let progress: CGFloat

        var body: some View {
            let p = max(0, min(1, progress))
            ZStack {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color.opacity(0.98))
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: max(1, 18 * p))
                    }
                    .opacity(0.6 + 0.4 * p)
            }
            .frame(width: 30, height: 30)
            .scaleEffect(0.85 + 0.15 * p)
        }
    }

    @ViewBuilder
    private func clipboardCellContent(_ item: ClipboardEntry) -> some View {
        if item.hasFiles {
            let urls = item.fileURLs
            if urls.count == 1, let fileURL = urls.first {
                clipboardSingleFileContent(fileURL)
            } else {
                clipboardMultiFileContent(item)
            }
        } else {
            Text(item.normalizedText)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clipboardSingleFileContent(_ fileURL: URL) -> some View {
        let preview = clipboardFilePreviews[fileURL.path]
        let fileName = fileURL.lastPathComponent

        return VStack(alignment: .leading, spacing: 8) {
            clipboardSingleVisual(for: fileURL, preview: preview)
            .onAppear {
                requestClipboardFilePreviewIfNeeded(for: fileURL)
            }

            Text(fileName)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func clipboardMultiFileContent(_ item: ClipboardEntry) -> some View {
        let summary = clipboardMultiItemSummary(for: item.fileURLs)
        let previewURLs = Array(item.fileURLs.prefix(4))
        let folderNamesLine = clipboardJoinedFolderNames(for: item.fileURLs)
        let showFolderNames = !folderNamesLine.isEmpty
        let compactFolderStyle = summary == "Multiple folders"
        return VStack(alignment: .leading, spacing: compactFolderStyle ? 4 : 8) {
            clipboardMultiVisualGrid(urls: previewURLs)
                .onAppear {
                    for url in previewURLs {
                        requestClipboardFilePreviewIfNeeded(for: url)
                    }
                }

            Text(summary)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            if showFolderNames {
                Text(folderNamesLine)
                    .font(compactFolderStyle ? .system(size: 10, weight: .regular) : .caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func clipboardJoinedFolderNames(for urls: [URL]) -> String {
        let names = urls.filter(isDirectoryURL(_:)).map { url in
            let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? url.path : name
        }
        return names.joined(separator: ", ")
    }

    @ViewBuilder
    private func clipboardSingleVisual(for url: URL, preview: NSImage?) -> some View {
        if let preview {
            let fitted = fittedBoxPreviewSize(for: preview, maxDimension: 84)
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: fitted.width, height: fitted.height)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Image(systemName: clipboardFileSymbol(for: url))
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
        }
    }

    private func clipboardMultiVisualGrid(urls: [URL]) -> some View {
        let columns = [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 4),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 4)
        ]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                if index < urls.count {
                    clipboardMultiVisualCell(url: urls[index])
                } else {
                    Color.clear
                        .frame(height: 34)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func clipboardMultiVisualCell(url: URL) -> some View {
        if let preview = clipboardFilePreviews[url.path] {
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: clipboardFileSymbol(for: url))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        }
    }

    private func clipboardMultiItemSummary(for urls: [URL]) -> String {
        var folderCount = 0
        var fileCount = 0
        for url in urls {
            if isDirectoryURL(url) {
                folderCount += 1
            } else {
                fileCount += 1
            }
        }

        if folderCount > 0 && fileCount > 0 {
            return "Multiple folders and files"
        }
        if folderCount > 1 {
            return "Multiple folders"
        }
        if fileCount > 1 {
            return "Multiple files"
        }
        if folderCount == 1 {
            return "Folder"
        }
        if fileCount == 1 {
            return "File"
        }
        return "Multiple items"
    }

    private func clipboardTypeDescription(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey])
        if let desc = values?.localizedTypeDescription, !desc.isEmpty {
            return desc
        }
        let ext = url.pathExtension
        return ext.isEmpty ? "File" : ext.uppercased()
    }

    private func clipboardFileSymbol(for url: URL) -> String {
        if isDirectoryURL(url) {
            return "folder"
        }
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif":
            return "photo"
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "webm", "mpeg", "mpg", "3gp", "ts", "m2ts":
            return "video"
        case "pdf":
            return "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox"
        default:
            return "doc"
        }
    }

    private func isDirectoryURL(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func requestClipboardFilePreviewIfNeeded(for url: URL) {
        guard BoxIconCache.shared.shouldAttemptPreview(for: url) else { return }
        guard clipboardFilePreviews[url.path] == nil else { return }
        guard !clipboardFilePreviewLoadingPaths.contains(url.path) else { return }

        clipboardFilePreviewLoadingPaths.insert(url.path)
        DispatchQueue.global(qos: .utility).async {
            let preview = BoxIconCache.shared.displayImage(for: url, targetSize: 180)
            DispatchQueue.main.async {
                clipboardFilePreviewLoadingPaths.remove(url.path)
                clipboardFilePreviews[url.path] = preview
            }
        }
    }

    private func pruneClipboardPreviewState(keeping items: [ClipboardEntry]) {
        let keepPaths = Set(items.flatMap { $0.filePaths })
        clipboardFilePreviews = clipboardFilePreviews.filter { keepPaths.contains($0.key) }
        clipboardFilePreviewLoadingPaths = Set(clipboardFilePreviewLoadingPaths.filter { keepPaths.contains($0) })
    }
    
    private func copyClipboard(_ item: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        if item.hasText {
            NSPasteboard.general.setString(item.normalizedText, forType: .string)
        }
        if item.hasFiles {
            _ = NSPasteboard.general.writeObjects(item.fileURLs as [NSURL])
        }
        if settings.clipboardActionOption == .paste, let delegate = NSApp.delegate as? AppDelegate {
            delegate.postPasteCommand()
        }
        highlightedClipboardID = item.id
        clipboardTapFeedbackProgress = 0

        withAnimation(.easeOut(duration: 0.16)) {
            clipboardTapFeedbackProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            guard highlightedClipboardID == item.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                clipboardTapFeedbackProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
                if highlightedClipboardID == item.id {
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
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(model.boxFiles) { file in
                                    boxItemView(file: file, maxSize: maxSize)
                                }
                            }
                            .frame(width: w, alignment: .center)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(key: BoxContentHeightKey.self, value: proxy.size.height)
                                }
                            )
                            .overlay(alignment: .top) {
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: BoxScrollOffsetKey.self,
                                            value: max(0, -proxy.frame(in: .named("BoxScrollView")).minY)
                                        )
                                }
                            }
                        }
                        .coordinateSpace(name: "BoxScrollView")
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: BoxViewportHeightKey.self, value: proxy.size.height)
                            }
                        )
                        .onPreferenceChange(BoxScrollOffsetKey.self) { offset in
                            updateBoxScrollGate(
                                scrollOffset: offset,
                                contentHeight: boxContentHeight,
                                viewportHeight: boxViewportHeight
                            )
                        }
                        .onPreferenceChange(BoxContentHeightKey.self) { contentHeight in
                            updateBoxScrollGate(
                                scrollOffset: boxScrollOffset,
                                contentHeight: contentHeight,
                                viewportHeight: boxViewportHeight
                            )
                        }
                        .onPreferenceChange(BoxViewportHeightKey.self) { viewportHeight in
                            updateBoxScrollGate(
                                scrollOffset: boxScrollOffset,
                                contentHeight: boxContentHeight,
                                viewportHeight: viewportHeight
                            )
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
        let preview = boxPreviewImages[file.url]
        let previewSize = preview.map { fittedBoxPreviewSize(for: $0, maxDimension: size) } ?? CGSize(width: size, height: size)
        let isSelected = selectedBoxFileIDs.contains(file.id)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 6) {
                Group {
                    if let preview {
                        BoxIconView(nsImage: preview)
                    } else {
                        BoxPreviewPlaceholder(isLoading: boxPreviewLoadingURLs.contains(file.url))
                    }
                }
                    .frame(width: previewSize.width, height: previewSize.height)
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
                                .frame(width: max(12, previewSize.width * 0.7), height: 2)
                        }
                    }
                    .frame(width: previewSize.width + 6)
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
        .onAppear {
            requestBoxPreviewIfNeeded(for: file.url, targetSize: size)
        }
        .frame(
            width: previewSize.width + 8,
            height: settings.showBoxFileNames ? previewSize.height + 36 : previewSize.height,
            alignment: .center
        )
    }

    private func fittedBoxPreviewSize(for image: NSImage, maxDimension: CGFloat) -> CGSize {
        let maxDim = max(1, maxDimension)
        let rawWidth = max(1, image.size.width)
        let rawHeight = max(1, image.size.height)
        let scale = maxDim / max(rawWidth, rawHeight)
        return CGSize(width: rawWidth * scale, height: rawHeight * scale)
    }

    private func requestBoxPreviewIfNeeded(for url: URL, targetSize: CGFloat) {
        guard BoxIconCache.shared.shouldAttemptPreview(for: url) else { return }
        guard boxPreviewImages[url] == nil else { return }
        guard !boxPreviewLoadingURLs.contains(url) else { return }

        let requestSize = quantizedPreviewTargetSize(targetSize)
        boxPreviewLoadingURLs.insert(url)

        DispatchQueue.global(qos: .utility).async {
            let image = BoxIconCache.shared.displayImage(for: url, targetSize: requestSize)
            DispatchQueue.main.async {
                boxPreviewLoadingURLs.remove(url)
                guard model.boxFiles.contains(where: { $0.url == url }) else { return }
                boxPreviewImages[url] = image
            }
        }
    }

    private func quantizedPreviewTargetSize(_ targetSize: CGFloat) -> CGFloat {
        let clamped = max(72, min(320, targetSize))
        return ceil(clamped / 24) * 24
    }

    private func pruneBoxPreviewState(keeping urls: [URL]) {
        let keep = Set(urls)
        boxPreviewImages = boxPreviewImages.filter { keep.contains($0.key) }
        boxPreviewLoadingURLs = Set(boxPreviewLoadingURLs.filter { keep.contains($0) })
    }

    private struct BoxPreviewPlaceholder: View {
        let isLoading: Bool

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.7))
                        .scaleEffect(0.75)
                        .offset(y: 12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
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
        let acceptedProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !acceptedProviders.isEmpty else { return false }

        let loadGroup = DispatchGroup()
        let resultLock = NSLock()
        var droppedURLs: [URL] = []

        for provider in acceptedProviders {
            loadGroup.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { loadGroup.leave() }
                guard let fileUrl = url else { return }
                resultLock.lock()
                droppedURLs.append(fileUrl)
                resultLock.unlock()
            }
        }

        loadGroup.notify(queue: .main) {
            let existing = Set(model.boxFiles.map(\.url))
            var seen = Set<URL>()
            var urlsToInsert: [URL] = []

            for url in droppedURLs where !existing.contains(url) {
                if seen.insert(url).inserted {
                    urlsToInsert.append(url)
                }
            }

            if !urlsToInsert.isEmpty {
                model.boxFiles.insert(contentsOf: urlsToInsert.reversed().map(BoxFile.init(url:)), at: 0)
                BoxIconCache.shared.prewarmDisplayImages(for: Array(urlsToInsert.prefix(24)), targetSize: 220)
            }

            if openBoxPage {
                model.currentPage = 2
                model.isExpanded = true
                model.expansionProgress = 1.0
            }
        }

        return true
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
        let page = IslandPage(rawValue: model.currentPage) ?? .clipboard
        let edgeNotchWidth = settings.effectiveNotchWidth

        return Color.clear
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let notchRight = (geo.size.width + edgeNotchWidth) / 2
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: notchRight + 12, y: 2)
                }
            }
            .frame(width: islandWidth, height: islandHeight)
    }

    private func globalTitleOverlay(islandWidth: CGFloat, islandHeight: CGFloat) -> some View {
        let page = IslandPage(rawValue: model.currentPage) ?? .clipboard
        let edgeNotchWidth = settings.effectiveNotchWidth
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
                GeometryReader { geo in
                    let notchLeft = (geo.size.width - edgeNotchWidth) / 2
                    if symbol != "empty" {
                        header(title: title, symbol: symbol, page: page)
                            .frame(maxWidth: max(0, notchLeft - 12), alignment: .trailing)
                            .offset(y: 2)
                    }
                }
            }
            .frame(width: islandWidth, height: islandHeight)
    }

    private func header(title: String, symbol: String, page: IslandPage) -> some View {
        let displaySymbol = settings.titleSymbol(for: page, fallback: symbol)
        return Label(title, systemImage: displaySymbol)
            .font(.system(size: settings.titleSize(for: page), weight: .bold))
            .foregroundColor(Color(settings.titleColor(for: page)))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
    }
}
