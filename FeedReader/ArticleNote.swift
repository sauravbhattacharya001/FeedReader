//
//  ArticleNote.swift
//  FeedReader
//
//  A personal note attached to an article.
//  Supports NSSecureCoding for persistence via NSKeyedArchiver.
//

import Foundation

/// A personal note attached to an article.
class ArticleNote: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    
    /// The article's link URL (unique identifier).
    let articleLink: String
    
    /// The article's title (for display when article is unavailable).
    let articleTitle: String
    
    /// The user's note text.
    var text: String
    
    /// When the note was created.
    let createdDate: Date
    
    /// When the note was last modified.
    var modifiedDate: Date
    
    init(articleLink: String, articleTitle: String, text: String,
         createdDate: Date = Date(), modifiedDate: Date = Date()) {
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.text = text
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        super.init()
    }
    
    // MARK: - NSSecureCoding
    
    private enum CodingKeys {
        static let articleLink = "articleLink"
        static let articleTitle = "articleTitle"
        static let text = "text"
        static let createdDate = "createdDate"
        static let modifiedDate = "modifiedDate"
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(articleLink as NSString, forKey: CodingKeys.articleLink)
        coder.encode(articleTitle as NSString, forKey: CodingKeys.articleTitle)
        coder.encode(text as NSString, forKey: CodingKeys.text)
        coder.encode(createdDate as NSDate, forKey: CodingKeys.createdDate)
        coder.encode(modifiedDate as NSDate, forKey: CodingKeys.modifiedDate)
    }
    
    required init?(coder: NSCoder) {
        guard let articleLink = coder.decodeObject(of: NSString.self, forKey: CodingKeys.articleLink) as String?,
              let articleTitle = coder.decodeObject(of: NSString.self, forKey: CodingKeys.articleTitle) as String?,
              let text = coder.decodeObject(of: NSString.self, forKey: CodingKeys.text) as String?,
              let createdDate = coder.decodeObject(of: NSDate.self, forKey: CodingKeys.createdDate) as Date?,
              let modifiedDate = coder.decodeObject(of: NSDate.self, forKey: CodingKeys.modifiedDate) as Date? else {
            return nil
        }
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.text = text
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        super.init()
    }
}
