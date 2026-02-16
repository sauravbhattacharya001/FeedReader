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

        // Fetch asynchronously
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.setImage(image, forKey: urlString)
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    /// Pre-fetches images for the given URL strings, warming the cache.
    func prefetch(urls: [String]) {
        for urlString in urls {
            guard Story.isSafeURL(urlString),
                  image(forKey: urlString) == nil,
                  let url = URL(string: urlString) else { continue }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                self?.setImage(image, forKey: urlString)
            }.resume()
        }
    }

    /// Clears all cached images.
    @objc func clearCache() {
        cache.removeAllObjects()
    }
}
