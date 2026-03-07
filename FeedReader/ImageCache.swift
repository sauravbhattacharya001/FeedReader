//
//  ImageCache.swift
//  FeedReader
//
//  Extracted from StoryTableViewController to provide a reusable,
//  thread-safe image cache with async loading. Wraps NSCache for
//  automatic memory-pressure eviction.
//

import UIKit
import ImageIO
import CryptoKit

class ImageCache {

    // MARK: - Singleton

    static let shared = ImageCache()

    // MARK: - Properties

    /// In-memory image cache. NSCache automatically evicts entries
    /// under memory pressure — no manual cleanup needed.
    private let cache = NSCache<NSString, UIImage>()

    /// Dedicated URL session for image loading with constrained concurrency.
    /// Limits simultaneous connections to avoid saturating the network
    /// during prefetch bursts (e.g., scrolling through 50+ stories).
    private let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15
        config.urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024,
                                   diskCapacity: 50 * 1024 * 1024)
        return URLSession(configuration: config)
    }()

    /// Tracks in-flight prefetch URLs to avoid duplicate requests.
    private var inflightURLs = Set<String>()
    private let inflightLock = NSLock()

    /// Serial queue for disk I/O operations — keeps file writes off the main thread.
    private let diskQueue = DispatchQueue(label: "com.feedreader.imagecache.disk", qos: .utility)

    /// Directory for persisted thumbnail images on disk.
    private static let diskCacheDirectory: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = cacheDir.appendingPathComponent("ImageThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Maximum number of files in the disk cache. Oldest files are evicted
    /// when this limit is exceeded.
    private static let maxDiskCacheFiles = 500

    /// Maximum age (in seconds) for disk-cached thumbnails before eviction (7 days).
    private static let maxDiskCacheAge: TimeInterval = 7 * 24 * 60 * 60

    private init() {
        // Evict cache on memory warning
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        // Evict stale disk cache entries on launch (async, non-blocking)
        diskQueue.async { [weak self] in
            self?.evictStaleDiskEntries()
        }
    }

    // MARK: - Public API

    /// Returns a cached image for the given URL string, or nil.
    func image(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    /// Stores an image in the cache.
    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    /// Maximum pixel dimension for cached thumbnail images.
    /// Images are downsampled at decode time to avoid holding
    /// full-resolution bitmaps in memory (often 3000×2000+ for
    /// news article photos). A 200pt limit covers typical table
    /// view cells at 3× scale (600px).
    static let maxThumbnailPixels: CGFloat = 600

    /// Downsample raw image data to a thumbnail without decoding
    /// the full image into memory first. Uses ImageIO to decode
    /// directly at the target size, saving ~10× memory for typical
    /// news images.
    private static func downsampledImage(data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    /// Loads an image from URL, returning it via the completion handler.
    /// Checks: 1) in-memory cache, 2) disk cache, 3) network fetch.
    /// Persists downloaded thumbnails to disk for fast cold starts.
    ///
    /// - Parameters:
    ///   - urlString: The image URL string. Must pass `Story.isSafeURL` check.
    ///   - completion: Called on the main thread with the loaded image, or nil on failure.
    func loadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        // Check safety
        guard Story.isSafeURL(urlString), let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        // 1. Return from memory cache immediately
        if let cached = image(forKey: urlString) {
            completion(cached)
            return
        }

        // 2. Check disk cache (async to avoid blocking main thread)
        let diskPath = ImageCache.diskPath(for: urlString)
        diskQueue.async { [weak self] in
            if let data = try? Data(contentsOf: diskPath),
               let diskImage = ImageCache.downsampledImage(data: data) {
                self?.setImage(diskImage, forKey: urlString)
                DispatchQueue.main.async { completion(diskImage) }
                return
            }

            // 3. Fetch from network
            self?.imageSession.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = ImageCache.downsampledImage(data: data) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                self?.setImage(image, forKey: urlString)
                // Persist downsampled thumbnail to disk
                self?.persistToDisk(image: image, for: urlString)
                DispatchQueue.main.async { completion(image) }
            }.resume()
        }
    }

    /// Pre-fetches images for the given URL strings, warming the cache.
    /// Uses a concurrency-limited session and deduplicates in-flight requests
    /// to avoid saturating the network when scrolling quickly.
    func prefetch(urls: [String]) {
        for urlString in urls {
            guard Story.isSafeURL(urlString),
                  image(forKey: urlString) == nil,
                  let url = URL(string: urlString) else { continue }

            // Skip if already in flight
            inflightLock.lock()
            let alreadyInFlight = !inflightURLs.insert(urlString).inserted
            inflightLock.unlock()
            if alreadyInFlight { continue }

            imageSession.dataTask(with: url) { [weak self] data, _, _ in
                self?.inflightLock.lock()
                self?.inflightURLs.remove(urlString)
                self?.inflightLock.unlock()

                guard let data = data, let image = ImageCache.downsampledImage(data: data) else { return }
                self?.setImage(image, forKey: urlString)
                self?.persistToDisk(image: image, for: urlString)
            }.resume()
        }
    }

    /// Cancel all pending prefetch requests (e.g., on rapid scroll direction change).
    func cancelPrefetches() {
        imageSession.getTasksWithCompletionHandler { dataTasks, _, _ in
            for task in dataTasks {
                task.cancel()
            }
        }
        inflightLock.lock()
        inflightURLs.removeAll()
        inflightLock.unlock()
    }

    /// Clears all cached images (memory and disk).
    @objc func clearCache() {
        cache.removeAllObjects()
        diskQueue.async {
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: ImageCache.diskCacheDirectory,
                                                        includingPropertiesForKeys: nil) {
                for file in files { try? fm.removeItem(at: file) }
            }
        }
    }

    // MARK: - Disk Cache Helpers

    /// Compute a stable file URL for a given image URL string using SHA-256.
    /// Previous implementation used djb2 (UInt64) which has a high collision
    /// probability at scale — two different URLs mapping to the same file
    /// means stale/wrong images served silently.
    private static func diskPath(for urlString: String) -> URL {
        let data = Data(urlString.utf8)
        let digest = SHA256.hash(data: data)
        let hash = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent("\(hash).jpg")
    }

    /// Persist a downsampled image to the disk cache as JPEG.
    private func persistToDisk(image: UIImage, for urlString: String) {
        diskQueue.async {
            let path = ImageCache.diskPath(for: urlString)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: path, options: .atomic)
            }
        }
    }

    /// Remove disk cache entries older than `maxDiskCacheAge` or exceeding
    /// `maxDiskCacheFiles`. Called once on init.
    private func evictStaleDiskEntries() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: ImageCache.diskCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let cutoff = Date().addingTimeInterval(-ImageCache.maxDiskCacheAge)
        var kept: [(url: URL, date: Date)] = []

        for file in files {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate {
                if modDate < cutoff {
                    try? fm.removeItem(at: file)
                } else {
                    kept.append((file, modDate))
                }
            }
        }

        // Enforce file count limit — remove oldest first
        if kept.count > ImageCache.maxDiskCacheFiles {
            let sorted = kept.sorted { $0.date < $1.date }
            let excess = sorted.prefix(kept.count - ImageCache.maxDiskCacheFiles)
            for entry in excess {
                try? fm.removeItem(at: entry.url)
            }
        }
    }
}
