//
//  apolloApp.swift
//  apollo
//

import SwiftUI
import AppKit
import Combine
import ImageIO
import AVFoundation
import Darwin

// MARK: - Lightweight Page Models
enum IslandPage: Int, CaseIterable {
    case clipboard = 0
    case jot = 1
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

private let maxStoredClipboardTextLength = 512
private let maxDisplayedClipboardTextLength = 240

private func cappedClipboardText(_ text: String?, limit: Int = maxStoredClipboardTextLength) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    guard trimmed.count > limit else { return trimmed }
    let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
    return String(trimmed[..<endIndex])
}

struct ClipboardEntry: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var text: String?
    var filePaths: [String] = []
    var createdAt: Date = Date()
    var isDirectoryFlags: [String: Bool]? = nil
    var fileNames: [String]? = nil
    var fileSymbols: [String]? = nil
    var fileSummary: String? = nil
    var cachedGlyph: String? = nil
    var cachedDisplayTitle: String? = nil

    init(text: String) {
        self.text = cappedClipboardText(text)
        self.filePaths = []
        self.fileNames = []
        self.fileSymbols = []
        self.fileSummary = nil
        self.isDirectoryFlags = [:]
    }

    init(text: String?, fileURLs: [URL]) {
        let fileURLs = fileURLs.filter(\.isFileURL)
        self.text = fileURLs.isEmpty ? cappedClipboardText(text) : nil
        self.filePaths = fileURLs
            .map(\.path)
        self.createdAt = Date()

        var flags: [String: Bool] = [:]
        var names: [String] = []
        var symbols: [String] = []
        for url in fileURLs {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                flags[url.path] = isDir.boolValue
            } else {
                flags[url.path] = false
            }
            let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            names.append(name.isEmpty ? url.path : name)
            symbols.append(Self.fileSymbol(pathExtension: url.pathExtension, isDirectory: flags[url.path] == true))
        }
        self.isDirectoryFlags = flags
        self.fileNames = names
        self.fileSymbols = symbols
        self.fileSummary = Self.fileSummary(filePaths: self.filePaths, flags: flags)
    }

    func isDirectory(_ path: String) -> Bool {
        if let flags = isDirectoryFlags, let isDir = flags[path] {
            return isDir
        }
        return false
    }

    func normalizedForLightweightStorage() -> ClipboardEntry {
        var entry = self
        if !entry.filePaths.isEmpty {
            entry.text = nil
            if entry.fileNames?.count != entry.filePaths.count {
                entry.fileNames = entry.filePaths.map { path in
                    let name = (path as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? path : name
                }
            }
            if entry.fileSymbols?.count != entry.filePaths.count {
                entry.fileSymbols = entry.filePaths.map { path in
                    Self.fileSymbol(pathExtension: (path as NSString).pathExtension, isDirectory: entry.isDirectory(path))
                }
            }
            if entry.fileSummary == nil {
                entry.fileSummary = Self.fileSummary(filePaths: entry.filePaths, flags: entry.isDirectoryFlags ?? [:])
            }
        } else {
            entry.text = cappedClipboardText(entry.text)
            entry.fileNames = []
            entry.fileSymbols = []
            entry.fileSummary = nil
        }
        if entry.isDirectoryFlags == nil {
            entry.isDirectoryFlags = [:]
        }
        
        // Pre-calculate display properties
        if !entry.filePaths.isEmpty {
            let counts = Self.fileAndFolderCounts(filePaths: entry.filePaths, flags: entry.isDirectoryFlags ?? [:])
            if entry.filePaths.count == 1 {
                entry.cachedGlyph = entry.fileSymbol(at: 0)
                entry.cachedDisplayTitle = entry.fileName(at: 0)
            } else if counts.folderCount > 0 && counts.fileCount == 0 {
                entry.cachedGlyph = "folder"
                entry.cachedDisplayTitle = entry.fileSummaryText()
            } else if counts.fileCount > 0 && counts.folderCount == 0 {
                entry.cachedGlyph = Self.symbolForMultipleFiles(filePaths: entry.filePaths)
                entry.cachedDisplayTitle = entry.fileSummaryText()
            } else {
                entry.cachedGlyph = "folder.badge.plus"
                entry.cachedDisplayTitle = entry.fileSummaryText()
            }
        } else {
            entry.cachedGlyph = "doc.text"
            entry.cachedDisplayTitle = entry.normalizedText
        }
        
        return entry
    }

    func fileName(at index: Int) -> String {
        if let fileNames, fileNames.indices.contains(index), !fileNames[index].isEmpty {
            return fileNames[index]
        }
        guard filePaths.indices.contains(index) else { return "File" }
        let name = (filePaths[index] as NSString).lastPathComponent
        return name.isEmpty ? filePaths[index] : name
    }

    func fileSymbol(at index: Int) -> String {
        if let fileSymbols, fileSymbols.indices.contains(index), !fileSymbols[index].isEmpty {
            return fileSymbols[index]
        }
        guard filePaths.indices.contains(index) else { return "doc" }
        let path = filePaths[index]
        return Self.fileSymbol(pathExtension: (path as NSString).pathExtension, isDirectory: isDirectory(path))
    }

    private static func fileSymbol(pathExtension: String, isDirectory: Bool) -> String {
        if isDirectory { return "folder" }
        switch pathExtension.lowercased() {
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

    func fileSummaryText() -> String {
        if let fileSummary, !fileSummary.isEmpty {
            return fileSummary
        }
        return Self.fileSummary(filePaths: filePaths, flags: isDirectoryFlags ?? [:]) ?? "Multiple items"
    }

    private static func fileSummary(filePaths: [String], flags: [String: Bool]) -> String? {
        guard filePaths.count > 1 else { return nil }
        let counts = fileAndFolderCounts(filePaths: filePaths, flags: flags)
        let folderCount = counts.folderCount
        let fileCount = counts.fileCount

        if folderCount == 0,
           fileCount > 1,
           let typedSummary = fileTypeSummaryForMultipleFiles(filePaths: filePaths) {
            return typedSummary
        }

        if folderCount > 0 && fileCount > 0 {
            return "\(folderCount) folders, \(fileCount) files"
        }
        if folderCount > 0 {
            return folderCount == 1 ? "1 folder" : "\(folderCount) folders"
        }
        return fileCount == 1 ? "1 file" : "\(fileCount) files"
    }

    private static func fileAndFolderCounts(filePaths: [String], flags: [String: Bool]) -> (folderCount: Int, fileCount: Int) {
        var folderCount = 0
        var fileCount = 0
        for path in filePaths {
            if flags[path] == true {
                folderCount += 1
            } else {
                fileCount += 1
            }
        }
        return (folderCount, fileCount)
    }

    private static func symbolForMultipleFiles(filePaths: [String]) -> String {
        var imageCount = 0
        var videoCount = 0
        var otherCount = 0

        for path in filePaths {
            let ext = (path as NSString).pathExtension
            if isImageExtension(ext) {
                imageCount += 1
            } else if isVideoExtension(ext) {
                videoCount += 1
            } else {
                otherCount += 1
            }
        }

        if imageCount > 0, videoCount == 0, otherCount == 0 {
            return "photo.on.rectangle.angled"
        }
        if videoCount > 0, imageCount == 0, otherCount == 0 {
            return "video.badge.checkmark"
        }
        return "doc.on.doc"
    }

    private static func fileTypeSummaryForMultipleFiles(filePaths: [String]) -> String? {
        guard filePaths.count > 1 else { return nil }

        var imageCount = 0
        var videoCount = 0
        var extensionCounts: [String: Int] = [:]

        for path in filePaths {
            let ext = (path as NSString).pathExtension.lowercased()
            if isImageExtension(ext) {
                imageCount += 1
            } else if isVideoExtension(ext) {
                videoCount += 1
            } else {
                let key = ext.isEmpty ? "file" : ext
                extensionCounts[key, default: 0] += 1
            }
        }

        var parts: [String] = []
        if imageCount > 0 {
            parts.append(imageCount == 1 ? "1 image" : "\(imageCount) images")
        }
        if videoCount > 0 {
            parts.append(videoCount == 1 ? "1 video" : "\(videoCount) videos")
        }
        for key in extensionCounts.keys.sorted() {
            let count = extensionCounts[key] ?? 0
            if key == "file" {
                parts.append(count == 1 ? "1 file" : "\(count) files")
            } else {
                parts.append(count == 1 ? "1 \(key) file" : "\(count) \(key) files")
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private static func isImageExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif", "icns":
            return true
        default:
            return false
        }
    }

    private static func isVideoExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "ts", "m2ts":
            return true
        default:
            return false
        }
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
    @Published var observedFileToast: ObservedFileToast?
    @Published var canCloseFromVerticalSwipe = false
    @Published var closeGestureProgress: CGFloat = 0
    @Published var carouselDragOffset: CGFloat = 0
    @Published var isToastDismissing = false
    @Published var chunkedClipboardRows: [[ClipboardEntry]] = []
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
    static let clipboardColumns = "clipboardColumns"
    static let jotColumns = "jotColumns"
    static let boxColumns = "boxColumns"
    static let clipTextSize = "clipTextSize"
    static let clipFileLabelSize = "clipFileLabelSize"
    static let jotTextSize = "jotTextSize"
    static let boxFileNameSize = "boxFileNameSize"
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
    return safeDimension(200 * heightScale, fallback: 200)
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
    private var failedPreviewKeys = Set<String>()
    private let stateLock = NSLock()
    private let prewarmQueue = DispatchQueue(label: "apollo.box.prewarm", qos: .utility)
    private let previewLoadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "apollo.box.preview-load"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let maintenanceQueue = DispatchQueue(label: "apollo.box.maintenance", qos: .utility)
    private var pendingTrimKeepPaths = Set<String>()
    private var pendingTrimWorkItem: DispatchWorkItem?

    private init() {
        iconCache.countLimit = 64
        iconCache.totalCostLimit = 8 * 1024 * 1024
        previewCache.countLimit = 48
        previewCache.totalCostLimit = 16 * 1024 * 1024
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

        stateLock.lock()
        let didPreviouslyFail = failedPreviewKeys.contains(previewKey)
        stateLock.unlock()
        if didPreviouslyFail {
            return icon(for: url)
        }

        if isLikelyImageURL(url),
           let thumbnail = downsampledImage(at: url, maxPixelSize: px) {
            let cost = max(1, px * px * 4)
            previewCache.setObject(thumbnail, forKey: nsKey, cost: cost)
            stateLock.lock()
            knownPreviewKeys.insert(previewKey)
            failedPreviewKeys.remove(previewKey)
            stateLock.unlock()
            return thumbnail
        }

        if isLikelyVideoURL(url),
           let videoThumbnail = videoThumbnailImage(at: url, maxPixelSize: px) {
            let cost = max(1, px * px * 4)
            previewCache.setObject(videoThumbnail, forKey: nsKey, cost: cost)
            stateLock.lock()
            knownPreviewKeys.insert(previewKey)
            failedPreviewKeys.remove(previewKey)
            stateLock.unlock()
            return videoThumbnail
        }

        if isLikelyPreviewableURL(url) {
            stateLock.lock()
            failedPreviewKeys.insert(previewKey)
            stateLock.unlock()
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
        generator.maximumSize = CGSize(width: CGFloat(maxPixelSize), height: CGFloat(maxPixelSize))

        let sampleTime = CMTime(seconds: 0.1, preferredTimescale: 600)
        var generatedImage: CGImage?
        let semaphore = DispatchSemaphore(value: 0)

        generator.generateCGImageAsynchronously(for: sampleTime) { image, _, _ in
            generatedImage = image
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 0.6) == .timedOut {
            generator.cancelAllCGImageGeneration()
            return nil
        }

        guard let cgImage = generatedImage else { return nil }
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
        let failedPreviewKeysSnapshot = failedPreviewKeys
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
        let nextFailedPreviewKeys = Set(failedPreviewKeysSnapshot.filter { key in
            guard let pathEnd = key.firstIndex(of: "|") else { return false }
            let path = String(key[..<pathEnd])
            return keepPaths.contains(path)
        })
        stateLock.lock()
        knownIconKeys = nextIconKeys
        knownPreviewKeys = nextPreviewKeys
        failedPreviewKeys = nextFailedPreviewKeys
        stateLock.unlock()
    }

    func removeAll() {
        iconCache.removeAllObjects()
        previewCache.removeAllObjects()
        stateLock.lock()
        knownIconKeys.removeAll()
        knownPreviewKeys.removeAll()
        failedPreviewKeys.removeAll()
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

    func cachedPreview(for url: URL, targetSize: CGFloat) -> NSImage? {
        let px = max(24, Int(targetSize.rounded()))
        let previewKey = "\(url.path)|\(px)"
        let nsKey = previewKey as NSString
        return previewCache.object(forKey: nsKey)
    }

    func requestDisplayImage(for url: URL, targetSize: CGFloat, completion: @escaping (NSImage) -> Void) {
        let safeTarget = max(24, targetSize)
        let operation = BlockOperation()
        operation.qualityOfService = .utility
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else { return }
            let image = autoreleasepool { self.displayImage(for: url, targetSize: safeTarget) }
            guard !operation.isCancelled else { return }
            OperationQueue.main.addOperation {
                guard !operation.isCancelled else { return }
                completion(image)
            }
        }
        previewLoadQueue.addOperation(operation)
    }

    func cancelQueuedPreviewLoads() {
        previewLoadQueue.cancelAllOperations()
    }

    func schedulePreviewTrim(keepingPaths: Set<String>, debounce: TimeInterval = 0.12) {
        maintenanceQueue.async { [weak self] in
            guard let self else { return }
            self.pendingTrimKeepPaths = keepingPaths
            self.pendingTrimWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let paths = self.pendingTrimKeepPaths
                self.pendingTrimKeepPaths.removeAll()
                self.trimPreviews(keepingPaths: paths)
            }

            self.pendingTrimWorkItem = workItem
            self.maintenanceQueue.asyncAfter(deadline: .now() + max(0, debounce), execute: workItem)
        }
    }

    func cancelScheduledPreviewTrim() {
        maintenanceQueue.async { [weak self] in
            guard let self else { return }
            self.pendingTrimWorkItem?.cancel()
            self.pendingTrimWorkItem = nil
            self.pendingTrimKeepPaths.removeAll()
        }
    }

    func trimPreviews(keepingPaths: Set<String>) {
        stateLock.lock()
        let previewKeysSnapshot = knownPreviewKeys
        let failedPreviewKeysSnapshot = failedPreviewKeys
        stateLock.unlock()

        for key in previewKeysSnapshot {
            guard let pathEnd = key.firstIndex(of: "|") else { continue }
            let path = String(key[..<pathEnd])
            if !keepingPaths.contains(path) {
                previewCache.removeObject(forKey: key as NSString)
            }
        }

        let nextPreviewKeys = Set(previewKeysSnapshot.filter { key in
            guard let pathEnd = key.firstIndex(of: "|") else { return false }
            let path = String(key[..<pathEnd])
            return keepingPaths.contains(path)
        })
        let nextFailedPreviewKeys = Set(failedPreviewKeysSnapshot.filter { key in
            guard let pathEnd = key.firstIndex(of: "|") else { return false }
            let path = String(key[..<pathEnd])
            return keepingPaths.contains(path)
        })
        stateLock.lock()
        knownPreviewKeys = nextPreviewKeys
        failedPreviewKeys = nextFailedPreviewKeys
        stateLock.unlock()
    }

    func shouldAttemptPreview(for url: URL) -> Bool {
        isLikelyPreviewableURL(url)
    }

    func shouldAttemptStillImagePreview(for url: URL) -> Bool {
        isLikelyImageURL(url)
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

    let notchWidthRange: ClosedRange<CGFloat> = 205...600
    let notchHeightRange: ClosedRange<CGFloat> = 20...120
    let rememberClipsRange: ClosedRange<Double> = 1...200
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
            let clampedValue = clamp(defaultPage, min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
            if clampedValue != defaultPage {
                defaultPage = clampedValue
            }
            enqueueDefaultSet(defaultPage, forKey: AppStorageKey.defaultPage)
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
            let clampedValue = clamp(lastVisitedPage, min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
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
        case .jot:
            return TitleAlignmentOption(rawValue: jotTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
        case .box:
            return TitleAlignmentOption(rawValue: boxTitleAlignment ?? titleAlignment) ?? titleAlignmentOption
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
        case .jot:
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
        case .jot:
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
                        let label: String = {
                            switch page {
                            case .clipboard: return "Clip"
                            case .jot: return "Jot"
                            case .box: return "Box"
                            }
                        }()
                        Text(label)
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

                HStack {
                    Text("Clip columns")
                    Slider(
                        value: Binding(
                            get: { Double(settings.clipboardColumns) },
                            set: { settings.clipboardColumns = Int($0.rounded()) }
                        ),
                        in: settings.clipboardColumnsRange
                    )
                    Text("\(settings.clipboardColumns)")
                        .frame(width: 32, alignment: .trailing)
                }

                HStack {
                    Text("Jot columns")
                    Slider(
                        value: Binding(
                            get: { Double(settings.jotColumns) },
                            set: { settings.jotColumns = Int($0.rounded()) }
                        ),
                        in: settings.jotColumnsRange
                    )
                    Text("\(settings.jotColumns)")
                        .frame(width: 32, alignment: .trailing)
                }

                HStack {
                    Text("Box columns")
                    Slider(
                        value: Binding(
                            get: { Double(settings.boxColumns) },
                            set: { settings.boxColumns = Int($0.rounded()) }
                        ),
                        in: settings.boxColumnsRange
                    )
                    Text("\(settings.boxColumns)")
                        .frame(width: 32, alignment: .trailing)
                }

                HStack {
                    Text("Clip text size")
                    Slider(value: $settings.clipTextSize, in: settings.clipTextSizeRange)
                    Text("\(Int(settings.clipTextSize))")
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("Clip file label size")
                    Slider(value: $settings.clipFileLabelSize, in: settings.clipFileLabelSizeRange)
                    Text("\(Int(settings.clipFileLabelSize))")
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("Jot text size")
                    Slider(value: $settings.jotTextSize, in: settings.jotTextSizeRange)
                    Text("\(Int(settings.jotTextSize))")
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("Box file name size")
                    Slider(value: $settings.boxFileNameSize, in: settings.boxFileNameSizeRange)
                    Text("\(Int(settings.boxFileNameSize))")
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
        case .jot: return "Jot"
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
                case .jot:
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
                case .jot:
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
                case .jot:
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
                case .jot:
                    return settings.jotTitleUseAccent ?? false
                case .box:
                    return settings.boxTitleUseAccent ?? false
                }
            },
            set: { newValue in
                switch page {
                case .clipboard:
                    settings.clipboardTitleUseAccent = newValue
                case .jot:
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
                case .jot:
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
                case .jot:
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
        case .jot:
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
        return entries.map { $0.normalizedForLightweightStorage() }
    }
    let savedTexts = defaults.stringArray(forKey: AppStorageKey.clipboardHistory) ?? []
    return savedTexts.map { ClipboardEntry(text: $0) }
}

private final class PersistenceWriteCoordinator {
    static let shared = PersistenceWriteCoordinator()

    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "apollo.persistence.coalesced-writes", qos: .utility)
    private let flushDelay: TimeInterval = 0.35

    private var pendingClipboardEntries: [ClipboardEntry]?
    private var pendingJotNotes: [JotNote]?
    private var flushWorkItem: DispatchWorkItem?

    private init() {}

    func scheduleClipboardHistory(_ entries: [ClipboardEntry]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingClipboardEntries = entries
            self.scheduleFlushLocked()
        }
    }

    func scheduleJotNotes(_ notes: [JotNote]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingJotNotes = notes
            self.scheduleFlushLocked()
        }
    }

    func flushNow() {
        queue.sync {
            flushLocked()
        }
    }

    private func scheduleFlushLocked() {
        flushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushLocked()
        }
        flushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + flushDelay, execute: workItem)
    }

    private func flushLocked() {
        flushWorkItem?.cancel()
        flushWorkItem = nil

        if let entries = pendingClipboardEntries,
           let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: AppStorageKey.clipboardHistory)
        }
        pendingClipboardEntries = nil

        if let notes = pendingJotNotes,
           let data = try? JSONEncoder().encode(notes) {
            defaults.set(data, forKey: AppStorageKey.jotNotes)
        }
        pendingJotNotes = nil
    }
}

private extension View {
    func nativeSettingsFormStyle() -> some View {
        formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
    }
}

private func persistClipboardHistory(_ entries: [ClipboardEntry]) {
    PersistenceWriteCoordinator.shared.scheduleClipboardHistory(entries.map { $0.normalizedForLightweightStorage() })
}

private func loadJotNotes() -> [JotNote] {
    guard let data = UserDefaults.standard.data(forKey: AppStorageKey.jotNotes),
          let notes = try? JSONDecoder().decode([JotNote].self, from: data) else {
        return []
    }
    return notes
}

private func persistJotNotes(_ notes: [JotNote]) {
    PersistenceWriteCoordinator.shared.scheduleJotNotes(notes)
}

// MARK: - Global Coordinate Proximity Driver
private final class SingleInstanceLock {
    private var fileDescriptor: Int32 = -1

    func acquire(bundleIdentifier: String) -> Bool {
        guard fileDescriptor == -1 else { return true }
        let lockPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("\(bundleIdentifier).instance.lock")
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return true }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            fileDescriptor = descriptor
            return true
        }
        close(descriptor)
        return false
    }

    deinit {
        guard fileDescriptor >= 0 else { return }
        close(fileDescriptor)
        fileDescriptor = -1
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var islandWindow: IslandPanel!
    var notchWindow: IslandPanel! { islandWindow }
    private var clipboardTimer: DispatchSourceTimer?
    private var clipboardActivationObserver: NSObjectProtocol?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var idleCompactionWorkItem: DispatchWorkItem?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private let model = NotchMenuModel()
    private let settings = AppSettings.shared
    private var settingsCancellables = Set<AnyCancellable>()
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var swipeCloseWorkItem: DispatchWorkItem?

    private var notchPreviewWorkItem: DispatchWorkItem?
    private var lastCloseProgressEmission: CGFloat = 0
    private var lastCarouselOffsetEmission: CGFloat = 0
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private var lastWorkspaceClipboardPollTime: TimeInterval = 0
    private var lastImmediateClipboardPollTime: TimeInterval = 0
    private let clipboardQueue = DispatchQueue(label: "apollo.clipboard.poll", qos: .utility)
    private var folderMonitors: [String: FolderMonitor] = [:]
    private var folderSnapshots: [String: Set<String>] = [:]
    private var suppressProximityUntilExit = false
    private var isCursorInActivationZone = false
    private var pendingWindowHeightUpdate: CGFloat?
    private var windowFrameUpdateWorkItem: DispatchWorkItem?
    private let singleInstanceLock = SingleInstanceLock()

    // Event-driven proximity tracking
    private var proximityWakeWindow: ProximityWakeWindow?   // notch-edge / approach (open trigger)
    private var islandOpenMousePollTimer: DispatchSourceTimer?
    private var approachWorkItem: DispatchWorkItem?
    private var isDraggingOverProximity = false
    private var lastApproachProgressSampleTime: TimeInterval = 0
    private var lastApproachProgressEmitted: CGFloat = -1
    private var lastPanelExpandedAt: TimeInterval = 0
    private var panelVisibilityEpoch: UInt64 = 0

    // Dynamic structural dimensions
    private var notchWidth: CGFloat = 210
    private var notchHeight: CGFloat = 32
    private var panelWidth: CGFloat = 380
    private var panelHeight: CGFloat = 160

    // Proximity variables
    private let activationYBuffer: CGFloat = 80
    private let exactTriggerPadding: CGFloat = 20
    private let approachProgressUpdateInterval: TimeInterval = 1.0 / 30.0
    private let approachProgressDeltaThreshold: CGFloat = 0.02
    private let idleCompactionDelay: TimeInterval = 4.0
    private let clipboardActivePollingInterval: TimeInterval = 3.0
    private let clipboardWorkspaceActivationPollDebounce: TimeInterval = 0.7
    private let clipboardImmediatePollDebounce: TimeInterval = 0.25

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }

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
        refreshChunkedClipboard()
        normalizeClipboardDirectoryFlagsIfNeeded()
        applyClipboardLimitIfNeeded()
        persistClipboardHistory(model.clipboardItems)
        persistJotNotes(model.jotNotes)
        refreshNativeState()
    }

    private func acquireSingleInstanceLock() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        return singleInstanceLock.acquire(bundleIdentifier: bundleIdentifier)
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let runningInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) else {
            return
        }
        runningInstance.activate(options: [])
    }

    func refreshChunkedClipboard() {
        let items = model.clipboardItems
        let columns = max(1, settings.clipboardColumns)
        clipboardQueue.async { [weak self] in
            var chunked: [[ClipboardEntry]] = []
            for i in stride(from: 0, to: items.count, by: columns) {
                let end = min(i + columns, items.count)
                chunked.append(Array(items[i..<end]))
            }
            DispatchQueue.main.async {
                self?.model.chunkedClipboardRows = chunked
            }
        }
    }

    private func normalizeClipboardDirectoryFlagsIfNeeded() {
        let entries = model.clipboardItems
        guard entries.contains(where: { entry in
            entry.text != nil && !entry.filePaths.isEmpty
            || entry.fileNames?.count != entry.filePaths.count
            || entry.fileSymbols?.count != entry.filePaths.count
            || entry.isDirectoryFlags == nil && !entry.filePaths.isEmpty
        }) else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let normalizedEntries = entries.map { entry -> ClipboardEntry in
                var updated = entry
                if updated.isDirectoryFlags == nil, !updated.filePaths.isEmpty {
                    var flags: [String: Bool] = [:]
                    for path in entry.filePaths {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                            flags[path] = isDir.boolValue
                        } else {
                            flags[path] = false
                        }
                    }
                    updated.isDirectoryFlags = flags
                }
                return updated.normalizedForLightweightStorage()
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.model.clipboardItems.map(\.id) == entries.map(\.id) else { return }
                self.model.clipboardItems = normalizedEntries
                persistClipboardHistory(normalizedEntries)
                self.refreshChunkedClipboard()
            }
        }
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
                self.updateProximityWakeWindowFrame()
                self.previewNotchResize()
            }
            .store(in: &settingsCancellables)

        Publishers.MergeMany(
            settings.$disableApproach.map { _ in () }.eraseToAnyPublisher(),
            settings.$alwaysUseApproachWhenDraggingFile.map { _ in () }.eraseToAnyPublisher(),
            settings.$approachWidth.map { _ in () }.eraseToAnyPublisher(),
            settings.$approachHeight.map { _ in () }.eraseToAnyPublisher(),
            settings.$notchEdgeThickness.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            self?.updateProximityWakeWindowFrame()
        }
        .store(in: &settingsCancellables)

        settings.$rememberClips
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyClipboardLimitIfNeeded()
                persistClipboardHistory(self.model.clipboardItems)
                self.refreshChunkedClipboard()
            }
            .store(in: &settingsCancellables)

        settings.$clipboardColumns
            .sink { [weak self] _ in
                self?.refreshChunkedClipboard()
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
                self.updateClipboardObservationMode(immediatePoll: focus != .all)
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
        model.isExpanded = false
        model.isPinned = false
        model.expansionProgress = 0.0
        model.closeGestureProgress = 0
        model.carouselDragOffset = 0
        updateNotchWindowFrame(heightOverride: panelHeight)
        window.alphaValue = 1.0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        updateClipboardObservationMode(immediatePoll: true)
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

    private let scrollBottomTolerance: CGFloat = 24

    func isCurrentPageAtBottom() -> Bool {
        guard model.isExpanded, !model.isPinned else { return false }
        guard let window = islandWindow else { return true }
        guard let scrollView = window.contentView?.findScrollView() else {
            // If there's no scroll view, it's always ready to close.
            return true
        }
        guard let documentView = scrollView.documentView else { return true }
        let visibleRect = scrollView.documentVisibleRect
        let contentHeight = documentView.frame.height
        let viewportHeight = visibleRect.height

        // If content is shorter than the viewport, it's always at the bottom!
        if contentHeight <= viewportHeight { return true }

        return visibleRect.maxY >= (contentHeight - scrollBottomTolerance)
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
            self?.isCurrentPageAtBottom() ?? false
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
            if abs(self.lastCloseProgressEmission - clamped) < 0.02 {
                return
            }
            self.lastCloseProgressEmission = clamped
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
            if abs(self.lastCarouselOffsetEmission - offset) < (animate ? 0.01 : 0.6) {
                return
            }
            self.lastCarouselOffsetEmission = offset
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
                self.scheduleWindowFrameUpdate(for: newHeight)
            }

        notchWindow.contentView = IslandHostingView(rootView: rootHubView)
        // Don't order front at startup — window will be ordered front on first show.
        // Keeping it ordered out eliminates all NSTrackingArea and SwiftUI hover
        // events while the panel is idle, preventing CPU usage from cursor movement.
    }

    private func advancePage(direction: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let next = clamp(self.model.currentPage + direction, min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
            self.model.carouselDragOffset = 0
            withAnimation(self.settings.carouselAnimation) {
                self.model.currentPage = next
            }
        }
    }

    private func startBackgroundStateTracking() {
        startClipboardObservation()
    }

    private func startClipboardObservation() {
        observeWorkspaceActivationForClipboardIfNeeded()
        updateClipboardObservationMode(immediatePoll: true)
    }

    private func shouldKeepClipboardTimerRunning() -> Bool {
        (model.isExpanded || model.isPinned) && model.currentPage == IslandPage.clipboard.rawValue
    }

    private func updateClipboardObservationMode(immediatePoll: Bool = false) {
        let shouldPollActively = shouldKeepClipboardTimerRunning()
        if shouldPollActively {
            startClipboardPollingTimerIfNeeded()
        } else {
            stopClipboardObservation()
        }
        if immediatePoll, shouldPollActively {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastImmediateClipboardPollTime >= clipboardImmediatePollDebounce else {
                return
            }
            lastImmediateClipboardPollTime = now
            // Avoid forced payload reads on page transitions: a normal poll first
            // checks pasteboard changeCount and only decodes payload when changed.
            pollClipboard()
        }
    }

    private func startClipboardPollingTimerIfNeeded() {
        guard clipboardTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: clipboardQueue)
        timer.schedule(
            deadline: .now() + 1.2,
            repeating: clipboardActivePollingInterval,
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.pollClipboard()
        }
        timer.resume()
        clipboardTimer = timer
    }

    private func stopClipboardObservation() {
        clipboardTimer?.cancel()
        clipboardTimer = nil
    }

    private func observeWorkspaceActivationForClipboardIfNeeded() {
        guard clipboardActivationObserver == nil else { return }
        clipboardActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWorkspaceActivationForClipboard()
        }
    }

    private func handleWorkspaceActivationForClipboard() {
        guard !shouldKeepClipboardTimerRunning() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastWorkspaceClipboardPollTime >= clipboardWorkspaceActivationPollDebounce else {
            return
        }
        lastWorkspaceClipboardPollTime = now
        pollClipboard()
    }

    func updateObservationState(for page: Int) {
        updateClipboardObservationMode(immediatePoll: page == IslandPage.clipboard.rawValue)
    }

    private func refreshNativeState() {
        pollClipboard(force: true)
    }

    private func pollClipboard(force: Bool = false) {
        if Thread.isMainThread {
            pollClipboardFromPasteboard(force: force)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.pollClipboardFromPasteboard(force: force)
            }
        }
    }

    private func pollClipboardFromPasteboard(force: Bool = false) {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard force || currentChangeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentChangeCount

        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? [])
        .filter(\.isFileURL)

        let trimmedText: String?
        if fileURLs.isEmpty {
            trimmedText = cappedClipboardText(pasteboard.string(forType: .string))
        } else {
            trimmedText = nil
        }

        guard (trimmedText?.isEmpty == false) || !fileURLs.isEmpty else { return }

        clipboardQueue.async { [weak self] in
            let entry = ClipboardEntry(text: trimmedText, fileURLs: fileURLs).normalizedForLightweightStorage()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.model.clipboardItems.first?.signature != entry.signature else { return }

                self.model.clipboardItems.removeAll { $0.signature == entry.signature }
                self.model.clipboardItems.insert(entry, at: 0)
                self.applyClipboardLimitIfNeeded()
                persistClipboardHistory(self.model.clipboardItems)
                self.refreshChunkedClipboard()
            }
        }
    }

    func copyClipboardEntry(_ entry: ClipboardEntry) {
        let entry = entry.normalizedForLightweightStorage()
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
        refreshChunkedClipboard()
    }

    func clearClipboardHistory() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        lastClipboardChangeCount = pasteboard.changeCount
        model.clipboardItems.removeAll()
        model.chunkedClipboardRows.removeAll()
        model.clipboardPulseItemID = nil
        persistClipboardHistory(model.clipboardItems)
        refreshChunkedClipboard()
    }

    private func applyClipboardLimitIfNeeded() {
        guard let limit = settings.effectiveRememberClips else { return }
        if model.clipboardItems.count > limit {
            model.clipboardItems = Array(model.clipboardItems.prefix(limit))
            refreshChunkedClipboard()
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

    private func startGlobalProximityTracking() {
        setupProximityWakeWindow()
        updateProximityWakeWindowFrame()
    }

    private func setupProximityWakeWindow() {
        guard proximityWakeWindow == nil else { return }
        let wake = ProximityWakeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        wake.isOpaque = false
        wake.backgroundColor = .clear
        wake.hasShadow = false
        wake.level = .statusBar + 1
        wake.alphaValue = 0.001
        wake.ignoresMouseEvents = false
        wake.acceptsMouseMovedEvents = true
        wake.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        wake.hidesOnDeactivate = false
        wake.onMouseEntered = { [weak self] in self?.handleProximityWakeEntered() }
        wake.onMouseExited = { [weak self] in self?.handleProximityWakeExited() }
        wake.onApproachMouseMoved = { [weak self] pt in self?.handleProximityApproachMouseMoved(to: pt) }
        wake.onDraggingEntered = { [weak self] in self?.handleProximityDraggingEntered() }
        wake.onDraggingUpdated = { [weak self] pt in self?.handleProximityDraggingUpdated(to: pt) }
        wake.onDraggingExited = { [weak self] in self?.handleProximityDraggingExited() }
        wake.orderFrontRegardless()
        proximityWakeWindow = wake

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenParametersChanged() {
        calculateScreenNotchDimensions()
        updateNotchWindowFrame()
        updateProximityWakeWindowFrame()
    }

    private func updateProximityWakeWindowFrame() {
        guard let wake = proximityWakeWindow,
              let screen = NSScreen.screens.first else { return }
        let screenRect = screen.frame

        // proximityWakeWindow tracks notch edge + approach zone while island is closed.
        let shouldWakeTrackCursor =
            !model.isExpanded &&
            !model.isPinned &&
            model.observedFileToast == nil &&
            !(settings.showHoverPreviews && settings.hoverPreviewFocus != .all)
        guard shouldWakeTrackCursor else {
            resetApproachProgressSampling()
            wake.orderOut(nil)
            return
        }
        // Cursor is approaching the notch; reset the suppression flag so hover-to-open works.
        suppressProximityUntilExit = false
        let edge = settings.clampedNotchEdgeThickness
        let edgeNotchWidth = settings.effectiveNotchWidth
        let edgeNotchHeight = settings.effectiveNotchHeight
        let edgeNotchLeft = settings.hardwareNotchX
        let edgeNotchRect = CGRect(
            x: edgeNotchLeft,
            y: screenRect.maxY - edgeNotchHeight,
            width: edgeNotchWidth,
            height: edgeNotchHeight
        ).insetBy(dx: -edge, dy: -edge)

        let approachScale: CGFloat = settings.alwaysUseApproachWhenDraggingFile ? 2.0 : 1.0
        let approachWidth = settings.disableApproach ? 0 : settings.clampedApproachWidth * approachScale
        let approachHeight = settings.disableApproach ? 0 : settings.clampedApproachHeight * approachScale

        let cushion: CGFloat = 6
        let totalHeight = edgeNotchRect.height + approachHeight + cushion
        let totalWidth = edgeNotchRect.width + approachWidth * 2
        let originX = edgeNotchRect.minX - approachWidth
        let originY = screenRect.maxY - totalHeight
        let approachRect = CGRect(
            x: edgeNotchRect.minX - approachWidth,
            y: edgeNotchRect.minY - approachHeight,
            width: edgeNotchRect.width + (approachWidth * 2),
            height: approachHeight
        )

        wake.setFrame(NSRect(x: originX, y: originY, width: totalWidth, height: totalHeight), display: false)
        if !wake.isVisible {
            wake.orderFrontRegardless()
        }
        wake.updateTrackingGeometry(
            notchEdgeRect: edgeNotchRect.offsetBy(dx: -originX, dy: -originY),
            approachRect: approachRect.offsetBy(dx: -originX, dy: -originY)
        )

        // If tracking geometry moves under a stationary cursor, AppKit may not
        // emit mouseEntered. Synthesize an activation check so notch-edge hover
        // reliably opens the island.
        let cursor = NSEvent.mouseLocation
        if edgeNotchRect.contains(cursor) {
            setActivationZoneState(true)
            evaluateMouseCoordinates(cursor, isFileDrag: false)
        }
    }

    private func handleProximityWakeEntered() {
        guard !suppressProximityUntilExit else { return }
        // Only the notch-edge/notch itself should count as activation.
        // Entering approach alone should progressively expand, not open.
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first {
            let zones = makeProximityZones(screenRect: screen.frame, point: point, isFileDrag: false)
            setActivationZoneState(zones.isInsideNotch || zones.isHoveringEdge)
        } else {
            setActivationZoneState(false)
        }
        // Evaluate cursor when tracking areas are entered so approach progress
        // updates immediately, but open only occurs at notch-edge/notch.
        evaluateMouseCoordinates(point, isFileDrag: false)
    }

    private func handleProximityWakeExited() {
        suppressProximityUntilExit = false
        resetApproachProgressSampling()
        setActivationZoneState(false)
    }

    private func handleProximityApproachMouseMoved(to point: NSPoint) {
        guard !suppressProximityUntilExit, !model.isExpanded, !model.isPinned else { return }
        evaluateMouseCoordinates(point, isFileDrag: false)
    }

    private func setActivationZoneState(_ isInside: Bool) {
        guard isCursorInActivationZone != isInside else { return }
        isCursorInActivationZone = isInside
        applyCursorPresenceState()
    }

    private func applyCursorPresenceState() {
        guard !model.isPinned else {
            hoverCloseWorkItem?.cancel()
            hoverCloseWorkItem = nil
            return
        }

        if model.isExpanded {
            hoverCloseWorkItem?.cancel()
            hoverCloseWorkItem = nil
            return
        }

        guard isCursorInActivationZone, !suppressProximityUntilExit else { return }
        showPanel(expanded: true, pinned: false)
    }

    private func clearCursorPresenceState() {
        isCursorInActivationZone = false
    }

    private func handleLegacyProximityWakeExitedFallback() {
        approachWorkItem?.cancel()
        approachWorkItem = nil
        let globalPoint = NSEvent.mouseLocation
        let isWithinExpandedPanel = notchWindow?.frame.contains(globalPoint) ?? false
        if model.isExpanded {
            if !isWithinExpandedPanel {
                scheduleHoverCloseIfNeeded()
            }
        } else if !model.isPinned && model.expansionProgress > 0 {
            withAnimation(settings.notchOpenAnimation) {
                model.expansionProgress = 0
            }
            let checkWindow = notchWindow
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, !self.model.isExpanded, self.model.expansionProgress == 0 else { return }
                checkWindow?.alphaValue = 0.0
                checkWindow?.ignoresMouseEvents = true
                checkWindow?.orderOut(nil)
            }
        }
    }

    private func handleProximityDraggingEntered() {
        isDraggingOverProximity = true
        suppressProximityUntilExit = false
        evaluateMouseCoordinates(NSEvent.mouseLocation, isFileDrag: true)
    }

    private func handleProximityDraggingUpdated(to point: NSPoint) {
        evaluateMouseCoordinates(point, isFileDrag: true)
    }

    private func handleProximityDraggingExited() {
        isDraggingOverProximity = false
        handleLegacyProximityWakeExitedFallback()
    }

    private struct ProximityZones {
        let notchRect: CGRect
        let notchEdgeRect: CGRect
        let approachRect: CGRect
        let isHoveringEdge: Bool
        let isInsideNotch: Bool
    }

    private func makeProximityZones(screenRect: CGRect, point: NSPoint, isFileDrag: Bool) -> ProximityZones {
        let edge = settings.clampedNotchEdgeThickness
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
            // Use global screen-space Y (maxY), not local height, to keep
            // inside-notch detection correct on all display origins.
            y: screenRect.maxY - edgeNotchHeight,
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
        let isInsideNotch = notchRect.contains(point)
        let isHoveringEdge = isPointInNotchEdge(point, notchRect: notchRect, edge: edge)

        return ProximityZones(
            notchRect: notchRect,
            notchEdgeRect: notchEdgeRect,
            approachRect: approachRect,
            isHoveringEdge: isHoveringEdge,
            isInsideNotch: isInsideNotch
        )
    }

    private func isPointInNotchEdge(_ point: NSPoint, notchRect: CGRect, edge: CGFloat) -> Bool {
        if notchRect.contains(point) {
            return true
        }
        let thickness = max(0, edge)
        guard thickness > 0 else { return false }
        let hitThickness = max(6, thickness)
        let outerRect = notchRect.insetBy(dx: -hitThickness, dy: -hitThickness)
        return outerRect.contains(point)
    }

    private func scheduleHoverCloseIfNeeded() {
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
        hidePanel()
    }

    private func startIslandOpenMousePolling() {
        guard islandOpenMousePollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(400), repeating: .milliseconds(400), leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            self?.handleIslandOpenMousePollTick()
        }
        islandOpenMousePollTimer = timer
        timer.resume()
    }

    private func stopIslandOpenMousePolling() {
        islandOpenMousePollTimer?.cancel()
        islandOpenMousePollTimer = nil
    }

    private func handleIslandOpenMousePollTick() {
        guard model.isExpanded, !model.isPinned, let window = islandWindow else {
            stopIslandOpenMousePolling()
            return
        }
        let point = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        // Give the panel a brief settling window so fast notch-entry doesn't
        // get interpreted as an immediate leave before geometry catches up.
        if now - lastPanelExpandedAt < 0.45 {
            return
        }

        if window.frame.contains(point) || isPointInsideNotchActivationZone(point) {
            return
        }
        hidePanel()
    }

    private func isPointInsideNotchActivationZone(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let zones = makeProximityZones(screenRect: screen.frame, point: point, isFileDrag: false)
        return zones.isInsideNotch || zones.isHoveringEdge
    }

    private func resetApproachProgressSampling() {
        lastApproachProgressSampleTime = 0
        lastApproachProgressEmitted = -1
    }

    private func applyApproachProgressIfNeeded(_ targetProgress: CGFloat) {
        let clamped = min(1.0, max(0.0, targetProgress))
        let now = ProcessInfo.processInfo.systemUptime

        if lastApproachProgressEmitted < 0 {
            lastApproachProgressEmitted = clamped
            lastApproachProgressSampleTime = now
            if abs(model.expansionProgress - clamped) > 0.005 {
                model.expansionProgress = clamped
            }
            return
        }

        let delta = abs(clamped - lastApproachProgressEmitted)
        let elapsed = now - lastApproachProgressSampleTime
        let isLargeStep = delta >= 0.08
        guard isLargeStep || (delta >= approachProgressDeltaThreshold && elapsed >= approachProgressUpdateInterval) else {
            return
        }

        lastApproachProgressEmitted = clamped
        lastApproachProgressSampleTime = now
        if abs(model.expansionProgress - clamped) > 0.005 {
            model.expansionProgress = clamped
        }
    }

    private func evaluateMouseCoordinates(_ globalPoint: NSPoint, isFileDrag: Bool) {
        guard let screen = NSScreen.screens.first else { return }
        let screenRect = screen.frame
        let zones = makeProximityZones(screenRect: screenRect, point: globalPoint, isFileDrag: isFileDrag)
        let isInsideActiveZone = zones.isInsideNotch || zones.isHoveringEdge || zones.approachRect.contains(globalPoint)

        if isInsideActiveZone {
            hoverCloseWorkItem?.cancel()
            hoverCloseWorkItem = nil
        }

        if model.isPinned {
            showPanel(expanded: true, pinned: true)
            return
        }

        if model.isExpanded {
            let isWithinExpandedPanel = notchWindow?.frame.contains(globalPoint) ?? false
            if isWithinExpandedPanel || zones.isInsideNotch || zones.isHoveringEdge {
                hoverCloseWorkItem?.cancel()
                hoverCloseWorkItem = nil
            } else {
                scheduleHoverCloseIfNeeded()
            }
            return
        }

        let isDirectHoverOverNotch = zones.isInsideNotch || zones.isHoveringEdge
        let forceApproachForDrag = isFileDrag && settings.alwaysUseApproachWhenDraggingFile
        let disableApproachForCurrentInput = settings.disableApproach && !forceApproachForDrag

        if disableApproachForCurrentInput {
            if isDirectHoverOverNotch {
                let preferredPage = isFileDrag ? IslandPage.box.rawValue : nil
                showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
            } else {
                hidePanel()
            }
            return
        }

        if isInsideActiveZone {
            let totalHeight = max(1.0, zones.approachRect.height)
            let distance = max(0.0, zones.notchEdgeRect.minY - globalPoint.y)
            let baseProgress = min(1.0, max(0.0, 1.0 - (distance / totalHeight)))
            let targetProgress = zones.isHoveringEdge ? 1.0 : baseProgress

            applyApproachProgressIfNeeded(targetProgress)
            if notchWindow?.alphaValue != 1.0 {
                notchWindow?.alphaValue = 1.0
            }
            if notchWindow?.isVisible == false {
                notchWindow?.orderFrontRegardless()
            }
            let shouldIgnoreMouseEvents = !(isFileDrag && zones.approachRect.contains(globalPoint))
            if notchWindow?.ignoresMouseEvents != shouldIgnoreMouseEvents {
                notchWindow?.ignoresMouseEvents = shouldIgnoreMouseEvents
            }

            if isDirectHoverOverNotch {
                approachWorkItem?.cancel()
                approachWorkItem = nil
                resetApproachProgressSampling()
                let preferredPage = isFileDrag ? IslandPage.box.rawValue : nil
                showPanel(expanded: true, pinned: false, preferredPage: preferredPage)
            } else {
                approachWorkItem?.cancel()
                approachWorkItem = nil
            }
        } else {
            approachWorkItem?.cancel()
            approachWorkItem = nil
            resetApproachProgressSampling()
            hidePanel()
        }
    }

    private func showPanel(expanded: Bool, pinned: Bool, preferredPage: Int? = nil) {
        guard let window = islandWindow else { return }

        if expanded {
            panelVisibilityEpoch &+= 1
        }

        let resolvedPage: Int?
        if let preferredPage {
            resolvedPage = preferredPage
        } else if expanded {
            if settings.reopenLastPage {
                resolvedPage = settings.lastVisitedPage
            } else if settings.defaultToBoxIfItems, !model.boxFiles.isEmpty {
                resolvedPage = IslandPage.box.rawValue
            } else {
                resolvedPage = settings.defaultPage
            }
        } else {
            resolvedPage = nil
        }

        let stateMatches = model.isExpanded == expanded && model.isPinned == pinned
        let pageMatches = resolvedPage == nil || model.currentPage == resolvedPage
        if stateMatches,
           pageMatches,
           abs(model.expansionProgress - 1.0) < 0.001,
           abs(model.closeGestureProgress) < 0.001,
           abs(model.carouselDragOffset) < 0.001 {
            if window.alphaValue != 1.0 {
                window.alphaValue = 1.0
            }
            if window.ignoresMouseEvents {
                window.ignoresMouseEvents = false
            }
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            updateClipboardObservationMode(immediatePoll: true)
            updateProximityWakeWindowFrame()
            if expanded {
                startIslandOpenMousePolling()
            } else {
                stopIslandOpenMousePolling()
            }
            return
        }

        cancelIdleCompaction()
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        hoverCloseWorkItem?.cancel()
        hoverCloseWorkItem = nil
        swipeCloseWorkItem?.cancel()
        swipeCloseWorkItem = nil

        let wasExpanded = model.isExpanded
        let shouldAnimateOpen = expanded && (!wasExpanded || model.expansionProgress < 0.999 || model.closeGestureProgress > 0.001)
        if model.isExpanded != expanded {
            model.isExpanded = expanded
        }
        if model.isPinned != pinned {
            model.isPinned = pinned
        }

        if shouldAnimateOpen {
            withAnimation(settings.notchOpenAnimation) {
                model.expansionProgress = 1.0
                model.closeGestureProgress = 0
                model.carouselDragOffset = 0
            }
        } else {
            if abs(model.expansionProgress - 1.0) > 0.001 {
                model.expansionProgress = 1.0
            }
            if abs(model.closeGestureProgress) > 0.001 {
                model.closeGestureProgress = 0
            }
            if abs(model.carouselDragOffset) > 0.001 {
                model.carouselDragOffset = 0
            }
        }
        lastCloseProgressEmission = 0
        lastCarouselOffsetEmission = 0
        if let resolvedPage, model.currentPage != resolvedPage {
            model.currentPage = resolvedPage
        }
        if window.alphaValue != 1.0 {
            window.alphaValue = 1.0
        }
        if window.ignoresMouseEvents {
            window.ignoresMouseEvents = false
        }
        if !window.isVisible {
            window.orderFrontRegardless()
        }
        if expanded {
            lastPanelExpandedAt = ProcessInfo.processInfo.systemUptime
        }
        isCursorInActivationZone = window.frame.contains(NSEvent.mouseLocation)
        updateClipboardObservationMode(immediatePoll: true)
        updateProximityWakeWindowFrame()
        if expanded {
            startIslandOpenMousePolling()
        } else {
            stopIslandOpenMousePolling()
        }
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
        stopIslandOpenMousePolling()
        // Match open exactly: use the same notch spring for collapse.
        // Keep the window visible long enough for the spring to settle.
        withAnimation(settings.notchOpenAnimation) {
            model.isExpanded = false
            model.expansionProgress = 0.0
            if !preserveCloseProgress {
                model.closeGestureProgress = 0
            }
            model.carouselDragOffset = 0
        }
        // Reactivate notch/approach tracking immediately on close start so
        // quick re-entry can reopen without waiting for final orderOut.
        updateProximityWakeWindowFrame()
        lastCloseProgressEmission = 0
        lastCarouselOffsetEmission = 0

        panelVisibilityEpoch &+= 1
        let hideEpoch = panelVisibilityEpoch

        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isPinned else { return }
            guard self.panelVisibilityEpoch == hideEpoch else { return }
            window.alphaValue = 0.0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            self.clearCursorPresenceState()
            self.model.expansionProgress = 0
            self.scheduleIdleCompactionIfNeeded()
            self.updateClipboardObservationMode()
            self.updateProximityWakeWindowFrame()
        }
        scheduleHideAfterCollapse(
            window: window,
            hideWorkItem: hideWorkItem,
            startedAt: ProcessInfo.processInfo.systemUptime,
            hideEpoch: hideEpoch
        )
    }

    private func scheduleHideAfterCollapse(window: NSWindow, hideWorkItem: DispatchWorkItem, startedAt: TimeInterval, hideEpoch: UInt64) {
        let pollWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.panelVisibilityEpoch == hideEpoch else { return }
            guard !self.model.isPinned else { return }
            guard !self.model.isExpanded else { return }

            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            // Frame updates are quantized to rounded points in
            // `scheduleWindowFrameUpdate`, so compare against the same final value.
            let targetNotchHeight = self.settings.effectiveNotchHeight.rounded()
            let currentHeight = window.frame.height
            let hasCollapsedToNotch = abs(currentHeight - targetNotchHeight) <= 0.01

            // Require a small minimum visible duration so close remains
            // perceptible even when frame updates arrive quickly.
            if hasCollapsedToNotch && elapsed >= 0.10 {
                hideWorkItem.perform()
                return
            }

            if elapsed >= 1.2 {
                // Safety net: force an exact final-notch frame before hiding.
                self.updateNotchWindowFrame(heightOverride: targetNotchHeight)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    guard self.panelVisibilityEpoch == hideEpoch else { return }
                    hideWorkItem.perform()
                }
                return
            }

            self.scheduleHideAfterCollapse(window: window, hideWorkItem: hideWorkItem, startedAt: startedAt, hideEpoch: hideEpoch)
        }

        pendingHideWorkItem = pollWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0), execute: pollWorkItem)
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
        updateClipboardObservationMode(immediatePoll: true)
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
            window.orderOut(nil)
        }
        updateClipboardObservationMode(immediatePoll: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.suppressProximityUntilExit = true
            self?.model.isToastDismissing = false
            self?.updateClipboardObservationMode()
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

        let current = window.frame
        if abs(current.origin.x - newFrame.origin.x) < 1.0,
           abs(current.origin.y - newFrame.origin.y) < 1.0,
           abs(current.size.width - newFrame.size.width) < 1.0,
           abs(current.size.height - newFrame.size.height) < 1.0 {
            return
        }
        window.setFrame(newFrame, display: false)
    }

    private func scheduleWindowFrameUpdate(for newHeight: CGFloat) {
        guard newHeight.isFinite, newHeight > 1 else { return }
        if !model.isExpanded,
           !model.isPinned,
           model.observedFileToast == nil,
           let window = notchWindow,
           window.alphaValue <= 0.001 {
            pendingWindowHeightUpdate = nil
            return
        }
        let quantizedHeight = newHeight.rounded()
        if let pending = pendingWindowHeightUpdate, abs(pending - quantizedHeight) < 0.6 {
            return
        }
        pendingWindowHeightUpdate = quantizedHeight
        guard windowFrameUpdateWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.windowFrameUpdateWorkItem = nil
            guard let targetHeight = self.pendingWindowHeightUpdate else { return }
            self.pendingWindowHeightUpdate = nil
            self.updateWindowFrameForNewHeight(targetHeight)
        }
        windowFrameUpdateWorkItem = workItem
        let frameDelay: TimeInterval = model.isExpanded ? 0.05 : 0.07
        DispatchQueue.main.asyncAfter(deadline: .now() + frameDelay, execute: workItem)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelIdleCompaction()
        stopIslandOpenMousePolling()
        stopClipboardObservation()
        settings.flushPendingWrites()
        PersistenceWriteCoordinator.shared.flushNow()
        windowFrameUpdateWorkItem?.cancel()
        windowFrameUpdateWorkItem = nil
        pendingWindowHeightUpdate = nil
        if let clipboardActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(clipboardActivationObserver)
            self.clipboardActivationObserver = nil
        }
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
        }

        func startMonitoring() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                self?.handleEvent(event)
                return event
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

// Invisible panel anchored to the top-of-screen activation band. Its content
// view installs an NSTrackingArea so AppKit notifies us only when the cursor
// crosses the union of notch + approach rects, replacing always-on polling.
final class ProximityWakeWindow: NSPanel {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onApproachMouseMoved: ((NSPoint) -> Void)?
    var onDraggingEntered: (() -> Void)?
    var onDraggingUpdated: ((NSPoint) -> Void)?
    var onDraggingExited: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        let view = TrackingHostView(frame: NSRect(origin: .zero, size: contentRect.size))
        view.onMouseEntered = { [weak self] in self?.onMouseEntered?() }
        view.onMouseExited = { [weak self] in self?.onMouseExited?() }
        view.onApproachMouseMoved = { [weak self] pt in self?.onApproachMouseMoved?(pt) }
        view.onDraggingEntered = { [weak self] in self?.onDraggingEntered?() }
        view.onDraggingUpdated = { [weak self] pt in self?.onDraggingUpdated?(pt) }
        view.onDraggingExited = { [weak self] in self?.onDraggingExited?() }
        contentView = view
    }

    func updateTrackingGeometry(notchEdgeRect: CGRect, approachRect: CGRect) {
        (contentView as? TrackingHostView)?.updateTrackingGeometry(
            notchEdgeRect: notchEdgeRect,
            approachRect: approachRect
        )
    }

    final class TrackingHostView: NSView {
        private enum ZoneID: String {
            case notchEdge
            case approach
        }

        var onMouseEntered: (() -> Void)?
        var onMouseExited: (() -> Void)?
        var onApproachMouseMoved: ((NSPoint) -> Void)?
        var onDraggingEntered: (() -> Void)?
        var onDraggingUpdated: ((NSPoint) -> Void)?
        var onDraggingExited: (() -> Void)?
        private var notchEdgeTrackingArea: NSTrackingArea?
        private var approachTrackingArea: NSTrackingArea?
        private var notchEdgeRect: CGRect = .zero
        private var approachRect: CGRect = .zero
        private var activeZones = Set<ZoneID>()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL, .URL])
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            registerForDraggedTypes([.fileURL, .URL])
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            rebuildTrackingArea()
        }

        func updateTrackingGeometry(notchEdgeRect: CGRect, approachRect: CGRect) {
            self.notchEdgeRect = notchEdgeRect
            self.approachRect = approachRect
            rebuildTrackingArea()
        }

        func rebuildTrackingArea() {
            if let existing = notchEdgeTrackingArea {
                removeTrackingArea(existing)
                notchEdgeTrackingArea = nil
            }
            if let existing = approachTrackingArea {
                removeTrackingArea(existing)
                approachTrackingArea = nil
            }
            activeZones.removeAll()

            if notchEdgeRect.width > 0, notchEdgeRect.height > 0 {
                let area = NSTrackingArea(
                    rect: notchEdgeRect,
                    options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                    owner: self,
                    userInfo: ["zone": ZoneID.notchEdge.rawValue]
                )
                addTrackingArea(area)
                notchEdgeTrackingArea = area
            }

            if approachRect.width > 0, approachRect.height > 0 {
                let area = NSTrackingArea(
                    rect: approachRect,
                    options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                    owner: self,
                    userInfo: ["zone": ZoneID.approach.rawValue]
                )
                addTrackingArea(area)
                approachTrackingArea = area
            }
        }

        override func mouseEntered(with event: NSEvent) {
            guard let zone = zoneID(from: event) else { return }
            let inserted = activeZones.insert(zone).inserted
            if inserted {
                onMouseEntered?()
            }
        }

        override func mouseExited(with event: NSEvent) {
            guard let zone = zoneID(from: event) else { return }
            activeZones.remove(zone)
            if activeZones.isEmpty {
                onMouseExited?()
            }
        }

        override func mouseMoved(with event: NSEvent) {
            let localPoint = convert(event.locationInWindow, from: nil)
            if notchEdgeRect.contains(localPoint) {
                let inserted = activeZones.insert(.notchEdge).inserted
                if inserted {
                    onMouseEntered?()
                }
                onApproachMouseMoved?(NSEvent.mouseLocation)
                return
            }
            if approachRect.contains(localPoint) {
                let inserted = activeZones.insert(.approach).inserted
                if inserted {
                    onMouseEntered?()
                }
                onApproachMouseMoved?(NSEvent.mouseLocation)
                return
            }
        }

        private func zoneID(from event: NSEvent) -> ZoneID? {
            guard let raw = event.trackingArea?.userInfo?["zone"] as? String else { return nil }
            return ZoneID(rawValue: raw)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            onDraggingEntered?()
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            onDraggingUpdated?(NSEvent.mouseLocation)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onDraggingExited?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never intercept clicks
    }
}

struct IslandExitTracker {}

final class IslandHostingView<Content: View>: NSHostingView<Content> {}

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
    private var lastCarouselOffsetEmitTime: TimeInterval = 0
    private var lastCarouselOffsetEmitValue: CGFloat = 0
    private var lastCloseProgressEmitTime: TimeInterval = 0
    private var lastCloseProgressEmitValue: CGFloat = 0
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
            lastCarouselOffsetEmitTime = 0
            lastCarouselOffsetEmitValue = 0
            lastCloseProgressEmitTime = 0
            lastCloseProgressEmitValue = 0
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
            let minEmitDelta: CGFloat = isTrackpadLike ? 1.8 : 2.3
            let minEmitInterval: TimeInterval = isTrackpadLike ? (1.0 / 48.0) : (1.0 / 30.0)
            if abs(clampedOffset - lastCarouselOffsetEmitValue) >= minEmitDelta,
               (event.timestamp - lastCarouselOffsetEmitTime) >= minEmitInterval {
                onCarouselOffset?(clampedOffset, false)
                lastCarouselOffsetEmitValue = clampedOffset
                lastCarouselOffsetEmitTime = event.timestamp
            }
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
                lastCarouselOffsetEmitValue = 0
                lastCarouselOffsetEmitTime = event.timestamp
                snapBackWorkItem?.cancel()
                resetAccumulation(resetProgress: true)
                gestureAxis = nil
                ignoreScrollUntil = event.timestamp + 0.18
                return true
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                onCarouselOffset?(0, true)
                lastCarouselOffsetEmitValue = 0
                lastCarouselOffsetEmitTime = event.timestamp
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
            let minEmitDelta: CGFloat = 0.03
            let minEmitInterval: TimeInterval = 1.0 / 50.0
            if progress >= 1
                || (abs(progress - lastCloseProgressEmitValue) >= minEmitDelta
                    && (event.timestamp - lastCloseProgressEmitTime) >= minEmitInterval) {
                onCloseProgressLegacy?(progress, false)
                lastCloseProgressEmitValue = progress
                lastCloseProgressEmitTime = event.timestamp
            }
            if progress >= 1 {
                onSwipeUp?()
                accumulatedDeltaY = 0
                gestureAxis = nil
                verticalCloseArmed = false
                lastCloseProgressEmitValue = 0
                lastCloseProgressEmitTime = event.timestamp
                ignoreScrollUntil = event.timestamp + 0.12
                return true
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                onCloseProgressLegacy?(0, true)
                accumulatedDeltaY = 0
                gestureAxis = nil
                didCommitThisGesture = false
                verticalCloseArmed = false
                lastCloseProgressEmitValue = 0
                lastCloseProgressEmitTime = event.timestamp
                scheduleSnapBack(immediate: true)
            }
            return true
        } else {
            if accumulatedDeltaY > 0 {
                onCloseProgressLegacy?(0, true)
                accumulatedDeltaY = 0
                lastCloseProgressEmitValue = 0
                lastCloseProgressEmitTime = event.timestamp
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
        lastCloseProgressEmitTime = 0
        lastCloseProgressEmitValue = 0
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

    @FocusState private var isJotEditorFocused: Bool

    @State private var highlightedClipboardID: UUID?
    @State private var clipboardTapFeedbackProgress: CGFloat = 0
    @State private var isNotchFileDropTargeted = false
    @State private var isBoxDropTargeted = false
    @State private var selectedBoxFileIDs = Set<UUID>()
    @State private var boxPreviewImages: [URL: NSImage] = [:]
    @State private var boxPreviewLoadingURLs = Set<URL>()
    @State private var boxPreviewLRU: [URL] = []
    @State private var visibleBoxPreviewURLs = Set<URL>()
    @State private var pendingBoxPreviewRemovalWorkItems: [URL: DispatchWorkItem] = [:]
    @State private var pendingSharedPreviewTrimWorkItem: DispatchWorkItem?
    @State private var showShapeHandles = false
    private let maxBoxPreviewCount = 64
    private let retainedInvisibleBoxPreviewCount = 12
    private let adjacentPageRenderActivationOffset: CGFloat = 14
    private let pageTopContentInset: CGFloat = 8

    // This preference key is used to report the animated height of the island back to the AppDelegate.
    struct ShellHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
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
                        if selectedBoxFileIDs.isEmpty {
                            model.boxFiles.removeAll()
                            selectedBoxFileIDs.removeAll()
                        } else {
                            model.boxFiles.removeAll { selectedBoxFileIDs.contains($0.id) }
                            selectedBoxFileIDs.removeAll()
                        }
                    }
                } label: {
                    Text(selectedBoxFileIDs.isEmpty ? "Clear" : "Clear Selected")
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
        let targetIslandWidth = notchWidth + ((panelWidth - notchWidth) * 0.4)
        let islandHeight = notchHeight
        let pagerRowHeight: CGFloat = settings.showPagers ? 14 : 0
        let pagerBottomInset: CGFloat = settings.showPagers ? 8 : 0
        let pagerReservedHeight = pagerRowHeight + pagerBottomInset
        let contentAreaHeight = max(1, shellHeight - islandHeight - pagerReservedHeight)
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
                                globalTitleOverlay(islandWidth: targetIslandWidth, islandHeight: islandHeight)
                                    .opacity(contentProgress)
                                globalControlsOverlay(islandWidth: targetIslandWidth, islandHeight: islandHeight)
                                    .opacity(contentProgress)
                            }
                        }

                        .compositingGroup()
                        .frame(width: islandWidth, height: islandHeight)
                        .padding(.top, 0) // PULLED FLUSH

                        if shouldRenderExpandedContent && contentProgress > 0.01 {
                            HStack(spacing: 0) {
                                ForEach(0..<3) { index in
                                    Group {
                                        if shouldRenderCarouselPage(index) {
                                            switch index {
                                            case 0: clipboardPage
                                            case 1: sidebarPage
                                            case 2: boxPage
                                            default: EmptyView()
                                            }
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: panelWidth)
                                }
                            }
                            .frame(width: panelWidth, height: contentAreaHeight, alignment: .leading)
                            .offset(x: -CGFloat(model.currentPage) * panelWidth + model.carouselDragOffset)
                            .frame(width: shellWidth, height: contentAreaHeight)
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
                                        setPageFromCarousel(index)
                                    } label: {
                                        Capsule(style: .continuous)
                                            .fill(model.currentPage == index ? Color.white : Color.white.opacity(0.28))
                                            .frame(width: model.currentPage == index ? 24 : 14, height: 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: pagerRowHeight)
                            .opacity(contentProgress)
                            .padding(.bottom, pagerBottomInset)
                        }
                    }
                    .frame(width: shellWidth, height: shellHeight, alignment: .top)
                    .background(Color(settings.backgroundColor))
                    .clipShape(BottomRoundedRectangle(cornerRadius: cornerRadius))
                    // Static shadow: fixed radius/offset gated on a Bool instead of
                    // multiplying by contentProgress. An animated radius forces an
                    // offscreen gaussian blur of the entire island on every frame of
                    // the open/close spring; a constant radius is blurred once.
                    .shadow(
                        color: Color.black.opacity(shouldRenderExpandedContent ? 0.22 : 0),
                        radius: shouldRenderExpandedContent ? 18 : 0,
                        x: 0,
                        y: shouldRenderExpandedContent ? 10 : 0
                    )
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
        // Keep swipe paging, but don't preempt taps on pager buttons.
        .simultaneousGesture(horizontalPagingGesture)
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
        .onReceive(model.$currentPage) { newValue in
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.updateObservationState(for: newValue)
            }
            unloadInactivePageState(activePage: newValue)
        }
        .onReceive(model.$isExpanded) { expanded in
            if !expanded {
                unloadCollapsedPageState()
            }
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
        .drawingGroup()
    }

    private var horizontalPagingGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 40 else { return }
                let nextPage = value.translation.width < 0
                    ? min(IslandPage.box.rawValue, model.currentPage + 1)
                    : max(IslandPage.clipboard.rawValue, model.currentPage - 1)
                setPageFromCarousel(nextPage)
            }
    }

    private func setPageFromCarousel(_ page: Int) {
        let nextPage = clamp(page, min: IslandPage.clipboard.rawValue, max: IslandPage.box.rawValue)
        model.carouselDragOffset = 0
        withAnimation(settings.carouselAnimation) {
            model.currentPage = nextPage
        }
    }

    private func shouldRenderCarouselPage(_ index: Int) -> Bool {
        if index == model.currentPage {
            return true
        }

        let offset = model.carouselDragOffset
        if abs(offset) <= adjacentPageRenderActivationOffset {
            return false
        }

        if offset < 0 {
            let next = min(IslandPage.box.rawValue, model.currentPage + 1)
            return index == next
        }

        let previous = max(IslandPage.clipboard.rawValue, model.currentPage - 1)
        return index == previous
    }

    private func touchBoxPreviewURL(_ url: URL) {
        if let existingIndex = boxPreviewLRU.firstIndex(of: url) {
            boxPreviewLRU.remove(at: existingIndex)
        }
        boxPreviewLRU.append(url)
        while boxPreviewLRU.count > maxBoxPreviewCount {
            let removed = boxPreviewLRU.removeFirst()
            boxPreviewImages.removeValue(forKey: removed)
        }
    }

    private func sharedPreviewKeepPaths() -> Set<String> {
        let warmBoxPaths = Set(boxPreviewLRU.suffix(retainedInvisibleBoxPreviewCount).map(\.path))
        let visibleBoxPaths = Set(visibleBoxPreviewURLs.map(\.path))
        return visibleBoxPaths
            .union(warmBoxPaths)
    }

    private func scheduleSharedPreviewTrim() {
        pendingSharedPreviewTrimWorkItem?.cancel()
        let keepPaths = sharedPreviewKeepPaths()
        let workItem = DispatchWorkItem {
            BoxIconCache.shared.schedulePreviewTrim(keepingPaths: keepPaths, debounce: 0.08)
        }
        pendingSharedPreviewTrimWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func clearBoxPreviewState() {
        for workItem in pendingBoxPreviewRemovalWorkItems.values {
            workItem.cancel()
        }
        pendingBoxPreviewRemovalWorkItems.removeAll()
        visibleBoxPreviewURLs.removeAll()
        boxPreviewLoadingURLs.removeAll()
        boxPreviewImages.removeAll()
        boxPreviewLRU.removeAll()
    }

    private func updateBoxPreviewVisibility(for url: URL, isVisible: Bool, targetSize: CGFloat) {
        if isVisible {
            if let pending = pendingBoxPreviewRemovalWorkItems.removeValue(forKey: url) {
                pending.cancel()
            }
            visibleBoxPreviewURLs.insert(url)
            if boxPreviewImages[url] == nil {
                requestBoxPreviewIfNeeded(for: url, targetSize: targetSize)
            } else {
                touchBoxPreviewURL(url)
            }
            scheduleSharedPreviewTrim()
            return
        }

        guard pendingBoxPreviewRemovalWorkItems[url] == nil else { return }
        let workItem = DispatchWorkItem {
            pendingBoxPreviewRemovalWorkItems.removeValue(forKey: url)
            visibleBoxPreviewURLs.remove(url)
            boxPreviewLoadingURLs.remove(url)
            scheduleSharedPreviewTrim()
        }
        pendingBoxPreviewRemovalWorkItems[url] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func unloadInactivePageState(activePage: Int) {
        // Clipboard-only transient UI should reset when the clipboard page is inactive.
        if activePage != IslandPage.clipboard.rawValue {
            highlightedClipboardID = nil
            clipboardTapFeedbackProgress = 0
        }

        // Cancel box preview work only when the Box page is inactive.
        // We deliberately do NOT trim the shared NSCache here — it has its own
        // count/cost limits and a memory-pressure handler.
        if activePage != IslandPage.box.rawValue {
            BoxIconCache.shared.cancelQueuedPreviewLoads()
            for workItem in pendingBoxPreviewRemovalWorkItems.values {
                workItem.cancel()
            }
            pendingBoxPreviewRemovalWorkItems.removeAll()
            visibleBoxPreviewURLs.removeAll()
            boxPreviewLoadingURLs.removeAll()
            selectedBoxFileIDs.removeAll()
        }

        if activePage != IslandPage.jot.rawValue {
            isJotEditorFocused = false
        }
    }

    private func unloadCollapsedPageState() {
        // Cancel transient in-flight work but keep the preview dictionaries
        // and the shared NSCache populated so the next open is cheap. Eviction
        // is delegated to NSCache limits and `purgeCachesForMemoryPressure`.
        unloadInactivePageState(activePage: -1)
        pendingSharedPreviewTrimWorkItem?.cancel()
        pendingSharedPreviewTrimWorkItem = nil
        BoxIconCache.shared.cancelQueuedPreviewLoads()
        for workItem in pendingBoxPreviewRemovalWorkItems.values {
            workItem.cancel()
        }
        pendingBoxPreviewRemovalWorkItems.removeAll()
        visibleBoxPreviewURLs.removeAll()
        boxPreviewLoadingURLs.removeAll()
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
        clipboardPageWithWidth(scaledPanelWidth(for: settings), height: scaledPanelHeight(for: settings) - settings.effectiveNotchHeight)
    }

    private func clipboardPageWithWidth(_ width: CGFloat, height: CGFloat) -> some View {
        ClipboardPageContent(
            chunkedRows: model.chunkedClipboardRows,
            width: width,
            height: max(1, height - pageTopContentInset),
            columnCount: settings.clipboardColumns,
            plainTextSize: settings.clipTextSize,
            fileLabelSize: settings.clipFileLabelSize,
            accentColor: Color(nsColor: settings.accentColor),
            highlightedID: highlightedClipboardID,
            feedbackProgress: clipboardTapFeedbackProgress,
            onTap: copyClipboard
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    private struct ClipboardPageContent: View, Equatable {
        let chunkedRows: [[ClipboardEntry]]
        let width: CGFloat
        let height: CGFloat
        let columnCount: Int
        let plainTextSize: CGFloat
        let fileLabelSize: CGFloat
        let accentColor: Color
        let highlightedID: UUID?
        let feedbackProgress: CGFloat
        let onTap: (ClipboardEntry) -> Void

        static func == (lhs: ClipboardPageContent, rhs: ClipboardPageContent) -> Bool {
            abs(lhs.width - rhs.width) < 0.001 &&
            abs(lhs.height - rhs.height) < 0.001 &&
            lhs.columnCount == rhs.columnCount &&
            abs(lhs.plainTextSize - rhs.plainTextSize) < 0.001 &&
            abs(lhs.fileLabelSize - rhs.fileLabelSize) < 0.001 &&
            lhs.accentColor == rhs.accentColor &&
            lhs.highlightedID == rhs.highlightedID &&
            abs(lhs.feedbackProgress - rhs.feedbackProgress) < 0.01 &&
            lhs.chunkedRows == rhs.chunkedRows
        }

        var body: some View {
            VStack(spacing: 0) {
                if chunkedRows.isEmpty {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white.opacity(0.48))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    let horizontalPadding: CGFloat = 8
                    let spacing: CGFloat = 4
                    let totalSpacing = spacing * CGFloat(columnCount - 1)
                    let wd = max(1, width)
                    let tileSize = max(1, (wd - horizontalPadding * 2 - totalSpacing) / CGFloat(columnCount))
                    
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: spacing) {
                            ForEach(chunkedRows, id: \.first?.id) { row in
                                ClipboardRowView(
                                    items: row,
                                    columnCount: columnCount,
                                    tileSize: tileSize,
                                    spacing: spacing,
                                    plainTextSize: plainTextSize,
                                    fileLabelSize: fileLabelSize,
                                    accentColor: accentColor,
                                    highlightedID: highlightedID,
                                    feedbackProgress: feedbackProgress,
                                    onTap: onTap
                                )
                                .equatable()
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                    .frame(width: wd, alignment: .center)
                }
            }
            .frame(width: width, height: height, alignment: .top)
        }
    }

    private struct ClipboardRowView: View, Equatable {
        let items: [ClipboardEntry]
        let columnCount: Int
        let tileSize: CGFloat
        let spacing: CGFloat
        let plainTextSize: CGFloat
        let fileLabelSize: CGFloat
        let accentColor: Color
        let highlightedID: UUID?
        let feedbackProgress: CGFloat
        let onTap: (ClipboardEntry) -> Void

        static func == (lhs: ClipboardRowView, rhs: ClipboardRowView) -> Bool {
            guard lhs.items.count == rhs.items.count,
                  lhs.columnCount == rhs.columnCount,
                  abs(lhs.tileSize - rhs.tileSize) < 0.001,
                                    abs(lhs.plainTextSize - rhs.plainTextSize) < 0.001,
                                    abs(lhs.fileLabelSize - rhs.fileLabelSize) < 0.001,
                  lhs.items.first?.id == rhs.items.first?.id,
                  lhs.items.last?.id == rhs.items.last?.id else {
                return false
            }

            let lhsHasHighlight = lhs.items.contains { $0.id == lhs.highlightedID }
            let rhsHasHighlight = rhs.items.contains { $0.id == rhs.highlightedID }

            if lhsHasHighlight != rhsHasHighlight { return false }
            if lhsHasHighlight {
                return lhs.highlightedID == rhs.highlightedID &&
                       abs(lhs.feedbackProgress - rhs.feedbackProgress) < 0.01
            }
            return true
        }

        var body: some View {
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    ClipboardTile(
                        item: item,
                        size: tileSize,
                        plainTextSize: plainTextSize,
                        fileLabelSize: fileLabelSize,
                        accentColor: accentColor,
                        isHighlighted: highlightedID == item.id,
                        tapFeedbackProgress: highlightedID == item.id ? feedbackProgress : 0,
                        onTap: onTap
                    )
                    .equatable()
                }
                
                if items.count < columnCount {
                    ForEach(0..<(columnCount - items.count), id: \.self) { _ in
                        Color.clear
                            .frame(width: tileSize, height: tileSize)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// Flat, allocation-light tile. Multi-item clipboard entries render a
    /// single SF Symbol plus a count instead of per-file thumbnails, so a
    /// grouped copy costs the same as a single item.
    private struct ClipboardTile: View, Equatable {
        let item: ClipboardEntry
        let size: CGFloat
        let plainTextSize: CGFloat
        let fileLabelSize: CGFloat
        let accentColor: Color
        let isHighlighted: Bool
        let tapFeedbackProgress: CGFloat
        let onTap: (ClipboardEntry) -> Void

        @State private var loadedPreview: NSImage? = nil
        @State private var isLoadingPreview = false

        static func == (lhs: ClipboardTile, rhs: ClipboardTile) -> Bool {
            lhs.item.id == rhs.item.id &&
            lhs.size == rhs.size &&
            lhs.plainTextSize == rhs.plainTextSize &&
            lhs.fileLabelSize == rhs.fileLabelSize &&
            lhs.isHighlighted == rhs.isHighlighted &&
            lhs.tapFeedbackProgress == rhs.tapFeedbackProgress
        }

        var body: some View {
            let isText = item.isTextOnly
            ZStack {
                if isText {
                    Text(item.cachedDisplayTitle ?? (item.normalizedText.isEmpty ? "Text" : item.normalizedText))
                        .font(.system(size: max(8, plainTextSize)))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .frame(width: size, height: size, alignment: .center)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(accentColor.opacity(0.8), lineWidth: 1)
                        )
                } else {
                    VStack(spacing: 4) {
                        Group {
                            if let preview = loadedPreview, shouldShowSingleFilePreview {
                                Image(nsImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: size * 0.72, height: size * 0.72)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            } else {
                                Image(systemName: item.cachedGlyph ?? glyph)
                                    .font(.system(size: size * 0.50, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }

                        Text(item.cachedDisplayTitle ?? item.fileSummaryText())
                            .font(.system(size: max(8, fileLabelSize), weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: size, height: size, alignment: .center)
                }

                if isHighlighted {
                    UnifiedNotchContainer.ClipboardTapFeedbackGlyph(
                        color: .green,
                        progress: tapFeedbackProgress
                    )
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onTapGesture { onTap(item) }
            .onAppear {
                loadPreviewIfNeeded()
            }
            .onChange(of: item.id) { _, _ in
                loadedPreview = nil
                isLoadingPreview = false
                loadPreviewIfNeeded()
            }
            .onDisappear {
                loadedPreview = nil
                isLoadingPreview = false
            }
        }

        private var glyph: String {
            if let cached = item.cachedGlyph { return cached }
            if item.filePaths.count > 1 { return "doc.on.doc" }
            if item.hasFiles { return item.fileSymbol(at: 0) }
            return "doc.text"
        }

        private var previewURL: URL? {
            guard shouldShowSingleFilePreview,
                  let firstPath = item.filePaths.first else {
                return nil
            }
            return URL(fileURLWithPath: firstPath)
        }

        private var shouldShowSingleFilePreview: Bool {
            guard item.filePaths.count == 1,
                  let firstPath = item.filePaths.first else {
                return false
            }
            return !item.isDirectory(firstPath)
        }

        private func loadPreviewIfNeeded() {
            guard shouldShowSingleFilePreview,
                  let url = previewURL else { return }
            let targetSize = max(64, size * 0.9)

            if let cached = BoxIconCache.shared.cachedPreview(for: url, targetSize: targetSize) {
                loadedPreview = cached
                isLoadingPreview = false
                return
            }

            guard !isLoadingPreview else { return }
            isLoadingPreview = true
            BoxIconCache.shared.requestDisplayImage(for: url, targetSize: targetSize) { image in
                isLoadingPreview = false
                loadedPreview = image
            }
        }
    }

    fileprivate struct ClipboardTapFeedbackGlyph: View {
        let color: Color
        let progress: CGFloat

        var body: some View {
            let p = max(0, min(1, progress))
            Image(systemName: "clipboard")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color.opacity(0.98))
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: max(1, 24 * p))
                }
                .opacity(0.6 + 0.4 * p)
                .frame(width: 36, height: 36)
                .scaleEffect(0.8 + 0.2 * p)
        }
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

    private func clearClipboardHistory() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.clearClipboardHistory()
        } else {
            NSPasteboard.general.clearContents()
            model.clipboardItems.removeAll()
            model.chunkedClipboardRows.removeAll()
            persistClipboardHistory(model.clipboardItems)
        }
        highlightedClipboardID = nil
        clipboardTapFeedbackProgress = 0
    }

    // MARK: - Jot Page
    private var sidebarPage: some View {
        jotPage
    }

    private func sidebarPageWithWidth(_ width: CGFloat, height: CGFloat) -> some View {
        jotPageWithWidth(width, height: height)
    }

    @ViewBuilder
    private func jotPageContent(width: CGFloat, height: CGFloat) -> some View {
        if let activeID = model.activeJotID {
            jotEditor(activeID: activeID, width: width, height: height)
        } else if model.jotNotes.isEmpty {
            emptyDismissableScrollView(
                onMetricsChange: { _, _, _ in }
            ) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: max(120, height * 0.6))
            }
        } else {
            let columnCount = max(1, min(settings.jotColumns, model.jotNotes.count))
            let columns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8), count: columnCount)
            let cellWidth = max(1, (width - CGFloat(max(0, columnCount - 1)) * 8) / CGFloat(columnCount))
            DismissableScrollView(
                closeSensitivity: settings.clampedCloseSensitivity,
                onOverscrollProgress: { progress, animate in
                    updateCloseProgress(progress, animate: animate)
                },
                onBottomOverscroll: { closeNotchFromSwipe() },
                onMetricsChange: { _, _, _ in }
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
        jotPageWithWidth(scaledPanelWidth(for: settings), height: scaledPanelHeight(for: settings) - settings.effectiveNotchHeight)
    }

    private func jotPageWithWidth(_ width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            jotPageContent(width: width, height: height)
            Spacer(minLength: 0)
        }
        .padding(.top, pageTopContentInset)
        .padding(.horizontal, 8)
        .frame(width: max(1, width), height: max(1, height - pageTopContentInset), alignment: .top)
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

    private func jotCard(_ note: JotNote, cellWidth: CGFloat) -> some View {
        let accentColor = Color(settings.accentColor)
        return JotNoteCardView(
            note: note,
            accentColor: accentColor,
            previewText: jotNotePreview(note),
            textSize: settings.jotTextSize,
            isEmpty: note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onOpen: {
                model.activeJotID = note.id
            },
            onDelete: {
                withAnimation {
                    model.jotNotes.removeAll { $0.id == note.id }
                    if model.activeJotID == note.id {
                        model.activeJotID = nil
                    }
                }
            }
        )
    }

    private struct JotNoteCardView: View, Equatable {
        let note: JotNote
        let accentColor: Color
        let previewText: String
        let textSize: CGFloat
        let isEmpty: Bool
        let onOpen: () -> Void
        let onDelete: () -> Void

        static func == (lhs: JotNoteCardView, rhs: JotNoteCardView) -> Bool {
            lhs.note.id == rhs.note.id &&
            lhs.note.updatedAt == rhs.note.updatedAt &&
            lhs.accentColor == rhs.accentColor &&
            lhs.textSize == rhs.textSize &&
            lhs.isEmpty == rhs.isEmpty
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(previewText)
                            .font(.system(size: max(11, textSize)))
                            .fontWeight(isEmpty ? .regular : .semibold)
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentColor.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
    }

    private func jotEditor(activeID: UUID, width: CGFloat, height: CGFloat) -> some View {
        JotTextEditorView(
            text: jotBinding(for: activeID),
            isFocused: $isJotEditorFocused,
            textSize: settings.jotTextSize,
            closeSensitivity: settings.clampedCloseSensitivity,
            onOverscrollProgress: { progress, animate in
                updateCloseProgress(progress, animate: animate)
            },
            onBottomOverscroll: { closeNotchFromSwipe() },
            onScrollMetricsChange: { _, _, _ in }
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
        let textSize: CGFloat
        let closeSensitivity: CGFloat
        let onOverscrollProgressLegacy: (CGFloat, Bool) -> Void
        let onBottomOverscroll: () -> Void
        let onScrollMetricsChange: (CGFloat, CGFloat, CGFloat) -> Void

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, textSize: CGFloat, closeSensitivity: CGFloat, onOverscrollProgress: @escaping (CGFloat, Bool) -> Void, onBottomOverscroll: @escaping () -> Void, onScrollMetricsChange: @escaping (CGFloat, CGFloat, CGFloat) -> Void) {
            self._text = text
            self.isFocused = isFocused
            self.textSize = textSize
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
            textView.font = .systemFont(ofSize: max(11, textSize))

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

            let resolvedSize = max(11, textSize)
            if textView.font?.pointSize != resolvedSize {
                textView.font = .systemFont(ofSize: resolvedSize)
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
        private var lastReportedScrollOffset: CGFloat = .nan
        private var lastReportedContentHeight: CGFloat = .nan
        private var lastReportedViewportHeight: CGFloat = .nan

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
            if !lastReportedScrollOffset.isNaN,
               abs(lastReportedScrollOffset - scrollOffset) < 0.5,
               abs(lastReportedContentHeight - contentHeight) < 0.5,
               abs(lastReportedViewportHeight - viewportHeight) < 0.5 {
                return
            }
            lastReportedScrollOffset = scrollOffset
            lastReportedContentHeight = contentHeight
            lastReportedViewportHeight = viewportHeight
            self.onMetricsChange?(scrollOffset, contentHeight, viewportHeight)
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
                    self.onOverscrollProgress?(0, true)
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
                self.onOverscrollProgress?(progress, false)
                if progress >= 1 {
                    accumulatedOverscroll = 0
                    didTriggerClose = true
                    lastOverscrollProgress = 1
                    self.onOverscrollProgress?(1, true)
                    self.onBottomOverscroll?()
                    return
                }
            } else {
                if accumulatedOverscroll > 0 {
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                } else if lastOverscrollProgress > 0 {
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                }
            }

            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .began || event.momentumPhase == .ended {
                if accumulatedOverscroll > 0 {
                    accumulatedOverscroll = 0
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
                } else if lastOverscrollProgress > 0 {
                    lastOverscrollProgress = 0
                    self.onOverscrollProgress?(0, true)
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
                let intrinsicHeight = hostingView.intrinsicContentSize.height
                let hostingHeight = safeDimension(intrinsicHeight, fallback: max(1, scrollView.contentSize.height))
                let currentSize = hostingView.frame.size
                if abs(currentSize.width - hostingWidth) < 0.5,
                   abs(currentSize.height - hostingHeight) < 0.5 {
                    return
                }
                hostingView.frame = NSRect(x: 0, y: 0, width: hostingWidth, height: hostingHeight)
            }
        }
    }

    // MARK: - Box Page
    private var boxPage: some View {
        boxPageWithWidth(scaledPanelWidth(for: settings), height: scaledPanelHeight(for: settings) - settings.effectiveNotchHeight)
    }

    private func boxPageWithWidth(_ width: CGFloat, height: CGFloat) -> some View {
        let safeW = max(1, width)
        let safeH = max(1, height)
        return VStack(spacing: 10) {
            Group {
                if model.boxFiles.isEmpty {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: min(safeW, safeH) * 0.22, weight: .semibold))
                        .foregroundColor(.brown.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    let columnCount = max(1, settings.boxColumns)
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
                    let maxSize = max(1, min((safeW - 16) / CGFloat(columnCount), safeH * 0.38))
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(model.boxFiles) { file in
                                boxItemView(file: file, maxSize: maxSize)
                            }
                        }
                        .frame(width: width, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .padding(.top, pageTopContentInset)
        .frame(width: width, height: max(1, height - pageTopContentInset), alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $isBoxDropTargeted, perform: handleBoxDrop)
    }

    private func boxItemView(file: BoxFile, maxSize: CGFloat) -> some View {
        return SafeCachedBoxItemView(
            file: file,
            maxSize: maxSize,
            isSelected: selectedBoxFileIDs.contains(file.id),
            accentColor: settings.accentColor,
            showBoxFileNames: settings.showBoxFileNames,
            fileNameSize: settings.boxFileNameSize,
            onRemove: {
                DispatchQueue.main.async {
                    withAnimation {
                        model.boxFiles.removeAll { $0.id == file.id }
                        selectedBoxFileIDs.remove(file.id)
                    }
                }
            },
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
            }
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
        guard model.isExpanded, model.currentPage == IslandPage.box.rawValue else { return }
        guard visibleBoxPreviewURLs.contains(url) else { return }
        guard BoxIconCache.shared.shouldAttemptPreview(for: url) else { return }
        if boxPreviewImages[url] != nil {
            touchBoxPreviewURL(url)
            return
        }
        guard !boxPreviewLoadingURLs.contains(url) else { return }

        let requestSize = quantizedPreviewTargetSize(targetSize)
        boxPreviewLoadingURLs.insert(url)

        BoxIconCache.shared.requestDisplayImage(for: url, targetSize: requestSize) { image in
            boxPreviewLoadingURLs.remove(url)
            guard model.isExpanded, model.currentPage == IslandPage.box.rawValue else { return }
            guard model.boxFiles.contains(where: { $0.url == url }) else { return }
            boxPreviewImages[url] = image
            touchBoxPreviewURL(url)
        }
    }

    private func quantizedPreviewTargetSize(_ targetSize: CGFloat) -> CGFloat {
        let clamped = max(64, min(192, targetSize))
        return ceil(clamped / 24) * 24
    }

    private func pruneBoxPreviewState(keeping urls: [URL]) {
        let keep = Set(urls)
        visibleBoxPreviewURLs = visibleBoxPreviewURLs.intersection(keep)
        boxPreviewImages = boxPreviewImages.filter { keep.contains($0.key) }
        boxPreviewLoadingURLs = Set(boxPreviewLoadingURLs.filter { keep.contains($0) })
        boxPreviewLRU = boxPreviewLRU.filter { keep.contains($0) }
        scheduleSharedPreviewTrim()
    }

    fileprivate struct BoxPreviewPlaceholder: View {
        let isLoading: Bool
        let symbol: String

        var body: some View {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Image(systemName: symbol)
                        .font(.system(size: max(18, side * 0.56), weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.7))
                            .scaleEffect(0.75)
                            .offset(y: side * 0.28)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                if value.isFinite && contentHeight != value {
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

    fileprivate struct HoverRemoveButton: View {
        var action: () -> Void
        var body: some View {
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

    fileprivate struct BoxSelectableDragSurface: NSViewRepresentable {
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
                                    clearClipboardHistory()
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        case .jot:
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
        case .jot:
            title = "Jot"
            symbol = "note.text"
        case .box:
            title = "Box"
            symbol = "shippingbox.fill"
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

extension NSView {
    func findScrollView() -> NSScrollView? {
        if let scrollView = self as? NSScrollView {
            return scrollView
        }
        for subview in subviews {
            if let found = subview.findScrollView() {
                return found
            }
        }
        return nil
    }
}


struct SafeCachedSingleVisual: View {
    let preview: NSImage?
    let targetSize: CGFloat
    let symbol: String

    var body: some View {
        Group {
            if let image = preview {
                let fitted = fittedBoxPreviewSize(for: image, maxDimension: targetSize)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
            }
        }
    }

    private func fittedBoxPreviewSize(for image: NSImage, maxDimension: CGFloat) -> CGSize {
        let maxDim = max(1, maxDimension)
        let rawWidth = max(1, image.size.width)
        let rawHeight = max(1, image.size.height)
        let scale = maxDim / max(rawWidth, rawHeight)
        return CGSize(width: rawWidth * scale, height: rawHeight * scale)
    }
}

struct SafeCachedMultiVisualCell: View {
    let preview: NSImage?
    let size: CGFloat
    let symbol: String

    var body: some View {
        Group {
            if let image = preview {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: size, height: size)
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.40, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }
}

struct SafeCachedBoxItemView: View {
    let file: BoxFile
    let maxSize: CGFloat
    let isSelected: Bool
    let accentColor: NSColor
    let showBoxFileNames: Bool
    let fileNameSize: CGFloat
    let onRemove: () -> Void
    let urlsForDrag: () -> [URL]
    let selectForDrag: () -> Void
    let toggleSelection: () -> Void

    @State private var loadedImage: NSImage? = nil
    @State private var isLoading = false

    var body: some View {
        let size = max(1, maxSize)
        let previewSize = loadedImage.map { fittedSize(for: $0, maxDimension: size) } ?? CGSize(width: size, height: size)

        ZStack(alignment: .topLeading) {
            VStack(spacing: 6) {
                Group {
                    if let image = loadedImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        UnifiedNotchContainer.BoxPreviewPlaceholder(isLoading: isLoading, symbol: placeholderSymbol)
                    }
                }
                .frame(width: previewSize.width, height: previewSize.height)

                if showBoxFileNames {
                    VStack(spacing: 4) {
                        Text(file.url.lastPathComponent)
                            .font(.system(size: max(9, fileNameSize)))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        if isSelected {
                            Capsule()
                                .fill(Color(accentColor))
                                .frame(width: max(12, previewSize.width * 0.7), height: 2)
                        }
                    }
                    .frame(width: previewSize.width + 6)
                }
            }

            UnifiedNotchContainer.HoverRemoveButton {
                onRemove()
            }

            UnifiedNotchContainer.BoxSelectableDragSurface(
                file: file,
                isSelected: isSelected,
                urlsForDrag: urlsForDrag,
                selectForDrag: selectForDrag,
                toggleSelection: toggleSelection,
                removeHotSpotSize: 22
            )
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            loadedImage = nil
            isLoading = false
        }
        .onChange(of: file.url) { _, _ in
            loadImage()
        }
        .frame(
            width: previewSize.width + 8,
            height: showBoxFileNames ? previewSize.height + 36 : previewSize.height,
            alignment: .center
        )
    }

    private func loadImage() {
        let targetSize = max(1, maxSize)
        if let cached = BoxIconCache.shared.cachedPreview(for: file.url, targetSize: targetSize) {
            self.loadedImage = cached
            self.isLoading = false
            return
        }
        guard BoxIconCache.shared.shouldAttemptPreview(for: file.url) else {
            self.isLoading = false
            return
        }
        self.isLoading = true
        BoxIconCache.shared.requestDisplayImage(for: file.url, targetSize: targetSize) { image in
            self.loadedImage = image
            self.isLoading = false
        }
    }

    private func fittedSize(for image: NSImage, maxDimension: CGFloat) -> CGSize {
        let maxDim = max(1, maxDimension)
        let rawWidth = max(1, image.size.width)
        let rawHeight = max(1, image.size.height)
        let scale = maxDim / max(rawWidth, rawHeight)
        return CGSize(width: rawWidth * scale, height: rawHeight * scale)
    }

    private var placeholderSymbol: String {
        if isDirectory(file.url) {
            return "folder.fill"
        }

        let ext = file.url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "bmp", "webp", "svg":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return "archivebox.fill"
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            return "waveform"
        case "mp4", "mov", "mkv", "avi", "webm":
            return "film.fill"
        case "swift", "js", "ts", "tsx", "jsx", "py", "java", "c", "cpp", "h", "hpp", "go", "rs", "rb", "php", "json", "yaml", "yml", "xml", "html", "css", "scss", "md", "txt":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), let isDir = values.isDirectory {
            return isDir
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }
}
