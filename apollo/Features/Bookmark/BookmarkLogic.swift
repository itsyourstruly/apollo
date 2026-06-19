
import SwiftUI

final class BookmarkIconCache {
    static let shared = BookmarkIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSRecursiveLock()
    
    private init() {
        cache.countLimit = 100
    }
    
    func cachedImage(forBase64 base64: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: base64 as NSString)
    }
    
    func loadImageAsync(forBase64 base64: String, completion: @escaping (NSImage?) -> Void) {
        lock.lock()
        let nsKey = base64 as NSString
        if let cached = cache.object(forKey: nsKey) {
            lock.unlock()
            completion(cached)
            return
        }
        lock.unlock()
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            let img = autoreleasepool { () -> NSImage? in
                guard let data = Data(base64Encoded: base64) else { return nil }
                return NSImage(data: data)
            }
            
            if let img = img {
                self.lock.lock()
                self.cache.setObject(img, forKey: nsKey)
                self.lock.unlock()
                
                DispatchQueue.main.async {
                    completion(img)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
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
