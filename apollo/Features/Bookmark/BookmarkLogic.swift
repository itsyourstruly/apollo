
import SwiftUI

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
        
        return autoreleasepool {
            if let data = Data(base64Encoded: base64),
               let img = NSImage(data: data) {
                cache.setObject(img, forKey: nsKey)
                return img
            }
            return nil
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
    }
}
