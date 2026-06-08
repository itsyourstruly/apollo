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
import Sparkle
import UniformTypeIdentifiers

public struct LauncherApp: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bundleIdentifier: String?
    public var isPeekerPinned: Bool?

    public init(id: UUID = UUID(), name: String, path: String, bundleIdentifier: String? = nil, isPeekerPinned: Bool? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.isPeekerPinned = isPeekerPinned
    }
}

extension LauncherApp {
    public var isPinned: Bool {
        get { isPeekerPinned ?? true }
        set { isPeekerPinned = newValue }
    }
}

public struct BookmarkItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var urlString: String
    public var customBrowserPath: String?
    public var iconBase64: String?
    public var isPeekerPinned: Bool?

    public init(id: UUID = UUID(), name: String, urlString: String, customBrowserPath: String? = nil, iconBase64: String? = nil, isPeekerPinned: Bool? = nil) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.customBrowserPath = customBrowserPath
        self.iconBase64 = iconBase64
        self.isPeekerPinned = isPeekerPinned
    }
}

extension BookmarkItem {
    public var isPinned: Bool {
        get { isPeekerPinned ?? true }
        set { isPeekerPinned = newValue }
    }
}

// MARK: - Lightweight Page Models
enum IslandPage: Int, CaseIterable, Identifiable {
    case clipboard = 0
    case jot = 1
    case box = 2
    case chrono = 3
    case calendar = 4
    case launcher = 5
    case bookmarks = 6
    case customCombined = 7

    var id: Int { rawValue }
}

enum TitleAlignmentOption: Int, CaseIterable {
    case left = 0
    case right = 1

    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .left: return .leading
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

private let maxStoredClipboardTextLength = 512

private func cappedClipboardText(_ text: String?, limit: Int = maxStoredClipboardTextLength) -> String? {
    guard let text = text else { return nil }
    let capped: String
    if text.count > limit * 2 {
        let endIndex = text.index(text.startIndex, offsetBy: limit * 2)
        capped = String(text[..<endIndex])
    } else {
        capped = text
    }
    let trimmed = capped.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count > limit {
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex])
    }
    return trimmed
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
    private let updaterController: SPUStandardUpdaterController
    private let userDriverDelegate: SparkleUserDriverDelegate

    init() {
            let delegate = SparkleUserDriverDelegate()
            self.userDriverDelegate = delegate
            self.updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: delegate
            )
    }

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model, updater: updaterController.updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
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
    @Published var launcherApps: [LauncherApp] = []
    @Published var bookmarkItems: [BookmarkItem] = []
    @Published var boxDragActive = false
    @Published var boxSlimModeActive = false
    @Published var isSlimBoxCollapsed = false
    @Published var slimBoxWidth: CGFloat = 180
    @Published var slimBoxHeight: CGFloat = 260
    @Published var activeJotID: UUID?
    @Published var clipboardPulseItemID: UUID?
    @Published var observedFileToast: ObservedFileToast?
    @Published var canCloseFromVerticalSwipe = false
    @Published var closeGestureProgress: CGFloat = 0
    @Published var isToastDismissing = false
    @Published var chunkedClipboardRows: [[ClipboardEntry]] = []
    
    @Published var isStopwatchRunning = false
    @Published var stopwatchStartTime: TimeInterval? = nil
    @Published var stopwatchAccumulatedTime: TimeInterval = 0
    @Published var isTimerRunning = false
    @Published var timerDuration: TimeInterval = 0
    @Published var timerEndTime: TimeInterval? = nil
    @Published var timerRemainingAtPause: TimeInterval = 0
    @Published var isAddSheetOpen = false
    @Published var isContentActive = false
}

final class SwipeState: ObservableObject {
    static let shared = SwipeState()
    @Published var carouselDragOffset: CGFloat = 0
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

    // Custom Titles (String)
    static let clipboardCustomTitle = "clipboardCustomTitle"
    static let jotCustomTitle = "jotCustomTitle"
    static let boxCustomTitle = "boxCustomTitle"
    static let chronoCustomTitle = "chronoCustomTitle"
    static let calendarCustomTitle = "calendarCustomTitle"
    static let launcherCustomTitle = "launcherCustomTitle"
    static let bookmarksCustomTitle = "bookmarksCustomTitle"
    static let combinedCustomTitle = "combinedCustomTitle"

    // Show Title Icons (Bool)
    static let clipboardShowTitleIcon = "clipboardShowTitleIcon"
    static let jotShowTitleIcon = "jotShowTitleIcon"
    static let boxShowTitleIcon = "boxShowTitleIcon"
    static let chronoShowTitleIcon = "chronoShowTitleIcon"
    static let calendarShowTitleIcon = "calendarShowTitleIcon"
    static let launcherShowTitleIcon = "launcherShowTitleIcon"
    static let bookmarksShowTitleIcon = "bookmarksShowTitleIcon"
    static let combinedShowTitleIcon = "combinedShowTitleIcon"

    // Bookmark Layout Customizations
    static let bookmarkIconSize = "bookmarkIconSize"
    static let bookmarkTextSize = "bookmarkTextSize"
    static let bookmarkShowName = "bookmarkShowName"

    // Chrono Title Overrides
    static let chronoTitleAlignment = "chronoTitleAlignment"
    static let chronoTitleSize = "chronoTitleSize"
    static let chronoTitleIconName = "chronoTitleIconName"
    static let chronoTitleUseAccent = "chronoTitleUseAccent"
    static let chronoTitleRed = "chronoTitleRed"
    static let chronoTitleGreen = "chronoTitleGreen"
    static let chronoTitleBlue = "chronoTitleBlue"
    static let chronoTitleAlpha = "chronoTitleAlpha"

    // Calendar Title Overrides
    static let calendarTitleAlignment = "calendarTitleAlignment"
    static let calendarTitleSize = "calendarTitleSize"
    static let calendarTitleIconName = "calendarTitleIconName"
    static let calendarTitleUseAccent = "calendarTitleUseAccent"
    static let calendarTitleRed = "calendarTitleRed"
    static let calendarTitleGreen = "calendarTitleGreen"
    static let calendarTitleBlue = "calendarTitleBlue"
    static let calendarTitleAlpha = "calendarTitleAlpha"

    // Launcher Title Overrides
    static let launcherTitleAlignment = "launcherTitleAlignment"
    static let launcherTitleSize = "launcherTitleSize"
    static let launcherTitleIconName = "launcherTitleIconName"
    static let launcherTitleUseAccent = "launcherTitleUseAccent"
    static let launcherTitleRed = "launcherTitleRed"
    static let launcherTitleGreen = "launcherTitleGreen"
    static let launcherTitleBlue = "launcherTitleBlue"
    static let launcherTitleAlpha = "launcherTitleAlpha"

    // Bookmarks Title Overrides
    static let bookmarksTitleAlignment = "bookmarksTitleAlignment"
    static let bookmarksTitleSize = "bookmarksTitleSize"
    static let bookmarksTitleIconName = "bookmarksTitleIconName"
    static let bookmarksTitleUseAccent = "bookmarksTitleUseAccent"
    static let bookmarksTitleRed = "bookmarksTitleRed"
    static let bookmarksTitleGreen = "bookmarksTitleGreen"
    static let bookmarksTitleBlue = "bookmarksTitleBlue"
    static let bookmarksTitleAlpha = "bookmarksTitleAlpha"

    // Combined Title Overrides
    static let combinedTitleAlignment = "combinedTitleAlignment"
    static let combinedTitleSize = "combinedTitleSize"
    static let combinedTitleIconName = "combinedTitleIconName"
    static let combinedTitleUseAccent = "combinedTitleUseAccent"
    static let combinedTitleRed = "combinedTitleRed"
    static let combinedTitleGreen = "combinedTitleGreen"
    static let combinedTitleBlue = "combinedTitleBlue"
    static let combinedTitleAlpha = "combinedTitleAlpha"
    static let disableChronoHUD = "disableChronoHUD"

    // Per-page enable flags
    static let clipEnabled = "clipEnabled"
    static let jotEnabled = "jotEnabled"
    static let boxEnabled = "boxEnabled"
    static let chronoEnabled = "chronoEnabled"
    static let calendarEnabled = "calendarEnabled"
    static let launcherEnabled = "launcherEnabled"
    static let pagerStyle = "pagerStyle"
    static let peekerSize = "peekerSize"
    static let pageOrder = "pageOrder"
    static let openMethod = "openMethod"
    static let bookmarksEnabled = "bookmarksEnabled"
    static let pagerStyle2BackgroundEnabled = "pagerStyle2BackgroundEnabled"
}

func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
    return max(minValue, min(maxValue, value))
}

func safeDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
    guard value.isFinite else { return fallback }
    return max(1, value)
}

func scaledPanelWidth(for settings: AppSettings) -> CGFloat {
    let widthScale = settings.clampedNotchWidth / baseNotchWidth
    return safeDimension(380 * widthScale, fallback: 380)
}

func scaledPanelHeight(for settings: AppSettings) -> CGFloat {
    let heightScale = settings.clampedNotchHeight / baseNotchHeight
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

struct BottomRoundedRectangle: Shape {
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

final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private var missingPaths = Set<String>()
    private let lock = NSRecursiveLock()
    
    private init() {
        cache.countLimit = 100
    }
    
    func icon(forPath path: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        
        let nsPath = path as NSString
        if let cached = cache.object(forKey: nsPath) {
            return cached
        }
        if missingPaths.contains(path) {
            return nil
        }
        
        if FileManager.default.fileExists(atPath: path) {
            let img = NSWorkspace.shared.icon(forFile: path)
            cache.setObject(img, forKey: nsPath)
            return img
        } else {
            missingPaths.insert(path)
            return nil
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        missingPaths.removeAll()
    }
}

final class BookmarkIconCache {
    static let shared = BookmarkIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSRecursiveLock()
    
    private init() {
        cache.countLimit = 100
    }
    
    func image(forBase64 base64: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        
        let nsKey = base64 as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }
        
        if let data = Data(base64Encoded: base64),
           let img = NSImage(data: data) {
            cache.setObject(img, forKey: nsKey)
            return img
        }
        return nil
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
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
        queue.maxConcurrentOperationCount = min(4, ProcessInfo.processInfo.activeProcessorCount)
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

func persistClipboardHistory(_ entries: [ClipboardEntry]) {
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

private func loadLauncherApps() -> [LauncherApp] {
    guard let data = UserDefaults.standard.data(forKey: "launcherApps"),
          let apps = try? JSONDecoder().decode([LauncherApp].self, from: data) else {
        return []
    }
    return apps
}

private func persistLauncherApps(_ apps: [LauncherApp]) {
    if let data = try? JSONEncoder().encode(apps) {
        UserDefaults.standard.set(data, forKey: "launcherApps")
    }
}

private func loadBookmarkItems() -> [BookmarkItem] {
    guard let data = UserDefaults.standard.data(forKey: "bookmarkItems"),
          let bookmarks = try? JSONDecoder().decode([BookmarkItem].self, from: data) else {
        return []
    }
    return bookmarks
}

private func persistBookmarkItems(_ bookmarks: [BookmarkItem]) {
    if let data = try? JSONEncoder().encode(bookmarks) {
        UserDefaults.standard.set(data, forKey: "bookmarkItems")
    }
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
    private var dragPollingTimer: DispatchSourceTimer?
    private var fastDragTrackingTimer: DispatchSourceTimer?
    private var isDragSessionActive = false
    var slimBoxWindow: IslandPanel?
    var slimBoxDidReceiveDropThisSession = false
    private var lastDragChangeCount = -1
    private var clipboardActivationObserver: NSObjectProtocol?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var idleCompactionWorkItem: DispatchWorkItem?
    private var pendingHideWorkItem: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    let model = NotchMenuModel()
    private let settings = AppSettings.shared
    private var settingsCancellables = Set<AnyCancellable>()
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var swipeCloseWorkItem: DispatchWorkItem?
    private var lastCloseProgressEmission: CGFloat = 0
    private var lastCarouselOffsetEmission: CGFloat = 0

    private var notchPreviewWorkItem: DispatchWorkItem?
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastRetryChangeCount = -1
    private var lastWorkspaceClipboardPollTime: TimeInterval = 0
    private var lastImmediateClipboardPollTime: TimeInterval = 0
    private let clipboardQueue = DispatchQueue(label: "apollo.clipboard.poll", qos: .utility)
    private var folderMonitors: [String: FolderMonitor] = [:]
    private var folderSnapshots: [String: Set<String>] = [:]
    private var suppressProximityUntilExit = false
    private var isCursorInActivationZone = false
    private var pendingWindowHeightUpdate: CGFloat?
    private var windowFrameUpdateWorkItem: DispatchWorkItem?
    private var cachedScreenFrame: NSRect = .zero
    private let singleInstanceLock = SingleInstanceLock()

    // Event-driven proximity tracking
    private var proximityWakeWindow: ProximityWakeWindow?   // notch-edge / approach (open trigger)
    private var islandOpenMousePollTimer: DispatchSourceTimer?
    private var approachWorkItem: DispatchWorkItem?
    private var cachePurgeWorkItem: DispatchWorkItem?
    private var boxDragHoldWorkItem: DispatchWorkItem?
    private var isDraggingOverProximity = false
    private var lastApproachProgressSampleTime: TimeInterval = 0
    private var lastApproachProgressEmitted: CGFloat = -1
    private var lastPanelExpandedAt: TimeInterval = 0
    private var panelVisibilityEpoch: UInt64 = 0

    // Wiggle & Slim Box positioning tracking
    var dragWiggleAccumulator: CGFloat = 0
    var lastDragPoint: NSPoint?
    var lastDragTime: TimeInterval = 0
    var slimBoxOpenPosition: NSPoint?
    private var lastDxSign = 0
    private var lastDySign = 0
    private var directionChanges = 0
    private var lastDirectionChangeTime: TimeInterval = 0

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
        let initialRaw = settings.reopenLastPage ? settings.lastVisitedPage : settings.defaultPage
        let initialPage = IslandPage(rawValue: initialRaw) ?? .clipboard
        model.currentPage = activePages.firstIndex(of: initialPage) ?? 0
        setupNotchWindow()
        setupStatusItem()
        observeSettings()
        startMemoryPressureMonitoring()
        startGlobalProximityTracking()
        startGlobalDragPolling()
        startBackgroundStateTracking()
        model.clipboardItems = loadClipboardHistory()
        model.jotNotes = loadJotNotes()
        model.launcherApps = loadLauncherApps()
        model.bookmarkItems = loadBookmarkItems()
        refreshChunkedClipboard()
        normalizeClipboardDirectoryFlagsIfNeeded()
        applyClipboardLimitIfNeeded()
        persistClipboardHistory(model.clipboardItems)
        persistJotNotes(model.jotNotes)
        persistLauncherApps(model.launcherApps)
        persistBookmarkItems(model.bookmarkItems)
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
        let screen = NSScreen.screens.first
        cachedScreenFrame = screen?.frame ?? .zero
        let (x, width, height) = hardwareNotchDimensions(for: screen)
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
            .sink { [weak self] limit in
                guard let self else { return }
                self.applyClipboardLimitIfNeeded()
                persistClipboardHistory(self.model.clipboardItems)
                self.refreshChunkedClipboard()
                
                if limit == 0 {
                    self.stopClipboardObservation()
                    if let observer = self.clipboardActivationObserver {
                        NSWorkspace.shared.notificationCenter.removeObserver(observer)
                        self.clipboardActivationObserver = nil
                    }
                } else {
                    self.observeWorkspaceActivationForClipboardIfNeeded()
                    self.updateClipboardObservationMode(immediatePoll: true)
                }
            }
            .store(in: &settingsCancellables)

        settings.$clipboardColumns
            .sink { [weak self] _ in
                self?.refreshChunkedClipboard()
            }
            .store(in: &settingsCancellables)

        settings.$defaultPage
            .sink { [weak self] rawPage in
                guard let self, !self.model.isExpanded, !self.settings.reopenLastPage else { return }
                let page = IslandPage(rawValue: rawPage) ?? .clipboard
                if let idx = self.activePages.firstIndex(of: page) {
                    self.model.currentPage = idx
                }
            }
            .store(in: &settingsCancellables)

        model.$currentPage
            .sink { [weak self] pageIndex in
                guard let self = self else { return }
                let pages = self.activePages
                if pages.indices.contains(pageIndex) {
                    self.settings.lastVisitedPage = pages[pageIndex].rawValue
                }
            }
            .store(in: &settingsCancellables)

        settings.$customActionsLayoutOption
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    let count = self.activePages.count
                    if self.model.currentPage >= count {
                        self.model.currentPage = count - 1
                    }
                }
            }
            .store(in: &settingsCancellables)

        settings.$observedFolders
            .sink { [weak self] folders in
                self?.configureFolderMonitors(with: folders)
            }
            .store(in: &settingsCancellables)

        settings.$boxSlimModeEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.startGlobalDragPolling()
                } else {
                    if self?.isDragSessionActive == true {
                        self?.isDragSessionActive = false
                        self?.stopFastDragTracking()
                        self?.resetDragTrackingState()
                    }
                    self?.dragPollingTimer?.cancel()
                    self?.dragPollingTimer = nil
                }
            }
            .store(in: &settingsCancellables)

        model.$boxFiles
            .receive(on: RunLoop.main)
            .sink { [weak self] files in
                let urls = files.map(\.url)
                if urls.isEmpty {
                    BoxIconCache.shared.removeAll()
                } else {
                    BoxIconCache.shared.trim(keeping: urls)
                }
                
                guard let self = self else { return }
                if files.count <= 1 {
                    self.model.isSlimBoxCollapsed = false
                }
                if self.model.boxSlimModeActive {
                    if files.isEmpty {
                        self.hideSlimBox()
                    } else {
                        DispatchQueue.main.async {
                            self.updateSlimBoxWindowFrame()
                        }
                    }
                }
            }
            .store(in: &settingsCancellables)

        model.$jotNotes
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { notes in
                persistJotNotes(notes)
            }
            .store(in: &settingsCancellables)

        model.$launcherApps
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { apps in
                persistLauncherApps(apps)
            }
            .store(in: &settingsCancellables)

        model.$bookmarkItems
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { bookmarks in
                persistBookmarkItems(bookmarks)
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

        // Issue 6: When a popover or share sheet is dismissed, immediately check
        // whether the cursor is still inside the island. This gives a natural
        // close-after-dismiss feel without waiting for the next 400ms poll tick.
        model.$isAddSheetOpen
            .sink { [weak self] open in
                guard let self, !open else { return }
                self.handleIslandOpenMousePollTick()
            }
            .store(in: &settingsCancellables)

        // Issue 1: React to enable-flag changes
        Publishers.MergeMany(
            settings.$clipEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$jotEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$boxEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$chronoEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$calendarEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$launcherEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$bookmarksEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$pagerStyle2BackgroundEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$pageOrder.map { _ in () }.eraseToAnyPublisher(),
            settings.$openMethod.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            guard let self else { return }
            self.updateActivePages()
            
            if !self.settings.clipEnabled {
                self.stopClipboardObservation()
            } else {
                self.observeWorkspaceActivationForClipboardIfNeeded()
                self.updateClipboardObservationMode(immediatePoll: true)
            }
            
            if !self.settings.boxEnabled {
                self.configureFolderMonitors(with: [])
            } else {
                self.configureFolderMonitors(with: self.settings.observedFolders)
            }
        }
        .store(in: &settingsCancellables)

        Publishers.CombineLatest4(
            model.$isExpanded,
            model.$isPinned,
            model.$expansionProgress,
            model.$isAddSheetOpen
        )
        .combineLatest(model.$observedFileToast)
        .sink { [weak self] _ in
            self?.updateContentActiveState()
        }
        .store(in: &settingsCancellables)
    }

    private func updateContentActiveState() {
        let isHovered: Bool
        if cachedScreenFrame != .zero {
            let pt = NSEvent.mouseLocation
            let zones = makeProximityZones(screenRect: cachedScreenFrame, point: pt, isFileDrag: false)
            isHovered = zones.isInsideNotch || zones.isHoveringEdge || zones.approachRect.contains(pt)
        } else {
            isHovered = false
        }
        
        let shouldBeActive = model.isExpanded || 
                             model.isPinned || 
                             model.boxSlimModeActive ||
                             (model.expansionProgress > 0.16) || 
                             model.observedFileToast != nil || 
                             (settings.openMethod == 0 && isHovered) || 
                             model.isAddSheetOpen
        
        let wasActive = model.isContentActive
        if wasActive != shouldBeActive {
            model.isContentActive = shouldBeActive
            if shouldBeActive {
                self.cachePurgeWorkItem?.cancel()
                self.cachePurgeWorkItem = nil
            } else {
                self.cachePurgeWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.purgeCachesForMemoryPressure()
                    BoxIconCache.shared.removeAll()
                    AppIconCache.shared.clear()
                    BookmarkIconCache.shared.clear()
                }
                self.cachePurgeWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            }
        }
    }

    var activePages: [IslandPage] {
        if settings.boxEnabled && model.boxSlimModeActive {
            return [.box]
        }
        var pages: [IslandPage] = []
        for pageInt in settings.pageOrder {
            guard let basePage = IslandPage(rawValue: pageInt) else { continue }
            switch basePage {
            case .clipboard:
                if settings.clipEnabled { pages.append(.clipboard) }
            case .jot:
                if settings.jotEnabled { pages.append(.jot) }
            case .box:
                if settings.boxEnabled { pages.append(.box) }
            case .chrono:
                if settings.chronoEnabled { pages.append(.chrono) }
            case .calendar:
                if settings.calendarEnabled { pages.append(.calendar) }
            case .launcher:
                if settings.launcherEnabled {
                    if settings.customActionsLayoutOption == 0 {
                        if !pages.contains(.customCombined) {
                            pages.append(.customCombined)
                        }
                    } else {
                        pages.append(.launcher)
                    }
                }
            case .bookmarks:
                if settings.bookmarksEnabled {
                    if settings.customActionsLayoutOption == 0 {
                        if !pages.contains(.customCombined) {
                            pages.append(.customCombined)
                        }
                    } else {
                        pages.append(.bookmarks)
                    }
                }
            default:
                break
            }
        }
        if pages.isEmpty {
            pages = [.clipboard]
        }
        return pages
    }

    private func updateActivePages() {
        let count = activePages.count
        if model.currentPage >= count {
            model.currentPage = max(0, count - 1)
        }
        updateProximityWakeWindowFrame()
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
        AppIconCache.shared.clear()
        BookmarkIconCache.shared.clear()
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
        SwipeState.shared.carouselDragOffset = 0
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
        guard let window = notchWindow, cachedScreenFrame != .zero else { return }
        let screenRect = cachedScreenFrame
        let defaultWidth = max(panelWidth, notchWidth + 240)
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
        let windowWidth = max(panelWidth, notchWidth + 240)
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
            
            if offset != 0 {
                self.stopClipboardObservation()
            } else {
                self.updateClipboardObservationMode()
            }

            if animate {
                withAnimation(self.settings.carouselAnimation) {
                    SwipeState.shared.carouselDragOffset = offset
                }
            } else {
                SwipeState.shared.carouselDragOffset = offset
            }
        }
        notchWindow.carouselSensitivityProvider = { [weak self] in
            self?.settings.clampedCarouselSensitivity ?? 1.0
        }
        notchWindow.closeSensitivityProvider = { [weak self] in
            self?.settings.clampedCloseSensitivity ?? 1.0
        }
        notchWindow.isAtFirstPageProvider = { [weak self] in
            self?.model.currentPage == 0
        }
        notchWindow.isAtLastPageProvider = { [weak self] in
            guard let self else { return true }
            return self.model.currentPage >= self.activePages.count - 1
        }
        notchWindow.panelWidthProvider = { [weak self] in
            guard let self else { return 300 }
            return scaledPanelWidth(for: self.settings)
        }
        notchWindow.isTapToOpenProvider = { [weak self] in
            self?.settings.openMethod == 1
        }
        notchWindow.isExpandedProvider = { [weak self] in
            self?.model.isExpanded ?? false
        }
        notchWindow.onTapToOpen = { [weak self] in
            self?.showPanel(expanded: true, pinned: false)
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
            let activePagesCount = self.activePages.count
            let next = clamp(self.model.currentPage + direction, min: 0, max: activePagesCount - 1)
            withAnimation(self.settings.carouselAnimation) {
                SwipeState.shared.carouselDragOffset = 0
                self.model.currentPage = next
            }
        }
    }

    private func startBackgroundStateTracking() {
        if settings.rememberClips > 0 {
            startClipboardObservation()
        }
    }

    private func startClipboardObservation() {
        observeWorkspaceActivationForClipboardIfNeeded()
        updateClipboardObservationMode(immediatePoll: true)
    }

    private func shouldKeepClipboardTimerRunning() -> Bool {
        let pages = activePages
        guard pages.indices.contains(model.currentPage) else { return false }
        return (model.isExpanded || model.isPinned) && pages[model.currentPage] == .clipboard
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
        guard settings.rememberClips > 0 else { return }
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
        if let observer = clipboardActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            clipboardActivationObserver = nil
        }
    }

    private func observeWorkspaceActivationForClipboardIfNeeded() {
        guard settings.rememberClips > 0 else { return }
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

    func updateObservationState(for pageIndex: Int) {
        let pages = activePages
        guard pages.indices.contains(pageIndex) else { return }
        updateClipboardObservationMode(immediatePoll: pages[pageIndex] == .clipboard)
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
        autoreleasepool {
            let pasteboard = NSPasteboard.general
            let currentChangeCount = pasteboard.changeCount
            let isNewChange = currentChangeCount != lastClipboardChangeCount
            guard force || isNewChange else { return }

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

            if (trimmedText?.isEmpty == false) || !fileURLs.isEmpty {
                lastClipboardChangeCount = currentChangeCount

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
            } else {
                if isNewChange && currentChangeCount != lastRetryChangeCount {
                    lastRetryChangeCount = currentChangeCount
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                        self?.pollClipboard(force: true)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.pollClipboard(force: true)
                    }
                }
                if !isNewChange {
                    lastClipboardChangeCount = currentChangeCount
                }
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
        // Issue 4b: Only suppress proximity if the cursor is currently over the notch zone.
        // Suppressing unconditionally blocks re-open when the cursor is already far away.
        if cachedScreenFrame != .zero {
            let pt = NSEvent.mouseLocation
            let zones = makeProximityZones(screenRect: cachedScreenFrame, point: pt, isFileDrag: false)
            suppressProximityUntilExit = zones.isInsideNotch || zones.isHoveringEdge
        } else {
            suppressProximityUntilExit = true
        }
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
              cachedScreenFrame != .zero else { return }
        let screenRect = cachedScreenFrame

        // proximityWakeWindow tracks notch edge + approach zone while island is closed.
        let shouldWakeTrackCursor =
            !model.isExpanded &&
            !model.isPinned &&
            model.observedFileToast == nil &&
            !(settings.showHoverPreviews && settings.hoverPreviewFocus != .all)
        guard shouldWakeTrackCursor else {
            resetApproachProgressSampling()
            wake.orderOut(nil)
            if !model.isExpanded && !model.isPinned {
                updateNotchWindowFrame(heightOverride: settings.effectiveNotchHeight)
            }
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
        let approachRect = CGRect(
            x: edgeNotchRect.minX - approachWidth,
            y: edgeNotchRect.minY - approachHeight,
            width: edgeNotchRect.width + (approachWidth * 2),
            height: approachHeight
        )

        let totalHeight = edgeNotchRect.height + approachHeight + cushion
        let totalWidth = edgeNotchRect.width + approachWidth * 2
        let originX = edgeNotchRect.minX - approachWidth
        let originY = screenRect.maxY - totalHeight
        wake.setFrame(NSRect(x: originX, y: originY, width: totalWidth, height: totalHeight), display: false)
        if !wake.isVisible {
            wake.orderFrontRegardless()
        }
        wake.updateTrackingGeometry(
            notchEdgeRect: edgeNotchRect.offsetBy(dx: -originX, dy: -originY),
            approachRect: approachRect.offsetBy(dx: -originX, dy: -originY)
        )

        // If tracking geometry moves under a stationary cursor, AppKit may not
        // emit mouseEntered. Keep activation state in sync, but do not force
        // open from here so hover-open uses the same mouseEntered path.
        let cursor = NSEvent.mouseLocation
        if edgeNotchRect.contains(cursor) {
            setActivationZoneState(true)
        }
    }

    private func handleProximityWakeEntered() {
        updateContentActiveState()
        guard !suppressProximityUntilExit else { return }
        // Only the notch-edge/notch itself should count as activation.
        // Entering approach alone should progressively expand, not open.
        let point = NSEvent.mouseLocation
        if cachedScreenFrame != .zero {
            let zones = makeProximityZones(screenRect: cachedScreenFrame, point: point, isFileDrag: false)
            setActivationZoneState(zones.isInsideNotch || zones.isHoveringEdge)
            if zones.isInsideNotch || zones.isHoveringEdge {
                if settings.openMethod == 0 {
                    showPanel(expanded: true, pinned: false)
                }
            }
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
        if !model.isExpanded && !model.isPinned {
            withAnimation(.easeOut(duration: 0.15)) {
                model.expansionProgress = 0.0
            }
            if notchWindow?.ignoresMouseEvents == false {
                notchWindow?.ignoresMouseEvents = true
            }
        }
        updateContentActiveState()
    }

    private func handleProximityApproachMouseMoved(to point: NSPoint) {
        updateContentActiveState()
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
                let hasActiveChrono = self.model.isStopwatchRunning || self.model.isTimerRunning
                if !hasActiveChrono {
                    checkWindow?.alphaValue = 0.0
                    checkWindow?.ignoresMouseEvents = true
                    checkWindow?.orderOut(nil)
                } else {
                    checkWindow?.alphaValue = 1.0
                    checkWindow?.ignoresMouseEvents = true
                }
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
        boxDragHoldWorkItem?.cancel()
        boxDragHoldWorkItem = nil
        dragWiggleAccumulator = 0
        lastDragPoint = nil
        slimBoxOpenPosition = nil
        model.boxDragActive = false
        model.boxSlimModeActive = false
        handleLegacyProximityWakeExitedFallback()
    }

    // MARK: - Global Drag Polling & Separate Slim Box
    private func setupSlimBoxWindow() {
        guard slimBoxWindow == nil else { return }
        
        let windowWidth: CGFloat = CGFloat(settings.boxSlimModeWidth)
        let windowHeight: CGFloat = CGFloat(settings.boxSlimModeHeight)
        
        let initialRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        let window = IslandPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar + 2
        window.alphaValue = 0.0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        
        window.isActiveProvider = { return false }
        
        // AppKit-level close button handler — fires even when the app is inactive
        window.onCloseButtonTapped = { [weak self] in
            self?.hideSlimBox()
        }
        
        // AppKit-level collapse button handler — fires even when the app is inactive
        window.onCollapseButtonTapped = { [weak self] in
            guard let self = self, self.model.boxFiles.count > 1 else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self.model.isSlimBoxCollapsed.toggle()
            }
            DispatchQueue.main.async {
                self.updateSlimBoxWindowFrame()
            }
        }
        
        window.isCloseButtonVisible = { [weak self] in
            guard let self = self else { return false }
            return !self.model.boxFiles.isEmpty && self.settings.boxSlimModeKeepOpen
        }
        
        window.isCollapseButtonVisible = { [weak self] in
            guard let self = self else { return false }
            return self.model.boxFiles.count > 1 && self.settings.boxSlimModeKeepOpen
        }
        
        let containerView = UnifiedNotchContainer(model: model, settings: settings, isSlimBoxInstance: true)
        window.contentView = IslandHostingView(rootView: containerView)
        
        slimBoxWindow = window
    }

    func updateSlimBoxWindowFrame() {
        guard let window = slimBoxWindow, cachedScreenFrame != .zero else { return }
        let screenRect = cachedScreenFrame
        
        let count = settings.boxSlimModeKeepOpen ? (model.isSlimBoxCollapsed ? (model.boxFiles.isEmpty ? 0 : 1) : model.boxFiles.count) : 0
        let direction = settings.boxSlimModeExpandDirection // 0 = Horizontal, 1 = Vertical
        
        let itemSize: CGFloat = min(CGFloat(settings.boxSlimModeItemWidth), CGFloat(settings.boxSlimModeItemHeight))
        let maxItems = CGFloat(settings.boxSlimModeMaxViewSize)
        
        let padLeftRight: CGFloat = 24
        let padTopBottom: CGFloat = 24
        let spacing: CGFloat = 8
        let headerHeight: CGFloat = 40
        
        // Compute the max width/height based on the item size and max item settings
        var maxSlimWidth: CGFloat = 180
        var maxSlimHeight: CGFloat = 260
        
        if direction == 0 { // Horizontal
            let rawMaxW = padLeftRight + (itemSize * maxItems) + (spacing * (maxItems - 1)) + padLeftRight
            maxSlimWidth = max(180, rawMaxW)
            maxSlimHeight = itemSize + padTopBottom + padTopBottom + headerHeight
        } else { // Vertical
            maxSlimWidth = max(180, itemSize + padLeftRight + padLeftRight)
            let rawMaxH = headerHeight + padTopBottom + (itemSize * maxItems) + (spacing * (maxItems - 1)) + padTopBottom
            maxSlimHeight = max(180, rawMaxH)
        }
        
        var windowWidth: CGFloat = maxSlimWidth
        var windowHeight: CGFloat = maxSlimHeight
        
        if count == 0 {
            if direction == 0 {
                windowWidth = 160
                windowHeight = 90
            } else {
                windowWidth = 120
                windowHeight = 160
            }
        } else {
            if direction == 0 { // Horizontal expansion
                // Height is fixed to the calculated height
                windowHeight = maxSlimHeight
                
                // Width expands to fit current item count up to maxSlimWidth
                let rawWidth = padLeftRight + (itemSize * CGFloat(count)) + (spacing * CGFloat(count - 1)) + padLeftRight
                windowWidth = rawWidth
                if windowWidth > maxSlimWidth { windowWidth = maxSlimWidth }
                if windowWidth < 180 { windowWidth = 180 }
            } else { // Vertical expansion
                // Width is fixed to the calculated width
                windowWidth = maxSlimWidth
                
                // Height expands to fit current item count up to maxSlimHeight
                let rawHeight = headerHeight + padTopBottom + (itemSize * CGFloat(count)) + (spacing * CGFloat(count - 1)) + padTopBottom
                windowHeight = rawHeight
                if windowHeight > maxSlimHeight { windowHeight = maxSlimHeight }
                if windowHeight < 160 { windowHeight = 160 }
            }
        }
        
        var windowX: CGFloat = 0
        var windowY: CGFloat = 0
        
        if model.boxSlimModeActive && window.alphaValue > 0.1 {
            let currentFrame = window.frame
            windowX = currentFrame.midX - windowWidth / 2
            windowY = currentFrame.maxY - windowHeight
        } else if settings.boxSlimModePosition == 1, let openPos = slimBoxOpenPosition {
            windowX = openPos.x - windowWidth / 2
            // Fixed top positioning: top is at openPos.y + 40, growing downwards
            windowY = (openPos.y + 40) - windowHeight
        } else {
            // Default position centered under the notch
            let notchX = settings.hardwareNotchX
            let notchWidth = settings.effectiveNotchWidth
            windowX = notchX - (windowWidth - notchWidth) / 2
            // Fixed top positioning: top is at screenRect.maxY - 20, growing downwards
            windowY = screenRect.maxY - windowHeight - 20
        }
        
        // Clamp to screen bounds with 20px padding
        let screenMinX = screenRect.minX + 20
        let screenMaxX = screenRect.maxX - 20
        let screenMinY = screenRect.minY + 20
        let screenMaxY = screenRect.maxY - 20
        
        if windowX < screenMinX {
            windowX = screenMinX
        } else if windowX + windowWidth > screenMaxX {
            windowX = screenMaxX - windowWidth
        }
        
        if windowY < screenMinY {
            windowY = screenMinY
        } else if windowY + windowHeight > screenMaxY {
            windowY = screenMaxY - windowHeight
        }
        
        window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true)
        model.slimBoxWidth = windowWidth
        model.slimBoxHeight = windowHeight
        settings.boxSlimModeWidth = Double(windowWidth)
        settings.boxSlimModeHeight = Double(windowHeight)
    }

    private func triggerSlimBoxMode() {
        setupSlimBoxWindow()
        
        model.boxSlimModeActive = true
        model.boxDragActive = true
        if settings.boxSlimModePosition == 1 {
            slimBoxOpenPosition = NSEvent.mouseLocation
        } else {
            slimBoxOpenPosition = nil
        }
        
        if let idx = activePages.firstIndex(of: .box) {
            model.currentPage = idx
        }
        
        updateSlimBoxWindowFrame()
        
        if let window = slimBoxWindow {
            window.alphaValue = 1.0
            window.ignoresMouseEvents = false
            window.orderFrontRegardless()
        }
    }

    func hideSlimBox() {
        guard let window = slimBoxWindow else { return }
        model.boxSlimModeActive = false
        model.boxDragActive = false
        // Issue 4d: Don't permanently suppress proximity after hiding the slim box.
        // The cursor may already be outside the notch zone, so suppression would
        // block the very next hover attempt. Reset immediately.
        suppressProximityUntilExit = false
        slimBoxOpenPosition = nil
        
        window.alphaValue = 0.0
        window.ignoresMouseEvents = true
        window.orderOut(nil)
    }

    private func startGlobalDragPolling() {
        dragPollingTimer?.cancel()
        guard settings.boxSlimModeEnabled else { return }
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.pollGlobalDragState()
        }
        timer.resume()
        dragPollingTimer = timer
    }

    private func pollGlobalDragState() {
        autoreleasepool {
            guard settings.boxSlimModeEnabled else {
                if isDragSessionActive {
                    isDragSessionActive = false
                    stopFastDragTracking()
                    resetDragTrackingState()
                }
                return
            }
            
            let isLeftButtonPressed = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
            
            if isDragSessionActive {
                if !isLeftButtonPressed {
                    isDragSessionActive = false
                    stopFastDragTracking()
                    resetDragTrackingState()
                    if model.boxSlimModeActive {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                            guard let self = self else { return }
                            if self.slimBoxDidReceiveDropThisSession {
                                self.slimBoxDidReceiveDropThisSession = false
                                return
                            }
                            let isHovered = self.slimBoxWindow?.frame.contains(NSEvent.mouseLocation) ?? false
                            if !isHovered {
                                self.hideSlimBox()
                            }
                        }
                    }
                }
                return
            }
            
            let dragPboard = dragPasteboard
            let currentChangeCount = dragPboard.changeCount
            
            if currentChangeCount != lastDragChangeCount {
                lastDragChangeCount = currentChangeCount
                
                let hasFileTypes = dragPboard.types?.contains(where: {
                    $0 == .fileURL || $0.rawValue == "public.file-url" || $0.rawValue == "NSFilenamesPboardType"
                }) ?? false
                
                if hasFileTypes && isLeftButtonPressed {
                    isDragSessionActive = true
                    slimBoxDidReceiveDropThisSession = false
                    startFastDragTracking()
                }
            }
        }
    }

    private func startFastDragTracking() {
        slimBoxDidReceiveDropThisSession = false
        fastDragTrackingTimer?.cancel()
        
        dragWiggleAccumulator = 0
        lastDxSign = 0
        lastDySign = 0
        directionChanges = 0
        lastDirectionChangeTime = 0
        lastDragPoint = NSEvent.mouseLocation
        lastDragTime = ProcessInfo.processInfo.systemUptime
        boxDragHoldWorkItem?.cancel()
        boxDragHoldWorkItem = nil
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            self?.trackDragCursorLocation()
        }
        timer.resume()
        fastDragTrackingTimer = timer
    }

    private func stopFastDragTracking() {
        fastDragTrackingTimer?.cancel()
        fastDragTrackingTimer = nil
    }

    private func resetDragTrackingState() {
        boxDragHoldWorkItem?.cancel()
        boxDragHoldWorkItem = nil
        dragWiggleAccumulator = 0
        lastDragPoint = nil
        lastDragTime = 0
        lastDxSign = 0
        lastDySign = 0
        directionChanges = 0
        lastDirectionChangeTime = 0
    }

    private func trackDragCursorLocation() {
        guard settings.boxSlimModeEnabled else { return }
        guard !model.boxSlimModeActive else { return }
        
        let isLeftButtonPressed = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
        if !isLeftButtonPressed {
            isDragSessionActive = false
            stopFastDragTracking()
            resetDragTrackingState()
            if model.boxSlimModeActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self = self else { return }
                    if self.slimBoxDidReceiveDropThisSession {
                        self.slimBoxDidReceiveDropThisSession = false
                        return
                    }
                    let isHovered = self.slimBoxWindow?.frame.contains(NSEvent.mouseLocation) ?? false
                    if !isHovered {
                        self.hideSlimBox()
                    }
                }
            }
            return
        }
        
        guard !model.isExpanded else { return }
        
        let globalPoint = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        
        if settings.boxSlimModeTrigger == 0 { // Wiggle Trigger
            if let lastPoint = lastDragPoint {
                let dx = globalPoint.x - lastPoint.x
                let dy = globalPoint.y - lastPoint.y
                
                let threshold: CGFloat = max(3.0, 25.0 / CGFloat(settings.boxSlimModeWiggleSensitivity))
                var signChanged = false
                
                if abs(dx) > threshold {
                    let currentSignX = dx > 0 ? 1 : -1
                    if lastDxSign != 0 && currentSignX != lastDxSign {
                        signChanged = true
                    }
                    lastDxSign = currentSignX
                }
                
                if abs(dy) > threshold {
                    let currentSignY = dy > 0 ? 1 : -1
                    if lastDySign != 0 && currentSignY != lastDySign {
                        signChanged = true
                    }
                    lastDySign = currentSignY
                }
                
                if signChanged {
                    if now - lastDirectionChangeTime < 0.5 {
                        directionChanges += 1
                    } else {
                        directionChanges = 1
                    }
                    lastDirectionChangeTime = now
                } else if now - lastDirectionChangeTime > 0.5 {
                    directionChanges = 0
                }
                
                if directionChanges >= 4 {
                    triggerSlimBoxMode()
                    stopFastDragTracking()
                }
            }
            lastDragPoint = globalPoint
            lastDragTime = now
        } else { // Delay Trigger
            if boxDragHoldWorkItem == nil {
                let holdDuration = settings.boxSlimModeHoldDuration
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.triggerSlimBoxMode()
                    self.stopFastDragTracking()
                }
                boxDragHoldWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: item)
            }
        }
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
        guard !model.isAddSheetOpen else { return }
        guard hoverCloseWorkItem == nil else { return }
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
        guard !model.isAddSheetOpen else { return }
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
        scheduleHoverCloseIfNeeded()
    }

    private func isPointInsideNotchActivationZone(_ point: NSPoint) -> Bool {
        guard cachedScreenFrame != .zero else { return false }
        let zones = makeProximityZones(screenRect: cachedScreenFrame, point: point, isFileDrag: false)
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
        autoreleasepool {
            if model.boxSlimModeActive {
                return
            }
            if model.isAddSheetOpen {
                hoverCloseWorkItem?.cancel()
                hoverCloseWorkItem = nil
                return
            }
            guard cachedScreenFrame != .zero else { return }
            let screenRect = cachedScreenFrame
            let zones = makeProximityZones(screenRect: screenRect, point: globalPoint, isFileDrag: isFileDrag)
            
            if settings.openMethod == 1 && !isFileDrag {
                let isDirectHoverOverNotch = zones.isInsideNotch || zones.isHoveringEdge
                if isDirectHoverOverNotch {
                    hoverCloseWorkItem?.cancel()
                    hoverCloseWorkItem = nil
                    
                    if abs(model.expansionProgress - 0.15) > 0.01 {
                        withAnimation(.easeOut(duration: 0.15)) {
                            model.expansionProgress = 0.15
                        }
                    }
                    if notchWindow?.alphaValue != 1.0 {
                        notchWindow?.alphaValue = 1.0
                    }
                    if notchWindow?.isVisible == false {
                        notchWindow?.orderFrontRegardless()
                    }
                    if notchWindow?.ignoresMouseEvents != false {
                        notchWindow?.ignoresMouseEvents = false
                    }
                } else {
                    if !model.isExpanded && !model.isPinned {
                        if model.expansionProgress > 0 {
                            withAnimation(.easeOut(duration: 0.15)) {
                                model.expansionProgress = 0.0
                            }
                        }
                        if notchWindow?.ignoresMouseEvents == false {
                            notchWindow?.ignoresMouseEvents = true
                        }
                    }
                    scheduleHoverCloseIfNeeded()
                }
                return
            }

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
                var isWithinExpandedPanel = false
                if let frame = notchWindow?.frame {
                    if model.boxSlimModeActive {
                        let bufferFrame = frame.insetBy(dx: -40, dy: -40)
                        isWithinExpandedPanel = bufferFrame.contains(globalPoint)
                    } else {
                        isWithinExpandedPanel = frame.contains(globalPoint)
                    }
                }
                if isWithinExpandedPanel || zones.isInsideNotch || zones.isHoveringEdge {
                    hoverCloseWorkItem?.cancel()
                    hoverCloseWorkItem = nil
                } else {
                    scheduleHoverCloseIfNeeded()
                }
                return
            }

            if isFileDrag {
                if settings.boxSlimModeEnabled {
                    // Issue 3: When slim mode is enabled, still open the full island if the
                    // cursor is directly on the notch edge so the user can drop normally.
                    if zones.isInsideNotch || zones.isHoveringEdge {
                        boxDragHoldWorkItem?.cancel()
                        boxDragHoldWorkItem = nil
                        model.boxDragActive = true
                        showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
                        if notchWindow?.alphaValue != 1.0 { notchWindow?.alphaValue = 1.0 }
                        if notchWindow?.isVisible == false { notchWindow?.orderFrontRegardless() }
                        if notchWindow?.ignoresMouseEvents != false { notchWindow?.ignoresMouseEvents = false }
                    }
                    // Background drag polling handles the Slim Box triggers for non-notch drags.
                    return
                } else {
                    if isInsideActiveZone {
                        boxDragHoldWorkItem?.cancel()
                        boxDragHoldWorkItem = nil
                        model.boxSlimModeActive = false
                        model.boxDragActive = true
                        showPanel(expanded: true, pinned: false, preferredPage: IslandPage.box.rawValue)
                        
                        if notchWindow?.alphaValue != 1.0 {
                            notchWindow?.alphaValue = 1.0
                        }
                        if notchWindow?.isVisible == false {
                            notchWindow?.orderFrontRegardless()
                        }
                        if notchWindow?.ignoresMouseEvents != false {
                            notchWindow?.ignoresMouseEvents = false
                        }
                    } else {
                        boxDragHoldWorkItem?.cancel()
                        boxDragHoldWorkItem = nil
                        dragWiggleAccumulator = 0
                        lastDragPoint = nil
                        hidePanel()
                    }
                }
                return
            }

            let isDirectHoverOverNotch = zones.isInsideNotch || zones.isHoveringEdge
            let forceApproachForDrag = isFileDrag && settings.alwaysUseApproachWhenDraggingFile
            let disableApproachForCurrentInput = settings.disableApproach && !forceApproachForDrag

            if disableApproachForCurrentInput {
                if isDirectHoverOverNotch, isFileDrag {
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

                // When cursor is already on the notch edge, skip approach prefill.
                // Let showPanel drive a full, consistent open animation instead of
                // arriving with expansionProgress already at 1.0.
                if !isDirectHoverOverNotch {
                    applyApproachProgressIfNeeded(targetProgress)
                }
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

                if isDirectHoverOverNotch, isFileDrag {
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
    }

    private func showPanel(expanded: Bool, pinned: Bool, preferredPage: Int? = nil) {
        guard let window = islandWindow else { return }

        if expanded {
            panelVisibilityEpoch &+= 1
        }

        let resolvedPage: IslandPage?
        if let preferredPage {
            resolvedPage = IslandPage(rawValue: preferredPage)
        } else if expanded {
            if settings.reopenLastPage {
                resolvedPage = IslandPage(rawValue: settings.lastVisitedPage)
            } else if settings.defaultToBoxIfItems, !model.boxFiles.isEmpty {
                resolvedPage = .box
            } else {
                resolvedPage = IslandPage(rawValue: settings.defaultPage)
            }
        } else {
            resolvedPage = nil
        }

        let stateMatches = model.isExpanded == expanded && model.isPinned == pinned
        let currentPageEnum = activePages.indices.contains(model.currentPage) ? activePages[model.currentPage] : .clipboard
        let pageMatches = resolvedPage == nil || currentPageEnum == resolvedPage
        if stateMatches,
           pageMatches,
           abs(model.expansionProgress - 1.0) < 0.001,
           abs(model.closeGestureProgress) < 0.001,
           abs(SwipeState.shared.carouselDragOffset) < 0.001 {
            // Issue 4a: always cancel pending close work items even in the early-return path
            hoverCloseWorkItem?.cancel()
            hoverCloseWorkItem = nil
            swipeCloseWorkItem?.cancel()
            swipeCloseWorkItem = nil
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

        if expanded {
            if model.boxSlimModeActive {
                hideSlimBox()
            }
        }
        let isFreshOpenRequest = expanded && !model.isExpanded
        let wasExpanded = model.isExpanded
        let shouldAnimateOpen = expanded && (isFreshOpenRequest || !wasExpanded || model.expansionProgress < 0.999 || model.closeGestureProgress > 0.001)
        if model.isExpanded != expanded {
            model.isExpanded = expanded
        }
        if model.isPinned != pinned {
            model.isPinned = pinned
        }

        if shouldAnimateOpen {
            var resetTransaction = Transaction()
            resetTransaction.animation = nil
            withTransaction(resetTransaction) {
                model.expansionProgress = 0
                model.closeGestureProgress = 0
                SwipeState.shared.carouselDragOffset = 0
            }
            withAnimation(settings.notchOpenAnimation) {
                model.expansionProgress = 1.0
                model.closeGestureProgress = 0
                SwipeState.shared.carouselDragOffset = 0
            }
        } else {
            if abs(model.expansionProgress - 1.0) > 0.001 {
                model.expansionProgress = 1.0
            }
            if abs(model.closeGestureProgress) > 0.001 {
                model.closeGestureProgress = 0
            }
            if abs(SwipeState.shared.carouselDragOffset) > 0.001 {
                SwipeState.shared.carouselDragOffset = 0
            }
        }
        lastCloseProgressEmission = 0
        lastCarouselOffsetEmission = 0
        if let resolvedPage, let idx = activePages.firstIndex(of: resolvedPage) {
            if model.currentPage != idx {
                model.currentPage = idx
            }
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

    func hidePanel(preserveCloseProgress: Bool = false) {
        if model.boxSlimModeActive {
            hideSlimBox()
            return
        }
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
        model.boxDragActive = false
        model.boxSlimModeActive = false
        // Match open exactly: use the same notch spring for collapse.
        // Keep the window visible long enough for the spring to settle.
        withAnimation(settings.notchOpenAnimation) {
            model.isExpanded = false
            model.expansionProgress = 0.0
            if !preserveCloseProgress {
                model.closeGestureProgress = 0
            }
            SwipeState.shared.carouselDragOffset = 0
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
            let hasActiveChrono = self.model.isStopwatchRunning || self.model.isTimerRunning
            if !hasActiveChrono {
                window.alphaValue = 0.0
                window.ignoresMouseEvents = true
                window.orderOut(nil)
            } else {
                window.alphaValue = 1.0
                window.ignoresMouseEvents = true
            }
            self.updateNotchWindowFrame(heightOverride: self.settings.effectiveNotchHeight)
            self.clearCursorPresenceState()
            // Issue 4c: ensure suppressProximityUntilExit is cleared after close
            // so the very next hover always works correctly.
            self.suppressProximityUntilExit = false
            self.model.expansionProgress = 0
            self.model.boxSlimModeActive = false
            self.slimBoxOpenPosition = nil
            self.dragWiggleAccumulator = 0
            self.lastDragPoint = nil
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
        AppIconCache.shared.clear()
        BookmarkIconCache.shared.clear()
        if !model.isExpanded && !model.isPinned {
            SwipeState.shared.carouselDragOffset = 0
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
            let hasActiveChrono = model.isStopwatchRunning || model.isTimerRunning
            if !hasActiveChrono {
                window.alphaValue = 0.0
                window.ignoresMouseEvents = true
                window.orderOut(nil)
            } else {
                window.alphaValue = 1.0
                window.ignoresMouseEvents = true
            }
        }
        updateClipboardObservationMode(immediatePoll: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.suppressProximityUntilExit = true
            self?.model.isToastDismissing = false
            self?.updateClipboardObservationMode()
        }
    }

    private func updateWindowFrameForNewHeight(_ newHeight: CGFloat) {
        guard let window = notchWindow, cachedScreenFrame != .zero else { return }

        // Don't interfere when settings previews are active, as they use a fixed large frame.
        if settings.showHoverPreviews && settings.hoverPreviewFocus != .all {
            return
        }

        guard newHeight.isFinite, newHeight > 1 else { return }

        // Keep the window width fixed at the maximum possible panel width to avoid clipping content during animation.
        let windowWidth = max(self.panelWidth, self.notchWidth + 240)
        let windowHeight = newHeight

        // Correct window positioning: Center the window's midpoint on the hardware notch's midpoint
        let notchX = settings.hardwareNotchX
        let notchWidth = settings.effectiveNotchWidth
        let windowX = notchX - (windowWidth - notchWidth) / 2
        let windowY = cachedScreenFrame.maxY - windowHeight

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
        if model.boxSlimModeActive {
            return
        }
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
        dragPollingTimer?.cancel()
        dragPollingTimer = nil
        fastDragTrackingTimer?.cancel()
        fastDragTrackingTimer = nil
        slimBoxWindow?.orderOut(nil)
        slimBoxWindow = nil
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
            guard self.notchEdgeRect != notchEdgeRect || self.approachRect != approachRect else {
                return
            }
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

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
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
    var onCloseButtonTapped: (() -> Void)?
    var onCollapseButtonTapped: (() -> Void)?
    var isCloseButtonVisible: (() -> Bool)?
    var isCollapseButtonVisible: (() -> Bool)?

    var isAtFirstPageProvider: (() -> Bool)?
    var isAtLastPageProvider: (() -> Bool)?
    var panelWidthProvider: (() -> CGFloat)?
    var isTapToOpenProvider: (() -> Bool)?
    var isExpandedProvider: (() -> Bool)?
    var onTapToOpen: (() -> Void)?

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
        // Intercept left mouse clicks in the close button region at the AppKit level
        // This bypasses SwiftUI's gesture system which doesn't work reliably in non-activating panels
        if event.type == .leftMouseDown {
            if isTapToOpenProvider?() == true, isExpandedProvider?() == false {
                onTapToOpen?()
                return
            }
            
            let loc = event.locationInWindow
            let size = self.frame.size
            
            // Close button is in the top-right corner: 40x42 hit region
            if let closeHandler = onCloseButtonTapped, isCloseButtonVisible?() == true {
                let closeRect = NSRect(x: size.width - 40, y: size.height - 42, width: 40, height: 42)
                if closeRect.contains(loc) {
                    closeHandler()
                    return
                }
            }
            
            // Collapse button: 40x42 hit region immediately to the left of the close button (x: width - 80 to width - 40)
            if let collapseHandler = onCollapseButtonTapped, isCollapseButtonVisible?() == true {
                let collapseRect = NSRect(x: size.width - 80, y: size.height - 42, width: 40, height: 42)
                if collapseRect.contains(loc) {
                    collapseHandler()
                    return
                }
            }
        }
        if event.type == .scrollWheel || event.type == .swipe {
            if handleGestureEvent(event) {
                return
            }
        }
        super.sendEvent(event)
    }

    private func rubberBand(offset: CGFloat, limit: CGFloat) -> CGFloat {
        let absOffset = abs(offset)
        let sign: CGFloat = offset >= 0 ? 1.0 : -1.0
        let factor = 1.0 / (1.0 + absOffset / limit)
        return sign * limit * (1.0 - factor)
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
            let panelWidth = panelWidthProvider?() ?? 300
            let rawOffset = -accumulatedDeltaX
            
            let finalOffset: CGFloat
            let isAtFirst = isAtFirstPageProvider?() == true
            let isAtLast = isAtLastPageProvider?() == true
            
            if isAtFirst && rawOffset > 0 {
                finalOffset = rubberBand(offset: rawOffset, limit: 60)
            } else if isAtLast && rawOffset < 0 {
                finalOffset = rubberBand(offset: rawOffset, limit: 60)
            } else {
                finalOffset = clamp(rawOffset, min: -panelWidth, max: panelWidth)
            }
            
            // Issue 7: Lower thresholds to let every ProMotion frame emit an update.
            let minEmitDelta: CGFloat = isTrackpadLike ? 0.5 : 1.5
            let minEmitInterval: TimeInterval = isTrackpadLike ? (1.0 / 120.0) : (1.0 / 60.0)
            if abs(finalOffset - lastCarouselOffsetEmitValue) >= minEmitDelta,
               (event.timestamp - lastCarouselOffsetEmitTime) >= minEmitInterval {
                onCarouselOffset?(finalOffset, false)
                lastCarouselOffsetEmitValue = finalOffset
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

// MARK: - Box Share Feature
// MARK: - Box Share Feature
struct BoxControlsAppIconView: View {
    let appPath: String
    let size: CGFloat

    var body: some View {
        if FileManager.default.fileExists(atPath: appPath) {
            if let icon = AppIconCache.shared.icon(forPath: appPath) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundColor(.gray.opacity(0.5))
        }
    }
}

struct BoxShareButton: View {
    let files: [BoxFile]
    let selectedIDs: Set<UUID>
    let accentColor: NSColor
    
    @State private var isShareTargeted = false
    @State private var targetedAppPath: String? = nil
    @State private var shareCoordinator: SharePickerCoordinator?

    private var urlsToShare: [URL] {
        let selected = files.filter { selectedIDs.contains($0.id) }.map(\.url)
        return selected.isEmpty ? files.map(\.url) : selected
    }

    var body: some View {
        HStack(spacing: 8) {
            if !AppSettings.shared.sharingTargetApps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(AppSettings.shared.sharingTargetApps, id: \.self) { appPath in
                        let appURL = URL(fileURLWithPath: appPath)
                        let appName = appURL.deletingPathExtension().lastPathComponent
                        let isHovered = targetedAppPath == appPath
                        
                        Button {
                            openFiles(urlsToShare, with: appPath)
                        } label: {
                            BoxControlsAppIconView(appPath: appPath, size: 20)
                                .padding(8)
                                .background(isHovered ? Color.white.opacity(0.3) : Color.black.opacity(0.4), in: Circle())
                                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("Open with \(appName)")
                        .onDrop(of: [.fileURL], isTargeted: Binding(
                            get: { self.targetedAppPath == appPath },
                            set: { isTargeted in
                                if isTargeted {
                                    self.targetedAppPath = appPath
                                } else if self.targetedAppPath == appPath {
                                    self.targetedAppPath = nil
                                }
                            }
                        )) { providers in
                            handleAppDrop(providers: providers, appPath: appPath)
                            return true
                        }
                    }
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)
            }

            Button {
                share(urls: urlsToShare)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(accentColor).gradient)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(isShareTargeted ? Color.white.opacity(0.3) : Color.black.opacity(0.4), in: Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: $isShareTargeted) { providers in
                handleShareDrop(providers: providers)
                return true
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.25), in: Capsule())
    }

    private func openFiles(_ urls: [URL], with appPath: String) {
        guard !urls.isEmpty else { return }
        let appURL = URL(fileURLWithPath: appPath)
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func handleAppDrop(providers: [NSItemProvider], appPath: String) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.slimBoxDidReceiveDropThisSession = true
        }
        var droppedURLs: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileUrl = url {
                    DispatchQueue.main.async {
                        droppedURLs.append(fileUrl)
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.openFiles(droppedURLs, with: appPath)
        }
    }

    private func share(urls: [URL]) {
        guard !urls.isEmpty else { return }
        // Issue 6: Set isAddSheetOpen so the island doesn't close while the picker is visible.
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.model.isAddSheetOpen = true
        }
        let picker = NSSharingServicePicker(items: urls)
        let coordinator = SharePickerCoordinator {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.model.isAddSheetOpen = false
            }
            DispatchQueue.main.async {
                self.shareCoordinator = nil
            }
        }
        self.shareCoordinator = coordinator
        picker.delegate = coordinator
        if let window = NSApp.keyWindow, let view = window.contentView {
            let rect = NSRect(x: view.bounds.width - 50, y: view.bounds.height - 20, width: 1, height: 1)
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        } else {
            // No window available; clear the flag immediately.
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.model.isAddSheetOpen = false
            }
            self.shareCoordinator = nil
        }
    }

    private func handleShareDrop(providers: [NSItemProvider]) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.slimBoxDidReceiveDropThisSession = true
        }
        var droppedURLs: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileUrl = url {
                    DispatchQueue.main.async {
                        droppedURLs.append(fileUrl)
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.share(urls: droppedURLs)
        }
    }
}

// MARK: - Issue 6: Share Picker Coordinator
// Tracks NSSharingServicePicker lifecycle so model.isAddSheetOpen stays true
// while the share sheet is visible, preventing the island from closing.
final class SharePickerCoordinator: NSObject, NSSharingServicePickerDelegate {
    private let onDismiss: () -> Void

    init(_ onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onDismiss()
    }
}

extension View {
    @ViewBuilder
    func conditionalDrawingGroup(_ active: Bool) -> some View {
        if active {
            self.drawingGroup()
        } else {
            self
        }
    }
}

// Issue 7: Use GeometryEffect instead of offset() so SwiftUI applies the
// translation at the CALayer level without re-running layout for the entire
// container on every swipe event. The animatableData conformance means
// withAnimation(...) still drives the spring settle correctly.
struct CarouselTranslationEffect: GeometryEffect {
    var offsetX: CGFloat

    var animatableData: CGFloat {
        get { offsetX }
        set { offsetX = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: offsetX, y: 0))
    }
}

// MARK: - Master Container Structural Layout
struct UnifiedNotchContainer: View {
    @ObservedObject var model: NotchMenuModel
    @ObservedObject var settings: AppSettings
    var isSlimBoxInstance: Bool = false

    @State var isJotEditorFocused: Bool = false

    @State var highlightedClipboardID: UUID?
    @State var clipboardTapFeedbackProgress: CGFloat = 0
    @State var isNotchFileDropTargeted = false
    @State var isBoxDropTargeted = false
    @State var selectedBoxFileIDs = Set<UUID>()
    @State private var isAddAppPresented = false
    @State private var isAddBookmarkPresented = false
    @State private var animatingFromPage: Int? = nil
    
    var isSlimModeActive: Bool {
        isSlimBoxInstance
    }
    
    var activePages: [IslandPage] {
        if isSlimModeActive {
            return [.box]
        }
        var pages: [IslandPage] = []
        for pageInt in settings.pageOrder {
            guard let basePage = IslandPage(rawValue: pageInt) else { continue }
            switch basePage {
            case .clipboard:
                if settings.clipEnabled { pages.append(.clipboard) }
            case .jot:
                if settings.jotEnabled { pages.append(.jot) }
            case .box:
                if settings.boxEnabled { pages.append(.box) }
            case .chrono:
                if settings.chronoEnabled { pages.append(.chrono) }
            case .calendar:
                if settings.calendarEnabled { pages.append(.calendar) }
            case .launcher:
                if settings.launcherEnabled {
                    if settings.customActionsLayoutOption == 0 {
                        if !pages.contains(.customCombined) {
                            pages.append(.customCombined)
                        }
                    } else {
                        pages.append(.launcher)
                    }
                }
            case .bookmarks:
                if settings.bookmarksEnabled {
                    if settings.customActionsLayoutOption == 0 {
                        if !pages.contains(.customCombined) {
                            pages.append(.customCombined)
                        }
                    } else {
                        pages.append(.bookmarks)
                    }
                }
            default:
                break
            }
        }
        if pages.isEmpty {
            pages = [.clipboard]
        }
        return pages
    }


    let pageTopContentInset: CGFloat = 2

    // This preference key is used to report the animated height of the island back to the AppDelegate.
    struct ShellHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    func updateCloseProgress(_ progress: CGFloat, animate: Bool) {
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

    func closeNotchFromSwipe() {
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
        let isBoxPage = activePages.indices.contains(model.currentPage) && activePages[model.currentPage] == .box
        let showControls = model.isExpanded && isBoxPage && !model.boxFiles.isEmpty && !isSlimModeActive
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

    private var slimBoxMenuBarControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    if selectedBoxFileIDs.count == model.boxFiles.count {
                        selectedBoxFileIDs.removeAll()
                    } else {
                        selectedBoxFileIDs = Set(model.boxFiles.map { $0.id })
                    }
                }
            } label: {
                Image(systemName: selectedBoxFileIDs.count == model.boxFiles.count ? "bookmark.slash.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(selectedBoxFileIDs.count == model.boxFiles.count ? "Deselect All" : "Select All")

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
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help(selectedBoxFileIDs.isEmpty ? "Clear All" : "Clear Selected")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .padding(6)
    }

    var body: some View {
        Group {
            if !isSlimBoxInstance && !model.isContentActive {
                Color.clear
                    .frame(width: 1, height: 1)
            } else {
                let currentSlimWidth = model.slimBoxWidth
                let currentSlimHeight = model.slimBoxHeight

                let panelWidth = isSlimModeActive ? currentSlimWidth : scaledPanelWidth(for: settings)
                let panelHeight = isSlimModeActive ? currentSlimHeight : scaledPanelHeight(for: settings)

                let notchWidth = isSlimModeActive ? 0 : settings.effectiveNotchWidth
                let notchHeight = isSlimModeActive ? 0 : settings.effectiveNotchHeight
                let rawProgress = isSlimModeActive ? 1.0 : model.expansionProgress
                let progress = rawProgress.isFinite ? max(0, min(1, rawProgress)) : 0
                let easedProgress = progress * progress * (3 - 2 * progress)
                
                let showStopwatch = model.isStopwatchRunning
                let showTimer = model.isTimerRunning
                let targetLeftExt: CGFloat = showStopwatch ? 100 : 0
                let targetRightExt: CGFloat = showTimer ? 100 : 0
                let activeLeftExt = targetLeftExt * (1 - easedProgress)
                let activeRightExt = targetRightExt * (1 - easedProgress)

                let baseRawShellWidth = notchWidth + ((panelWidth - notchWidth) * easedProgress)
                let rawShellWidth = isSlimModeActive ? panelWidth : max(baseRawShellWidth, notchWidth + activeLeftExt + activeRightExt)
                let rawShellHeight = notchHeight + ((panelHeight - notchHeight) * easedProgress)
                let shellWidth = safeDimension(rawShellWidth, fallback: panelWidth)
                let shellHeight = safeDimension(rawShellHeight, fallback: panelHeight)
                let baseIslandWidth = notchWidth + ((panelWidth - notchWidth) * easedProgress * 0.4)
                let islandWidth = baseIslandWidth + activeLeftExt + activeRightExt
                let targetIslandWidth = notchWidth + ((panelWidth - notchWidth) * 0.4)
                let islandOffset = (activeRightExt - activeLeftExt) / 2
                let islandHeight = notchHeight
                let pagerRowHeight: CGFloat = (settings.showPagers && !isSlimModeActive) ? 14 : 0
                let pagerBottomInset: CGFloat = (settings.showPagers && !isSlimModeActive) ? 8 : 0
                let pagerReservedHeight = pagerRowHeight + pagerBottomInset
                let isPeekerVisible = !isSlimModeActive && ((settings.showLauncherInPeeker && !model.launcherApps.isEmpty) ||
                              (settings.showBookmarksInPeeker && !model.bookmarkItems.isEmpty))
                let peekerHeight: CGFloat = isPeekerVisible ? 24 : 0
                let contentAreaHeight = max(1, panelHeight - notchHeight - pagerReservedHeight - peekerHeight - (isSlimModeActive ? 0 : 2))
                let cornerRadius = safeDimension(max(4, settings.cornerRadius * (0.6 + 0.4 * easedProgress)), fallback: 8)
                let contentProgress = easedProgress.isFinite ? max(0, min(1, (easedProgress - 0.18) / 0.82)) : 0
                let showToastOnly = (model.observedFileToast != nil || model.isToastDismissing) && !model.isExpanded && !model.isPinned
                let isFloatingPagerActive = settings.pagerStyle == 1 && settings.showPagers && !isSlimModeActive
                let floatingPagerHeightAdjustment: CGFloat = isFloatingPagerActive ? (8 * easedProgress + 44 * easedProgress) : 0
                let baseContainerHeight = isSlimModeActive ? currentSlimHeight : (showToastOnly ? max(panelHeight, toastPanelHeight) : panelHeight)
                let containerHeight = safeDimension(baseContainerHeight + floatingPagerHeightAdjustment, fallback: panelHeight)
                let toastWidth = toastPanelWidth
                let containerWidth = isSlimModeActive ? currentSlimWidth : max(panelWidth, notchWidth + 240)
                let closeProgress = max(0, min(1, model.closeGestureProgress))
                let closeEase = closeProgress * closeProgress * (3 - 2 * closeProgress)
                let closeOffset = -44 * closeEase
                let closeScale = 1 - (0.14 * closeEase)
                let shouldRenderExpandedContent = model.isExpanded || model.isPinned || isSlimModeActive

                ZStack(alignment: .top) {
                    // Overlay previews so they don't impact the measured height of the island body
                    if settings.showHoverPreviews && !isSlimModeActive {
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
                        VStack(spacing: 8 * easedProgress) {
                            VStack(spacing: 0) {
                                VStack(spacing: 0) {
                                    // UNIFIED FIX: Pad internal layouts to offset default top window inset masking values
                                    if !isSlimModeActive {
                                        ZStack {
                                            Capsule()
                                                .fill(Color(nsColor: settings.backgroundColor.withAlphaComponent(1.0)))
                                                .frame(width: islandWidth, height: islandHeight)

                                            globalTitleOverlay(islandWidth: targetIslandWidth, islandHeight: islandHeight)
                                                .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                                                .allowsHitTesting(shouldRenderExpandedContent)
                                            globalControlsOverlay(islandWidth: targetIslandWidth, islandHeight: islandHeight)
                                                .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                                                .allowsHitTesting(shouldRenderExpandedContent)

                                            if !model.isExpanded && !model.isPinned {
                                                closedIslandChronoWidgets(islandWidth: islandWidth, islandHeight: islandHeight, leftExt: activeLeftExt, rightExt: activeRightExt)
                                            }
                                        }
                                        .compositingGroup()
                                        .frame(width: islandWidth, height: islandHeight)
                                        .padding(.top, 0)
                                    }

                                    let pages = activePages
                                    CarouselContainer(isSlimBoxInstance: isSlimBoxInstance, currentPage: model.currentPage, panelWidth: panelWidth) {
                                        HStack(spacing: 0) {
                                            ForEach(0..<pages.count, id: \.self) { index in
                                                let resolvedCurrentPage = isSlimBoxInstance ? 0 : model.currentPage
                                                if shouldRenderExpandedContent && (index == resolvedCurrentPage || index == animatingFromPage) {
                                                    pageView(for: pages[index], contentAreaHeight: contentAreaHeight)
                                                        .frame(width: panelWidth, height: contentAreaHeight, alignment: .top)
                                                        .clipped()
                                                } else {
                                                    Color.clear
                                                        .frame(width: panelWidth, height: contentAreaHeight, alignment: .top)
                                                }
                                            }
                                        }
                                        .frame(width: panelWidth, height: contentAreaHeight, alignment: .leading)
                                    }
                                    .padding(.top, 2)
                                    .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                                    .allowsHitTesting(shouldRenderExpandedContent)

                                    if isPeekerVisible && !isSlimModeActive {
                                        PeekerWidgetView(
                                            apps: model.launcherApps,
                                            bookmarks: model.bookmarkItems,
                                            showApps: settings.showLauncherInPeeker,
                                            showBookmarks: settings.showBookmarksInPeeker,
                                            accentColor: Color(settings.accentColor),
                                            itemSize: settings.peekerSize
                                        )
                                        .frame(height: peekerHeight)
                                        .opacity(shouldRenderExpandedContent ? contentProgress : 0)
                                        .allowsHitTesting(shouldRenderExpandedContent)
                                        .padding(.bottom, 2)
                                    }

                                    if settings.showPagers && !isSlimModeActive && settings.pagerStyle == 0 {
                                        HStack(spacing: 8) {
                                            ForEach(0..<pages.count, id: \.self) { index in
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
                                        .opacity(easedProgress)
                                        .padding(.bottom, pagerBottomInset)
                                        .offset(y: -(panelHeight - notchHeight - settings.clampedNotchEdgeThickness) * (1 - (model.isExpanded || model.isPinned ? easedProgress : 0)))
                                        .allowsHitTesting(shouldRenderExpandedContent)
                                    }
                                }
                                .frame(width: panelWidth, height: panelHeight, alignment: .top)
                                .frame(width: shellWidth, height: shellHeight, alignment: .top)
                                .conditionalClip(clipAll: isSlimModeActive, cornerRadius: cornerRadius)
                                .background(
                                    Group {
                                        if isSlimModeActive {
                                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                                .fill(Color(settings.backgroundColor))
                                                .shadow(color: Color.black.opacity(shouldRenderExpandedContent ? 0.22 : 0),
                                                        radius: shouldRenderExpandedContent ? 18 : 0, x: 0, y: shouldRenderExpandedContent ? 10 : 0)
                                        } else {
                                            BottomRoundedRectangle(cornerRadius: cornerRadius)
                                                .fill(Color(settings.backgroundColor))
                                                .shadow(color: Color.black.opacity(shouldRenderExpandedContent ? 0.22 : 0),
                                                        radius: shouldRenderExpandedContent ? 18 : 0, x: 0, y: shouldRenderExpandedContent ? 10 : 0)
                                        }
                                    }
                                )
                                .animation(settings.notchOpenAnimation, value: model.expansionProgress)
                            }

                            if settings.pagerStyle == 1 && settings.showPagers && !isSlimModeActive {
                                floatingPagerView(pages: activePages)
                                    .opacity(easedProgress)
                                    .scaleEffect(0.6 + 0.4 * easedProgress)
                                    .frame(height: 44 * easedProgress)
                            }
                        }
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ShellHeightKey.self, value: proxy.size.height)
                        })
                        .offset(x: islandOffset)
                    } // End if !showToastOnly
                } // End ZStack
                .frame(width: containerWidth, height: containerHeight, alignment: .top)
                .overlay(alignment: .topLeading) {
                    if isSlimModeActive {
                        if !model.boxFiles.isEmpty && settings.boxSlimModeKeepOpen {
                            slimBoxMenuBarControls
                                .zIndex(50)
                        }
                    } else {
                        boxMenuBarControls
                            .zIndex(50)
                    }
                }
                .scaleEffect(closeScale, anchor: .top)
                .offset(y: closeOffset)
                // Keep swipe paging, but don't preempt taps on pager buttons. Disable swipe gesture in slim mode so window background dragging works.
                .simultaneousGesture(isSlimModeActive ? nil : horizontalPagingGesture)
                .contextMenu {
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
                .onChange(of: isAddBookmarkPresented) { _, newValue in
                    model.isAddSheetOpen = newValue
                }
                .onChange(of: isAddAppPresented) { _, newValue in
                    model.isAddSheetOpen = newValue
                }
                .onChange(of: model.currentPage) { oldValue, newValue in
                    animatingFromPage = oldValue
                    // Issue 7: Reduce from 400ms to 220ms — the spring (response: 0.32) settles in ~240ms.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        if animatingFromPage == oldValue {
                            animatingFromPage = nil
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
            }
        }
    }

    @ViewBuilder
    private var settingsPreviewOverlay: some View {
        GeometryReader { geo in
            let edgeNotchWidth = settings.effectiveNotchWidth
            let edgeNotchHeight = settings.effectiveNotchHeight
            let edge = settings.clampedNotchEdgeThickness
            let approachWidth = settings.clampedApproachWidth
            let approachHeight = settings.clampedApproachHeight
            let focus = settings.hoverPreviewFocus
            let accent = Color(settings.accentColor)
            let edgeNotchX = (geo.size.width - edgeNotchWidth) / 2
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
                        EmptyView()
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

    private func symbolForPage(_ page: IslandPage) -> String {
        switch page {
        case .clipboard: return "doc.on.clipboard"
        case .jot: return "note.text"
        case .box: return "shippingbox.fill"
        case .chrono: return "timer"
        case .calendar: return "calendar"
        case .launcher: return "app.fill"
        case .bookmarks: return "globe"
        case .customCombined: return "square.grid.2x2.fill"
        }
    }

    private func floatingPagerView(pages: [IslandPage]) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<pages.count, id: \.self) { index in
                let page = pages[index]
                let isSelected = model.currentPage == index
                
                Button {
                    setPageFromCarousel(index)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.white : Color.white.opacity(0.15))
                            .frame(width: isSelected ? 30 : 24, height: isSelected ? 30 : 24)
                            .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0), radius: 3)
                        
                        Image(systemName: symbolForPage(page))
                            .font(.system(size: isSelected ? 12 : 10, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? Color.black : Color.white.opacity(0.8))
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .scaleEffect(isSelected ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.currentPage)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Group {
                if settings.pagerStyle2BackgroundEnabled {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(Capsule()))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func pageView(for page: IslandPage, contentAreaHeight: CGFloat) -> some View {
        switch page {
        case .clipboard:
            clipboardPage(contentAreaHeight: contentAreaHeight)
        case .jot:
            sidebarPage(contentAreaHeight: contentAreaHeight)
        case .box:
            boxPage(contentAreaHeight: contentAreaHeight)
        case .chrono:
            chronoPage(contentAreaHeight: contentAreaHeight)
        case .calendar:
            calendarPage(contentAreaHeight: contentAreaHeight)
        case .launcher:
            launcherPage(contentAreaHeight: contentAreaHeight)
        case .bookmarks:
            bookmarksPage(contentAreaHeight: contentAreaHeight)
        case .customCombined:
            customCombinedPage(contentAreaHeight: contentAreaHeight)
        }
    }

    private var horizontalPagingGesture: some Gesture {
        let pagesCount = activePages.count
        return DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 40 else { return }
                let nextPage = value.translation.width < 0
                    ? min(pagesCount - 1, model.currentPage + 1)
                    : max(0, model.currentPage - 1)
                setPageFromCarousel(nextPage)
            }
    }

    private func setPageFromCarousel(_ page: Int) {
        let pagesCount = activePages.count
        let nextPage = clamp(page, min: 0, max: pagesCount - 1)
        SwipeState.shared.carouselDragOffset = 0
        withAnimation(settings.carouselAnimation) {
            model.currentPage = nextPage
        }
    }

    private func unloadInactivePageState(activePage: Int) {
        let pages = activePages
        guard pages.indices.contains(activePage) else { return }
        let resolvedPage = pages[activePage]

        // Clipboard-only transient UI should reset when the clipboard page is inactive.
        if resolvedPage != .clipboard {
            highlightedClipboardID = nil
            clipboardTapFeedbackProgress = 0
        }

        // Cancel box preview work only when the Box page is inactive.
        // We deliberately do NOT trim the shared NSCache here — it has its own
        // count/cost limits and a memory-pressure handler.
        if resolvedPage != .box {
            BoxIconCache.shared.cancelQueuedPreviewLoads()
            selectedBoxFileIDs.removeAll()
        }

        if resolvedPage != .jot {
            isJotEditorFocused = false
        }
    }

    private func unloadCollapsedPageState() {
        unloadInactivePageState(activePage: -1)
        BoxIconCache.shared.cancelQueuedPreviewLoads()
    }

    func emptyDismissableScrollView<Content: View>(
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

    // MARK: - Drop Handling
    func handleNotchFileDrop(providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers: providers, openBoxPage: true)
    }

    func handleBoxDrop(providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers: providers, openBoxPage: false)
    }

    func handleFileDrop(providers: [NSItemProvider], openBoxPage: Bool) -> Bool {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.slimBoxDidReceiveDropThisSession = true
        }
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
            }

            if model.boxSlimModeActive {
                if !settings.boxSlimModeKeepOpen {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.hidePanel()
                    }
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.slimBoxWindow?.makeKeyAndOrderFront(nil)
                    }
                }
            } else if openBoxPage {
                if let idx = activePages.firstIndex(of: .box) {
                    model.currentPage = idx
                }
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
        let page = activePages.indices.contains(model.currentPage) ? activePages[model.currentPage] : .clipboard
        let edgeNotchWidth = settings.effectiveNotchWidth
        let alignmentOption = settings.titleAlignment(for: page)

        return Color.clear
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let notchLeft = (geo.size.width - edgeNotchWidth) / 2
                    let notchRight = (geo.size.width + edgeNotchWidth) / 2
                    
                    if page == .customCombined {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(settings.titleText(for: .bookmarks), systemImage: settings.titleSymbol(for: .bookmarks, fallback: "globe"))
                                .conditionalLabelStyle(showIcon: settings.showTitleIcon(for: .bookmarks))
                                .font(.system(size: settings.titleSize(for: .bookmarks), weight: .bold))
                                .foregroundColor(Color(settings.titleColor(for: .bookmarks)))
                            
                            if settings.showAddBookmarkButton {
                                Button {
                                    model.isAddSheetOpen = true
                                    isAddBookmarkPresented = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $isAddBookmarkPresented, arrowEdge: .bottom) {
                                    AddBookmarkSheet(isPresented: Binding(
                                        get: { self.isAddBookmarkPresented },
                                        set: { newValue in
                                            self.isAddBookmarkPresented = newValue
                                            if !newValue { self.model.isAddSheetOpen = false }
                                        }
                                    ), onAdd: { bookmark in
                                        model.bookmarkItems.append(bookmark)
                                        persistBookmarkItems(model.bookmarkItems)
                                        
                                        fetchFaviconBase64(for: bookmark.urlString) { base64 in
                                            if let base64 = base64 {
                                                DispatchQueue.main.async {
                                                    if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                                        model.bookmarkItems[idx].iconBase64 = base64
                                                        persistBookmarkItems(model.bookmarkItems)
                                                    }
                                                }
                                            }
                                        }
                                    })
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(x: notchRight + 12, y: 2)
                    } else {
                        let controls = HStack {
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
                                HStack(spacing: 12) {
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

                                    if model.activeJotID != nil {
                                        Button {
                                            exportActiveJot()
                                        } label: {
                                            Image(systemName: "square.and.arrow.down")
                                                .foregroundColor(.white)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            case .box:
                                EmptyView()
                            case .chrono:
                                EmptyView()
                            case .launcher:
                                if settings.showAddAppButton {
                                    Button {
                                        model.isAddSheetOpen = true
                                        isAddAppPresented = true
                                    } label: {
                                        Image(systemName: "plus")
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $isAddAppPresented, arrowEdge: .bottom) {
                                        AddAppSheet(isPresented: Binding(
                                            get: { self.isAddAppPresented },
                                            set: { newValue in
                                                self.isAddAppPresented = newValue
                                                if !newValue { self.model.isAddSheetOpen = false }
                                            }
                                        ), onAdd: { app in
                                            model.launcherApps.append(app)
                                            persistLauncherApps(model.launcherApps)
                                        })
                                    }
                                }
                            case .bookmarks:
                                if settings.showAddBookmarkButton {
                                    Button {
                                        model.isAddSheetOpen = true
                                        isAddBookmarkPresented = true
                                    } label: {
                                        Image(systemName: "plus")
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $isAddBookmarkPresented, arrowEdge: .bottom) {
                                        AddBookmarkSheet(isPresented: Binding(
                                            get: { self.isAddBookmarkPresented },
                                            set: { newValue in
                                                self.isAddBookmarkPresented = newValue
                                                if !newValue { self.model.isAddSheetOpen = false }
                                            }
                                        ), onAdd: { bookmark in
                                            model.bookmarkItems.append(bookmark)
                                            persistBookmarkItems(model.bookmarkItems)
                                            
                                            fetchFaviconBase64(for: bookmark.urlString) { base64 in
                                                if let base64 = base64 {
                                                    DispatchQueue.main.async {
                                                        if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                                            model.bookmarkItems[idx].iconBase64 = base64
                                                            persistBookmarkItems(model.bookmarkItems)
                                                        }
                                                    }
                                                }
                                            }
                                        })
                                    }
                                }
                            default:
                                EmptyView()
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        if alignmentOption == .left {
                            controls
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .offset(x: notchRight + 12, y: 2)
                        } else {
                            controls
                                .frame(width: max(0, notchLeft - 12), alignment: .trailing)
                                .offset(y: 2)
                        }
                    }
                }
            }
            .frame(width: islandWidth, height: islandHeight)
    }

    private func globalTitleOverlay(islandWidth: CGFloat, islandHeight: CGFloat) -> some View {
        let page = activePages.indices.contains(model.currentPage) ? activePages[model.currentPage] : .clipboard
        let edgeNotchWidth = settings.effectiveNotchWidth
        let alignmentOption = settings.titleAlignment(for: page)
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
        case .chrono:
            title = "Chrono"
            symbol = "timer"
        case .calendar:
            title = "Calendar"
            symbol = "calendar"
        case .launcher:
            title = "Launcher"
            symbol = "app.fill"
        case .bookmarks:
            title = "Bookmarks"
            symbol = "globe"
        default:
            title = ""
            symbol = "empty"
        }

        return Color.clear
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let notchLeft = (geo.size.width - edgeNotchWidth) / 2
                    let notchRight = (geo.size.width + edgeNotchWidth) / 2
                    
                    if page == .customCombined {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label(settings.titleText(for: .launcher), systemImage: settings.titleSymbol(for: .launcher, fallback: "app.fill"))
                                .conditionalLabelStyle(showIcon: settings.showTitleIcon(for: .launcher))
                                .font(.system(size: settings.titleSize(for: .launcher), weight: .bold))
                                .foregroundColor(Color(settings.titleColor(for: .launcher)))
                            
                            if settings.showAddAppButton {
                                Button {
                                    model.isAddSheetOpen = true
                                    isAddAppPresented = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $isAddAppPresented, arrowEdge: .bottom) {
                                    AddAppSheet(isPresented: Binding(
                                        get: { self.isAddAppPresented },
                                        set: { newValue in
                                            self.isAddAppPresented = newValue
                                            if !newValue { self.model.isAddSheetOpen = false }
                                        }
                                    ), onAdd: { app in
                                        model.launcherApps.append(app)
                                        persistLauncherApps(model.launcherApps)
                                    })
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: max(0, notchLeft - 12), alignment: .trailing)
                        .offset(y: 2)
                    } else {
                        if symbol != "empty" {
                            let titleView = header(title: title, symbol: symbol, page: page)
                                .fixedSize(horizontal: true, vertical: false)
                            
                            if alignmentOption == .left {
                                titleView
                                    .frame(width: max(0, notchLeft - 12), alignment: .trailing)
                                    .offset(y: 2)
                            } else {
                                titleView
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: notchRight + 12, y: 2)
                            }
                        }
                    }
                }
            }
            .frame(width: islandWidth, height: islandHeight)
    }

    private func header(title: String, symbol: String, page: IslandPage) -> some View {
        let displaySymbol = settings.titleSymbol(for: page, fallback: symbol)
        return Label(settings.titleText(for: page), systemImage: displaySymbol)
            .conditionalLabelStyle(showIcon: settings.showTitleIcon(for: page))
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

// MARK: - Reintegrated Settings

private enum SettingsSection: String, CaseIterable, Identifiable {
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

struct CarouselContainer<Content: View>: View {
    @ObservedObject var swipeState = SwipeState.shared
    let isSlimBoxInstance: Bool
    let currentPage: Int
    let panelWidth: CGFloat
    let content: Content

    init(isSlimBoxInstance: Bool, currentPage: Int, panelWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.isSlimBoxInstance = isSlimBoxInstance
        self.currentPage = currentPage
        self.panelWidth = panelWidth
        self.content = content()
    }

    var body: some View {
        content
            .modifier(CarouselTranslationEffect(offsetX: -CGFloat(isSlimBoxInstance ? 0 : currentPage) * panelWidth + swipeState.carouselDragOffset))
    }
}

private extension View {
    func nativeSettingsFormStyle() -> some View {
        formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    func conditionalLabelStyle(showIcon: Bool) -> some View {
        if showIcon {
            self.labelStyle(.titleAndIcon)
        } else {
            self.labelStyle(.titleOnly)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: NotchMenuModel
    @ObservedObject private var settings = AppSettings.shared
    let updater: SPUUpdater

    @State private var selection: SettingsSection? = .general
    @State private var selectedTitlePage: IslandPage = .clipboard
    @State private var isSettingsAddAppPresented = false
    @State private var isSettingsAddBookmarkPresented = false
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
                case .clip:
                    clipSettings
                case .jot:
                    jotSettings
                case .box:
                    boxSettings
                case .chrono:
                    chronoSettings
                case .calendar:
                    calendarSettings
                case .launcherBookmarks:
                    launcherBookmarksSettings
                case .sharing:
                    SharingSettingsView()
                case .advanced:
                    advancedSettings
                case .updates:
                    updatesSettings
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
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear {
            settings.showHoverPreviews = true
        }
        .onDisappear {
            settings.showHoverPreviews = false
        }
    }

    @ViewBuilder
    private func titleCustomizationSection(for page: IslandPage) -> some View {
        Section("Title Overrides") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Custom title text", text: pageCustomTitleBinding(page))
                    .textFieldStyle(.roundedBorder)
                Text("* for empty")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Toggle("Show title icon", isOn: pageShowTitleIconBinding(page))
            
            Picker("Alignment", selection: pageTitleAlignmentBinding(page)) {
                ForEach(TitleAlignmentOption.allCases, id: \.rawValue) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                Text("Size")
                Slider(value: pageTitleSizeBinding(page), in: settings.titleSizeRange, onEditingChanged: { isEditing in
                    setTitlePreviewFocus(isEditing: isEditing, page: page)
                })
                Text("\(Int(settings.titleSize(for: page)))")
                    .frame(width: 36, alignment: .trailing)
            }
            
            HStack {
                ColorPicker("Color", selection: pageTitleColorBinding(page))
                    .disabled(pageTitleUseAccentBinding(page).wrappedValue)
                Toggle("Use accent", isOn: pageTitleUseAccentBinding(page))
                    .toggleStyle(.switch)
            }
            
            HStack(spacing: 10) {
                TextField("SF Symbol", text: pageTitleSymbolBinding(page))
                    .textFieldStyle(.roundedBorder)
                Image(systemName: settings.titleSymbol(for: page, fallback: "textformat"))
                    .foregroundColor(Color(settings.titleColor(for: page)))
            }
            
            Button("Reset overrides") {
                resetTitleOverrides(for: page)
            }
            .buttonStyle(.bordered)
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
                            case .chrono: return "Chrono"
                            case .calendar: return "Calendar"
                            case .launcher: return "Launcher"
                            case .bookmarks: return "Bookmarks"
                            case .customCombined: return "Combined"
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

            Section("Page Layout & Ordering") {
                ReorderablePageList(settings: settings)
                    .padding(.vertical, 4)
            }

            Section("Open Method") {
                Picker("Open Method", selection: $settings.openMethod) {
                    Text("Hover to Open").tag(0)
                    Text("Tap to Open").tag(1)
                }
                .pickerStyle(.segmented)
                
                Text(settings.openMethod == 0 ? "Hover over the notch to expand the island." : "Hovering expands the notch slightly; tapping opens the island.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Pager Style") {
                Picker("Pager Style", selection: $settings.pagerStyle) {
                    Text("Style 1 (Dots)").tag(0)
                    Text("Style 2 (Circles)").tag(1)
                }
                .pickerStyle(.segmented)
                
                Text(settings.pagerStyle == 0 ? "Displays simple dot indicators on the left side of the notch." : "Displays glassmorphic floating circle indicators below the notch with page icons.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settings.pagerStyle == 1 {
                    Toggle("Show glass background", isOn: $settings.pagerStyle2BackgroundEnabled)
                }

                Toggle("Show pagers", isOn: $settings.showPagers)
            }
        }
        .nativeSettingsFormStyle()
    }

    private var clipSettings: some View {
        Form {
            Group {
                Section("Clipboard Configuration") {
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

                Section("Clipboard Layout") {
                    HStack {
                        Text("Columns")
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
                        Text("Text size")
                        Slider(value: $settings.clipTextSize, in: settings.clipTextSizeRange)
                        Text("\(Int(settings.clipTextSize))")
                            .frame(width: 36, alignment: .trailing)
                    }

                    HStack {
                        Text("File label size")
                        Slider(value: $settings.clipFileLabelSize, in: settings.clipFileLabelSizeRange)
                        Text("\(Int(settings.clipFileLabelSize))")
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                titleCustomizationSection(for: .clipboard)
            }
            .disabled(!settings.clipEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var jotSettings: some View {
        Form {
            Group {
                Section("Jot Layout") {
                    HStack {
                        Text("Columns")
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
                        Text("Text size")
                        Slider(value: $settings.jotTextSize, in: settings.jotTextSizeRange)
                        Text("\(Int(settings.jotTextSize))")
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                titleCustomizationSection(for: .jot)
            }
            .disabled(!settings.jotEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var boxSettings: some View {
        Form {
            Group {
                Section("Box Configuration") {
                    Toggle("Show file names in Box", isOn: $settings.showBoxFileNames)
                    
                    Toggle("Enable Slim Box Mode", isOn: $settings.boxSlimModeEnabled)
                        .help("Open a compact 180x260 view of the Box page on drag or when holding a file")
                    
                    if settings.boxSlimModeEnabled {
                        Picker("Trigger Method", selection: $settings.boxSlimModeTrigger) {
                            Text("Wiggle Mouse").tag(0)
                            Text("Hold Delay").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        if settings.boxSlimModeTrigger == 0 {
                            HStack {
                                Text("Wiggle Sensitivity")
                                Slider(value: $settings.boxSlimModeWiggleSensitivity, in: 1.0...10.0)
                                Text(String(format: "%.1f", settings.boxSlimModeWiggleSensitivity))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } else {
                            HStack {
                                Text("Slim Box Hold Delay")
                                Slider(value: $settings.boxSlimModeHoldDuration, in: 0.5...3.0)
                                Text(String(format: "%.1fs", settings.boxSlimModeHoldDuration))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        
                        Picker("Window Position", selection: $settings.boxSlimModePosition) {
                            Text("Default (Notch)").tag(0)
                            Text("Next to Mouse").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        Toggle("Keep Slim Box open after drop", isOn: $settings.boxSlimModeKeepOpen)
                        
                        Picker("Expand Direction", selection: $settings.boxSlimModeExpandDirection) {
                            Text("Horizontal").tag(0)
                            Text("Vertical").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        HStack {
                            Text("Max View Size")
                            Slider(value: $settings.boxSlimModeMaxViewSize, in: 1.0...10.0, step: 1.0)
                            Text("\(Int(settings.boxSlimModeMaxViewSize)) items")
                                .frame(width: 60, alignment: .trailing)
                        }
                        
                        HStack {
                            Text("Item Size")
                            Slider(value: Binding(
                                get: { settings.boxSlimModeItemWidth },
                                set: { newValue in
                                    settings.boxSlimModeItemWidth = newValue
                                    settings.boxSlimModeItemHeight = newValue
                                }
                            ), in: 40.0...160.0, step: 4.0)
                            Text("\(Int(settings.boxSlimModeItemWidth))px")
                                .frame(width: 50, alignment: .trailing)
                        }
                        
                    }
                }

                Section("Box Layout") {
                    HStack {
                        Text("Columns")
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
                        Text("File name size")
                        Slider(value: $settings.boxFileNameSize, in: settings.boxFileNameSizeRange)
                        Text("\(Int(settings.boxFileNameSize))")
                            .frame(width: 36, alignment: .trailing)
                    }
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

                titleCustomizationSection(for: .box)
            }
            .disabled(!settings.boxEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var chronoSettings: some View {
        Form {
            Group {
                Section("HUD Options") {
                    Toggle("Disable HUD when notch is closed", isOn: $settings.disableChronoHUD)
                }
                titleCustomizationSection(for: .chrono)
            }
            .disabled(!settings.chronoEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var calendarSettings: some View {
        Form {
            Group {
                Section("Calendar Access") {
                    CalendarPermissionStatusView()
                }
                
                Section("Layout Options") {
                    Picker("View Style", selection: $settings.calendarViewOption) {
                        Text("Month Grid").tag(0)
                        Text("Week Carousel").tag(1)
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Month Grid displays a full monthly layout with day details. Week Carousel displays a horizontal scrolling strip of the current week.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                titleCustomizationSection(for: .calendar)
            }
            .disabled(!settings.calendarEnabled)
        }
        .nativeSettingsFormStyle()
    }

    private var launcherBookmarksSettings: some View {
        Form {
            Group {
                Section("Actions Layout") {
                Picker("Layout mode", selection: $settings.customActionsLayoutOption) {
                    Text("Combined Page").tag(0)
                    Text("Separated Pages").tag(1)
                }
                .pickerStyle(.segmented)
                
                Text("Combined mode places Launcher and Bookmarks inside one scrolling page. Separated mode splits them into two individual pages.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Peeker Widget") {
                Text("Show custom actions at the bottom of the expanded island as a quick-access shortcut strip:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Show launcher apps in Peeker", isOn: $settings.showLauncherInPeeker)
                Toggle("Show bookmarks in Peeker", isOn: $settings.showBookmarksInPeeker)
                
                HStack {
                    Text("Item Size")
                    Slider(value: $settings.peekerSize, in: 10...36)
                    Text("\(Int(settings.peekerSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                .disabled(!settings.showLauncherInPeeker && !settings.showBookmarksInPeeker)
            }

            Section("Launcher Setup") {
                HStack {
                    Text("Columns")
                    Slider(
                        value: Binding(
                            get: { Double(settings.launcherColumns) },
                            set: { settings.launcherColumns = Int($0.rounded()) }
                        ),
                        in: 2...8
                    )
                    Text("\(settings.launcherColumns)")
                        .frame(width: 32, alignment: .trailing)
                }
                
                HStack {
                    Text("Icon Size")
                    Slider(value: $settings.launcherIconSize, in: 24...64)
                    Text("\(Int(settings.launcherIconSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                HStack {
                    Text("Text Size")
                    Slider(value: $settings.launcherTextSize, in: 8...16)
                    Text("\(Int(settings.launcherTextSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                Toggle("Show application names", isOn: $settings.launcherShowName)
                
                Picker("Display layout", selection: $settings.launcherDisplayMode) {
                    Text("Grid").tag(0)
                    Text("List").tag(1)
                }
                .pickerStyle(.segmented)
                
                Toggle("Show 'Add Application' button in island", isOn: $settings.showAddAppButton)
            }

            Section("Manage Applications") {
                List {
                    ForEach(model.launcherApps) { app in
                        HStack {
                            CustomAppIconView(appPath: app.path, size: 20)
                            Text(app.name)
                                .font(.body)
                            Spacer()
                            Button {
                                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                                    var updated = model.launcherApps
                                    updated[idx].isPinned.toggle()
                                    model.launcherApps = updated
                                    persistLauncherApps(updated)
                                }
                            } label: {
                                Image(systemName: app.isPinned ? "pin.fill" : "pin")
                                    .foregroundColor(app.isPinned ? Color(settings.accentColor) : .secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .help(app.isPinned ? "Unpin from Peeker" : "Pin to Peeker")

                            Button {
                                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                                    model.launcherApps.remove(at: idx)
                                    persistLauncherApps(model.launcherApps)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                
                Button("Add Application...") {
                    isSettingsAddAppPresented = true
                }
                .popover(isPresented: $isSettingsAddAppPresented, arrowEdge: .bottom) {
                    AddAppSheet(isPresented: $isSettingsAddAppPresented, onAdd: { app in
                        model.launcherApps.append(app)
                        persistLauncherApps(model.launcherApps)
                    })
                }
            }

            if settings.customActionsLayoutOption != 0 {
                titleCustomizationSection(for: .launcher)
            }

            Section("Bookmarks Setup") {
                HStack {
                    Text("Columns")
                    Slider(
                        value: Binding(
                            get: { Double(settings.bookmarkColumns) },
                            set: { settings.bookmarkColumns = Int($0.rounded()) }
                        ),
                        in: 2...8
                    )
                    Text("\(settings.bookmarkColumns)")
                        .frame(width: 32, alignment: .trailing)
                }

                HStack {
                    Text("Icon Size")
                    Slider(value: $settings.bookmarkIconSize, in: 24...64)
                    Text("\(Int(settings.bookmarkIconSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                HStack {
                    Text("Text Size")
                    Slider(value: $settings.bookmarkTextSize, in: 8...16)
                    Text("\(Int(settings.bookmarkTextSize)) pt")
                        .frame(width: 48, alignment: .trailing)
                }
                
                Toggle("Show bookmark names", isOn: $settings.bookmarkShowName)
                
                Picker("Display layout", selection: $settings.bookmarkDisplayMode) {
                    Text("Grid").tag(0)
                    Text("List").tag(1)
                }
                .pickerStyle(.segmented)
                
                Toggle("Show 'Add Bookmark' button in island", isOn: $settings.showAddBookmarkButton)
            }

            Section("Manage Bookmarks") {
                List {
                    ForEach(model.bookmarkItems) { bookmark in
                        HStack {
                            BookmarkIconView(bookmark: bookmark, size: 20, accentColor: Color(settings.accentColor))
                            VStack(alignment: .leading, spacing: 2) {
                                  Text(bookmark.name)
                                      .font(.body)
                                  Text(bookmark.urlString)
                                      .font(.caption)
                                      .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                    var updated = model.bookmarkItems
                                    updated[idx].isPinned.toggle()
                                    model.bookmarkItems = updated
                                    persistBookmarkItems(updated)
                                }
                            } label: {
                                Image(systemName: bookmark.isPinned ? "pin.fill" : "pin")
                                    .foregroundColor(bookmark.isPinned ? Color(settings.accentColor) : .secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .help(bookmark.isPinned ? "Unpin from Peeker" : "Pin to Peeker")

                            Button {
                                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                    model.bookmarkItems.remove(at: idx)
                                    persistBookmarkItems(model.bookmarkItems)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                
                Button("Add Bookmark...") {
                    isSettingsAddBookmarkPresented = true
                }
                .popover(isPresented: $isSettingsAddBookmarkPresented, arrowEdge: .bottom) {
                    AddBookmarkSheet(isPresented: $isSettingsAddBookmarkPresented, onAdd: { bookmark in
                        model.bookmarkItems.append(bookmark)
                        persistBookmarkItems(model.bookmarkItems)
                        fetchFaviconBase64(for: bookmark.urlString) { base64 in
                            if let base64 = base64 {
                                DispatchQueue.main.async {
                                    if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                        model.bookmarkItems[idx].iconBase64 = base64
                                        persistBookmarkItems(model.bookmarkItems)
                                    }
                                }
                            }
                        }
                    })
                }
            }

            if settings.customActionsLayoutOption != 0 {
                titleCustomizationSection(for: .bookmarks)
            } else {
                titleCustomizationSection(for: .customCombined)
            }
            }
            .disabled(settings.customActionsLayoutOption == 0 ? !settings.launcherEnabled : (!settings.launcherEnabled && !settings.bookmarksEnabled))
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

    private var updatesSettings: some View {
        Form {
            Section("Current Version") {
                HStack(spacing: 12) {
                    if let icon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                        Text("Apollo")
                            .font(.headline)
                        Text("Version \(version) (\(build))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Updates") {
                CheckForUpdatesView(updater: updater)
                
                Toggle("Automatically check for updates on startup", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
            }
        }
        .nativeSettingsFormStyle()
    }

    private func pageCustomTitleBinding(_ page: IslandPage) -> Binding<String> {
        Binding(
            get: {
                switch page {
                case .clipboard: return settings.clipboardCustomTitle ?? ""
                case .jot: return settings.jotCustomTitle ?? ""
                case .box: return settings.boxCustomTitle ?? ""
                case .chrono: return settings.chronoCustomTitle ?? ""
                case .calendar: return settings.calendarCustomTitle ?? ""
                case .launcher: return settings.launcherCustomTitle ?? ""
                case .bookmarks: return settings.bookmarksCustomTitle ?? ""
                case .customCombined: return settings.combinedCustomTitle ?? ""
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmed.isEmpty ? nil : trimmed
                switch page {
                case .clipboard: settings.clipboardCustomTitle = value
                case .jot: settings.jotCustomTitle = value
                case .box: settings.boxCustomTitle = value
                case .chrono: settings.chronoCustomTitle = value
                case .calendar: settings.calendarCustomTitle = value
                case .launcher: settings.launcherCustomTitle = value
                case .bookmarks: settings.bookmarksCustomTitle = value
                case .customCombined: settings.combinedCustomTitle = value
                }
            }
        )
    }

    private func pageShowTitleIconBinding(_ page: IslandPage) -> Binding<Bool> {
        Binding(
            get: {
                switch page {
                case .clipboard: return settings.clipboardShowTitleIcon ?? true
                case .jot: return settings.jotShowTitleIcon ?? true
                case .box: return settings.boxShowTitleIcon ?? true
                case .chrono: return settings.chronoShowTitleIcon ?? true
                case .calendar: return settings.calendarShowTitleIcon ?? true
                case .launcher: return settings.launcherShowTitleIcon ?? true
                case .bookmarks: return settings.bookmarksShowTitleIcon ?? true
                case .customCombined: return settings.combinedShowTitleIcon ?? true
                }
            },
            set: { newValue in
                switch page {
                case .clipboard: settings.clipboardShowTitleIcon = newValue
                case .jot: settings.jotShowTitleIcon = newValue
                case .box: settings.boxShowTitleIcon = newValue
                case .chrono: settings.chronoShowTitleIcon = newValue
                case .calendar: settings.calendarShowTitleIcon = newValue
                case .launcher: settings.launcherShowTitleIcon = newValue
                case .bookmarks: settings.bookmarksShowTitleIcon = newValue
                case .customCombined: settings.combinedShowTitleIcon = newValue
                }
            }
        )
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
        case .chrono: return "Chrono"
        default: return "Custom"
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
                case .chrono:
                    settings.chronoTitleAlignment = newValue
                case .calendar:
                    settings.calendarTitleAlignment = newValue
                case .launcher:
                    settings.launcherTitleAlignment = newValue
                case .bookmarks:
                    settings.bookmarksTitleAlignment = newValue
                case .customCombined:
                    settings.combinedTitleAlignment = newValue
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
                case .chrono:
                    settings.chronoTitleSize = newValue
                case .calendar:
                    settings.calendarTitleSize = newValue
                case .launcher:
                    settings.launcherTitleSize = newValue
                case .bookmarks:
                    settings.bookmarksTitleSize = newValue
                case .customCombined:
                    settings.combinedTitleSize = newValue
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
                case .chrono:
                    settings.chronoTitleColor = NSColor(newValue)
                case .calendar:
                    settings.calendarTitleColor = NSColor(newValue)
                case .launcher:
                    settings.launcherTitleColor = NSColor(newValue)
                case .bookmarks:
                    settings.bookmarksTitleColor = NSColor(newValue)
                case .customCombined:
                    settings.combinedTitleColor = NSColor(newValue)
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
                case .chrono:
                    return settings.chronoTitleUseAccent ?? false
                case .calendar:
                    return settings.calendarTitleUseAccent ?? false
                case .launcher:
                    return settings.launcherTitleUseAccent ?? false
                case .bookmarks:
                    return settings.bookmarksTitleUseAccent ?? false
                case .customCombined:
                    return settings.combinedTitleUseAccent ?? false
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
                case .chrono:
                    settings.chronoTitleUseAccent = newValue
                case .calendar:
                    settings.calendarTitleUseAccent = newValue
                case .launcher:
                    settings.launcherTitleUseAccent = newValue
                case .bookmarks:
                    settings.bookmarksTitleUseAccent = newValue
                case .customCombined:
                    settings.combinedTitleUseAccent = newValue
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
                case .chrono:
                    return settings.chronoTitleIconName ?? ""
                case .calendar:
                    return settings.calendarTitleIconName ?? ""
                case .launcher:
                    return settings.launcherTitleIconName ?? ""
                case .bookmarks:
                    return settings.bookmarksTitleIconName ?? ""
                case .customCombined:
                    return settings.combinedTitleIconName ?? ""
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
                case .chrono:
                    settings.chronoTitleIconName = value
                case .calendar:
                    settings.calendarTitleIconName = value
                case .launcher:
                    settings.launcherTitleIconName = value
                case .bookmarks:
                    settings.bookmarksTitleIconName = value
                case .customCombined:
                    settings.combinedTitleIconName = value
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
        case .chrono:
            settings.chronoTitleAlignment = nil
            settings.chronoTitleSize = nil
            settings.chronoTitleIconName = nil
            settings.chronoTitleUseAccent = nil
            settings.chronoTitleColor = nil
        case .calendar:
            settings.calendarTitleAlignment = nil
            settings.calendarTitleSize = nil
            settings.calendarTitleIconName = nil
            settings.calendarTitleUseAccent = nil
            settings.calendarTitleColor = nil
        case .launcher:
            settings.launcherTitleAlignment = nil
            settings.launcherTitleSize = nil
            settings.launcherTitleIconName = nil
            settings.launcherTitleUseAccent = nil
            settings.launcherTitleColor = nil
        case .bookmarks:
            settings.bookmarksTitleAlignment = nil
            settings.bookmarksTitleSize = nil
            settings.bookmarksTitleIconName = nil
            settings.bookmarksTitleUseAccent = nil
            settings.bookmarksTitleColor = nil
        case .customCombined:
            settings.combinedTitleAlignment = nil
            settings.combinedTitleSize = nil
            settings.combinedTitleIconName = nil
            settings.combinedTitleUseAccent = nil
            settings.combinedTitleColor = nil
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

extension UnifiedNotchContainer {
    func calendarPage(contentAreaHeight: CGFloat) -> some View {
        CalendarPageContent(
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            calendarViewOption: settings.calendarViewOption
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    func launcherPage(contentAreaHeight: CGFloat) -> some View {
        LauncherPageContent(
            apps: model.launcherApps,
            displayMode: settings.launcherDisplayMode,
            columnsCount: settings.launcherColumns,
            iconSize: settings.launcherIconSize,
            textSize: settings.launcherTextSize,
            showName: settings.launcherShowName,
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            showHeader: false,
            onRemove: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    model.launcherApps.remove(at: idx)
                    persistLauncherApps(model.launcherApps)
                }
            },
            onAdd: { app in
                model.launcherApps.append(app)
                persistLauncherApps(model.launcherApps)
            },
            onTogglePin: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated[idx].isPinned.toggle()
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    func bookmarksPage(contentAreaHeight: CGFloat) -> some View {
        BookmarksPageContent(
            bookmarks: model.bookmarkItems,
            displayMode: settings.bookmarkDisplayMode,
            columnsCount: settings.bookmarkColumns,
            iconSize: settings.bookmarkIconSize,
            textSize: settings.bookmarkTextSize,
            showName: settings.bookmarkShowName,
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            showHeader: false,
            onRemove: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    model.bookmarkItems.remove(at: idx)
                    persistBookmarkItems(model.bookmarkItems)
                }
            },
            onAdd: { bookmark in
                model.bookmarkItems.append(bookmark)
                persistBookmarkItems(model.bookmarkItems)
                
                fetchFaviconBase64(for: bookmark.urlString) { base64 in
                    if let base64 = base64 {
                        DispatchQueue.main.async {
                            if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                model.bookmarkItems[idx].iconBase64 = base64
                                persistBookmarkItems(model.bookmarkItems)
                            }
                        }
                    }
                }
            },
            onTogglePin: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].isPinned.toggle()
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }

    func customCombinedPage(contentAreaHeight: CGFloat) -> some View {
        CombinedActionsPageContent(
            model: model,
            apps: model.launcherApps,
            bookmarks: model.bookmarkItems,
            launcherMode: settings.launcherDisplayMode,
            bookmarkMode: settings.bookmarkDisplayMode,
            launcherColumns: settings.launcherColumns,
            bookmarkColumns: settings.bookmarkColumns,
            launcherIconSize: settings.launcherIconSize,
            launcherTextSize: settings.launcherTextSize,
            launcherShowName: settings.launcherShowName,
            bookmarkIconSize: settings.bookmarkIconSize,
            bookmarkTextSize: settings.bookmarkTextSize,
            bookmarkShowName: settings.bookmarkShowName,
            width: scaledPanelWidth(for: settings),
            height: max(1, contentAreaHeight - pageTopContentInset),
            accentColor: Color(settings.accentColor),
            onRemoveApp: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    model.launcherApps.remove(at: idx)
                    persistLauncherApps(model.launcherApps)
                }
            },
            onAddApp: { app in
                model.launcherApps.append(app)
                persistLauncherApps(model.launcherApps)
            },
            onTogglePinApp: { app in
                if let idx = model.launcherApps.firstIndex(where: { $0.id == app.id }) {
                    var updated = model.launcherApps
                    updated[idx].isPinned.toggle()
                    model.launcherApps = updated
                    persistLauncherApps(updated)
                }
            },
            onRemoveBookmark: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    model.bookmarkItems.remove(at: idx)
                    persistBookmarkItems(model.bookmarkItems)
                }
            },
            onAddBookmark: { bookmark in
                model.bookmarkItems.append(bookmark)
                persistBookmarkItems(model.bookmarkItems)
                
                fetchFaviconBase64(for: bookmark.urlString) { base64 in
                    if let base64 = base64 {
                        DispatchQueue.main.async {
                            if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                                model.bookmarkItems[idx].iconBase64 = base64
                                persistBookmarkItems(model.bookmarkItems)
                            }
                        }
                    }
                }
            },
            onTogglePinBookmark: { bookmark in
                if let idx = model.bookmarkItems.firstIndex(where: { $0.id == bookmark.id }) {
                    var updated = model.bookmarkItems
                    updated[idx].isPinned.toggle()
                    model.bookmarkItems = updated
                    persistBookmarkItems(updated)
                }
            }
        )
        .equatable()
        .padding(.top, pageTopContentInset)
    }
}

// MARK: - Calendar Permission helper View
struct CalendarPermissionStatusView: View {
    @ObservedObject private var manager = CalendarManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if manager.permissionGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Calendar permission is granted.")
                        .font(.body)
                } else if manager.permissionChecked {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar access is denied.")
                            .font(.body)
                            .fontWeight(.semibold)
                        Text("Please enable Calendar permissions for Apollo in System Settings -> Privacy & Security -> Calendars.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.gray)
                    Text("Calendar permission has not been requested yet.")
                        .font(.body)
                }
            }
            
            if !manager.permissionGranted {
                Button("Request Calendar Access") {
                    manager.requestPermission { granted in
                        manager.checkPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            manager.checkPermission()
        }
    }
}

extension View {
    @ViewBuilder
    func conditionalClip(clipAll: Bool, cornerRadius: CGFloat) -> some View {
        if clipAll {
            self.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.clipShape(BottomRoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - VisualEffectView for Glassmorphism
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - ReorderablePageList for Settings Layout Customization
struct ReorderablePageList: View {
    @ObservedObject var settings: AppSettings
    @State private var draggedItem: Int?
    @State private var localOrder: [Int] = []

    var body: some View {
        VStack(spacing: 6) {
            ForEach(localOrder, id: \.self) { rawValue in
                if shouldShowPageInLayout(rawValue) {
                    rowView(for: rawValue)
                }
            }
        }
        .onAppear {
            localOrder = settings.pageOrder
        }
        .onChange(of: settings.pageOrder) { newOrder in
            if localOrder != newOrder {
                localOrder = newOrder
            }
        }
    }

    private func shouldShowPageInLayout(_ rawValue: Int) -> Bool {
        if rawValue == 6 {
            // Bookmarks is only shown separately in layout if customActionsLayoutOption is Separated (1).
            // In Combined mode (0), Launcher (5) represents "Launcher & Bookmarks", and rawValue 6 is hidden/unused.
            return settings.customActionsLayoutOption == 1
        }
        return true
    }

    private func pageName(for rawValue: Int) -> String {
        switch rawValue {
        case 0: return "Clipboard"
        case 1: return "Jot"
        case 2: return "Box"
        case 3: return "Chrono"
        case 4: return "Calendar"
        case 5:
            return settings.customActionsLayoutOption == 0 ? "Launcher & Bookmarks" : "Launcher"
        case 6: return "Bookmarks"
        default: return "Unknown"
        }
    }

    private func pageIcon(for rawValue: Int) -> String {
        switch rawValue {
        case 0: return "doc.on.clipboard"
        case 1: return "note.text"
        case 2: return "shippingbox.fill"
        case 3: return "timer"
        case 4: return "calendar"
        case 5: return "app.fill"
        case 6: return "globe"
        default: return "square.grid.2x2"
        }
    }

    private func isEnabledBinding(for rawValue: Int) -> Binding<Bool> {
        switch rawValue {
        case 0: return $settings.clipEnabled
        case 1: return $settings.jotEnabled
        case 2: return $settings.boxEnabled
        case 3: return $settings.chronoEnabled
        case 4: return $settings.calendarEnabled
        case 5: return $settings.launcherEnabled
        case 6: return $settings.bookmarksEnabled
        default:
            return .constant(false)
        }
    }

    private func rowView(for rawValue: Int) -> some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 4)

            // Icon
            Image(systemName: pageIcon(for: rawValue))
                .foregroundColor(isEnabledBinding(for: rawValue).wrappedValue ? Color(settings.accentColor) : .secondary)
                .frame(width: 18)

            // Name
            Text(pageName(for: rawValue))
                .font(.body)
                .foregroundColor(isEnabledBinding(for: rawValue).wrappedValue ? .primary : .secondary)

            Spacer()

            // Toggle switch
            Toggle("", isOn: isEnabledBinding(for: rawValue))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(draggedItem == rawValue ? 0.08 : 0.02))
        )
        .contentShape(Rectangle())
        .onDrag {
            self.draggedItem = rawValue
            return NSItemProvider(object: String(rawValue) as NSString)
        }
        .onDrop(of: [.text], delegate: PageDropDelegate(item: rawValue, list: $localOrder, draggedItem: $draggedItem) {
            settings.pageOrder = localOrder
        })
    }
}

// MARK: - Drop Delegate for Reordering Layout Items
struct PageDropDelegate: DropDelegate {
    let item: Int
    @Binding var list: [Int]
    @Binding var draggedItem: Int?
    var onCommit: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        onCommit()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        if draggedItem != item {
            guard let from = list.firstIndex(of: draggedItem),
                  let to = list.firstIndex(of: item) else { return }
            if list[to] != draggedItem {
                withAnimation(.easeInOut(duration: 0.2)) {
                    list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
}
