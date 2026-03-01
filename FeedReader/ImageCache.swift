//
//  ImageCache.swift
//  FeedReader
//
//  Extracted from StoryTableViewController to provide a reusable,
//  thread-safe image cache with async loading. Wraps NSCache for
//  automatic memory-pressure eviction.
//

import UIKit

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

    private init() {
        // Evict cache on memory warning
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
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

    /// Loads an image from URL, returning it via the completion handler.
    /// If already cached, returns immediately on the calling queue.
    /// Otherwise fetches asynchronously and caches the result.
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

        // Return cached image immediately
        if let cached = image(forKey: urlString) {
            completion(cached)
            return
        }

        // Fetch asynchronously via the constrained session
        imageSession.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.setImage(image, forKey: urlString)
            DispatchQueue.main.async { completion(image) }
        }.resume()
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

                guard let data = data, let image = UIImage(data: data) else { return }
                self?.setImage(image, forKey: urlString)
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

    /// Clears all cached images.
    @objc func clearCache() {
        cache.removeAllObjects()
    }
}
