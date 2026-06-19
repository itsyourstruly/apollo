
import SwiftUI
import AVFoundation
import CoreMedia

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
    private var activeOperations = [UUID: Operation]()

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
        return autoreleasepool {
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
        return autoreleasepool {
            let options: CFDictionary = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
            let thumbnailOptions: CFDictionary = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        }
    }

    private func videoThumbnailImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        return autoreleasepool { () -> NSImage? in
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

    @discardableResult
    func requestDisplayImage(for url: URL, targetSize: CGFloat, completion: @escaping (NSImage) -> Void) -> UUID {
        let safeTarget = max(24, targetSize)
        let requestID = UUID()
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
            self.stateLock.lock()
            self.activeOperations.removeValue(forKey: requestID)
            self.stateLock.unlock()
        }
        self.stateLock.lock()
        self.activeOperations[requestID] = operation
        self.stateLock.unlock()
        previewLoadQueue.addOperation(operation)
        return requestID
    }
    
    func cancelRequest(_ id: UUID) {
        stateLock.lock()
        if let op = activeOperations.removeValue(forKey: id) {
            op.cancel()
        }
        stateLock.unlock()
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

    func invalidate(url: URL) {
        let key = url as NSURL
        iconCache.removeObject(forKey: key)
        
        stateLock.lock()
        knownIconKeys.remove(key)
        
        let pathPrefix = url.path + "|"
        let pKeys = knownPreviewKeys.filter { $0.hasPrefix(pathPrefix) }
        for k in pKeys {
            previewCache.removeObject(forKey: k as NSString)
            knownPreviewKeys.remove(k)
        }
        
        let fKeys = failedPreviewKeys.filter { $0.hasPrefix(pathPrefix) }
        for k in fKeys {
            failedPreviewKeys.remove(k)
        }
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
