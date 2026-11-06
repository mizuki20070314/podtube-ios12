import UIKit
import ImageIO

/// Downloads thumbnails/avatars, decodes them off the main thread at a bounded pixel size and caches them.
final class ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let cache = NSCache<NSString, UIImage>()
    private let decodeQueue = DispatchQueue(label: "podtube.image.decode", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var waiting: [String: [(UIImage?) -> Void]] = [:]

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024, diskPath: "podtube-images")
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func clearCaches() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// The decoded image if it is in memory already; nothing is requested otherwise.
    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        return cache.object(forKey: "\(url.absoluteString)#\(Int(maxPixel.rounded()))" as NSString)
    }

    func load(_ url: URL, maxPixel: CGFloat, completion: @escaping (UIImage?) -> Void) {
        let px = Int(maxPixel.rounded())
        let key = "\(url.absoluteString)#\(px)"
        if let hit = cache.object(forKey: key as NSString) {
            completion(hit)
            return
        }
        lock.lock()
        if waiting[key] != nil {
            waiting[key]?.append(completion)
            lock.unlock()
            return
        }
        waiting[key] = [completion]
        lock.unlock()

        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad
        session.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self else { return }
            self.decodeQueue.async {
                var image: UIImage?
                if let data = data { image = ImageLoader.decode(data, maxPixel: px) }
                if let img = image {
                    let cost = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
                    self.cache.setObject(img, forKey: key as NSString, cost: cost)
                }
                self.lock.lock()
                let callbacks = self.waiting.removeValue(forKey: key) ?? []
                self.lock.unlock()
                DispatchQueue.main.async {
                    for cb in callbacks { cb(image) }
                }
            }
        }.resume()
    }

    static func decode(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private var imageKeyAssoc: UInt8 = 0

extension UIImageView {
    /// Loads `urlString` asynchronously; a reused view ignores results of an older request.
    func setRemote(_ urlString: String?, maxPixel: CGFloat, fade: Bool = true) {
        let key = urlString ?? ""
        objc_setAssociatedObject(self, &imageKeyAssoc, key, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        image = nil
        guard !key.isEmpty, let url = URL(string: key) else { return }
        var finishedSynchronously = true
        ImageLoader.shared.load(url, maxPixel: maxPixel) { [weak self] img in
            guard let self = self, let img = img else { return }
            if (objc_getAssociatedObject(self, &imageKeyAssoc) as? String) != key { return }
            self.image = img
            if fade && !finishedSynchronously {
                self.alpha = 0
                UIView.animate(withDuration: 0.18) { self.alpha = 1 }
            }
        }
        finishedSynchronously = false
    }
}
