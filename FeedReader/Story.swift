//
//  Story.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class Story: NSObject, NSSecureCoding {
    
    // MARK: - NSSecureCoding
    
    /// Required for NSSecureCoding — prevents deserialization of unexpected classes.
    static var supportsSecureCoding: Bool { return true }
    
    // MARK: - Properties
    
    var title: String
    var photo: UIImage?
    var body: String
    var link: String
    var imagePath: String?
    
    /// Allowed URL schemes for links and images. Restricts to safe web protocols
    /// to prevent javascript:, file:, data:, or custom scheme injection.
    private static let allowedSchemes: Set<String> = ["https", "http"]
    
    // MARK: - Archiving Paths
    
    static var DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
    static var ArchiveURL = DocumentsDirectory.appendingPathComponent("stories")

    
    // MARK: - Types
    
    struct PropertyKey {
        static let titleKey = "title"
        static let photoKey = "photo"
        static let descriptionKey = "description"
        static let linkKey = "link"
        static let imagePathKey = "imagePath"
    }
    
    // MARK: - Initialization
    
    init?(title: String, photo: UIImage?, description: String, link: String, imagePath: String? = nil) {
        
        // Sanitize HTML from description before storing
        let sanitized = Story.stripHTML(description)
        
        // Initialize stored properties.
        self.title = title
        self.photo = photo
        self.body = sanitized
        self.link = link
        
        // Only accept image paths with safe URL schemes (https/http)
        if let path = imagePath, Story.isSafeURL(path) {
            self.imagePath = path
        } else {
            self.imagePath = nil
        }
        
        super.init()
        
        // Initialization should fail if there is no name or if the link is invalid.
        if title.isEmpty || body.isEmpty || !Story.isSafeURL(link) {
            return nil
        }
    }
    
    /// Validates that a URL string uses only allowed schemes (https/http).
    /// Rejects javascript:, file:, data:, tel:, and custom URL schemes
    /// to prevent injection and redirect attacks.
    static func isSafeURL(_ urlString: String?) -> Bool {
        guard let urlString = urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return allowedSchemes.contains(scheme)
    }
    
    /// Strips HTML tags from a string to prevent rendering of injected markup.
    /// Uses a simple regex approach suitable for RSS description sanitization.
    /// Entity decoding is done in a single pass for efficiency instead of
    /// chaining multiple replacingOccurrences calls (which each allocate a
    /// new intermediate string).
    static func stripHTML(_ html: String) -> String {
        // Remove HTML tags
        let stripped = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        // Single-pass entity decoding — scan for '&' and replace known entities
        // in one traversal instead of 6 separate string scans.
        return decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Decodes common HTML entities in a single pass through the string.
    /// Avoids creating 6 intermediate String copies from chained
    /// replacingOccurrences calls.
    private static let entityMap: [(entity: String, replacement: Character)] = [
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&nbsp;", " "),
    ]
    
    private static func decodeHTMLEntities(_ input: String) -> String {
        // Fast path: if no ampersand, nothing to decode
        guard input.contains("&") else { return input }
        
        var result = ""
        result.reserveCapacity(input.count)
        var i = input.startIndex
        
        while i < input.endIndex {
            if input[i] == "&" {
                var matched = false
                let remaining = input[i...]
                for (entity, replacement) in entityMap {
                    if remaining.hasPrefix(entity) {
                        result.append(replacement)
                        i = input.index(i, offsetBy: entity.count)
                        matched = true
                        break
                    }
                }
                if !matched {
                    result.append(input[i])
                    i = input.index(after: i)
                }
            } else {
                result.append(input[i])
                i = input.index(after: i)
            }
        }
        
        return result
    }
    
    // MARK: - NSCoding
    
    func encode(with aCoder: NSCoder) {
        
        aCoder.encode(title, forKey: PropertyKey.titleKey)
        aCoder.encode(photo, forKey: PropertyKey.photoKey)
        aCoder.encode(body, forKey: PropertyKey.descriptionKey)
        aCoder.encode(link, forKey: PropertyKey.linkKey)
        aCoder.encode(imagePath, forKey: PropertyKey.imagePathKey)
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        
        guard let title = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.titleKey) as String?,
              let description = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.descriptionKey) as String?,
              let link = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.linkKey) as String? else {
            return nil
        }
        
        // Because photo is an optional property of Story, use conditional cast.
        let photo = aDecoder.decodeObject(of: UIImage.self, forKey: PropertyKey.photoKey)
        let imagePath = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.imagePathKey) as String?
        
        // Must call designated initializer.
        self.init(title: title, photo: photo, description: description, link: link, imagePath: imagePath)
    }
}




