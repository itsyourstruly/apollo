
import SwiftUI

public let maxStoredClipboardTextLength = 512

public func cappedClipboardText(_ text: String?, limit: Int = maxStoredClipboardTextLength) -> String? {
    guard let text = text else { return nil }
    let capped: Substring
    if text.count > limit * 2 {
        capped = text.prefix(limit * 2)
    } else {
        capped = text[...]
    }
    let trimmed = capped.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    
    let finalSubstring = trimmed.prefix(limit)
    // Force a fresh memory allocation to sever the original massive StringStorage buffer
    var severed = ""
    severed.reserveCapacity(finalSubstring.count)
    severed.append(contentsOf: finalSubstring)
    return severed
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

func loadClipboardHistory() -> [ClipboardEntry] {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: AppStorageKey.clipboardHistory),
       let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
        return entries.map { $0.normalizedForLightweightStorage() }
    }
    let savedTexts = defaults.stringArray(forKey: AppStorageKey.clipboardHistory) ?? []
    return savedTexts.map { ClipboardEntry(text: $0) }
}

func persistClipboardHistory(_ entries: [ClipboardEntry]) {
    PersistenceWriteCoordinator.shared.scheduleClipboardHistory(entries.map { $0.normalizedForLightweightStorage() })
}
