//
//  ArticleHighlight.swift
//  FeedReader
//
//  A highlighted text snippet saved from an article.
//  Supports color-coded labels and NSSecureCoding for persistence.
//

import Foundation

/// Color label for a highlight.
enum HighlightColor: Int {
    case yellow = 0
    case green = 1
    case blue = 2
    case pink = 3
    case orange = 4
    
    var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .pink:   return "Pink"
        case .orange: return "Orange"
        }
    }
}

/// A highlighted text snippet from an article.
class ArticleHighlight: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    
    /// Unique identifier for this highlight.
    let id: String
    
    /// The article's link URL.
    let articleLink: String
    
    /// The article's title (for display).
    let articleTitle: String
    
    /// The highlighted text snippet.
    let selectedText: String
    
    /// Color label for the highlight.
    var color: HighlightColor
    
    /// Optional user annotation on this highlight.
    var annotation: String?
    
    /// When the highlight was created.
    let createdDate: Date
    
    /// Maximum length for selected text.
    static let maxTextLength = 2000
    
    /// Maximum length for annotation.
    static let maxAnnotationLength = 500
    
    init?(articleLink: String, articleTitle: String, selectedText: String,
          color: HighlightColor = .yellow, annotation: String? = nil,
          id: String = UUID().uuidString, createdDate: Date = Date()) {
        
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !articleLink.isEmpty else { return nil }
        
        self.id = id
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.selectedText = String(trimmed.prefix(ArticleHighlight.maxTextLength))
        self.color = color
        self.createdDate = createdDate
        
        if let ann = annotation?.trimmingCharacters(in: .whitespacesAndNewlines), !ann.isEmpty {
            self.annotation = String(ann.prefix(ArticleHighlight.maxAnnotationLength))
        }
        
        super.init()
    }
    
    // MARK: - NSSecureCoding
    
    private enum CodingKeys {
        static let id = "highlightId"
        static let articleLink = "highlightArticleLink"
        static let articleTitle = "highlightArticleTitle"
        static let selectedText = "highlightSelectedText"
        static let color = "highlightColor"
        static let annotation = "highlightAnnotation"
        static let createdDate = "highlightCreatedDate"
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: CodingKeys.id)
        coder.encode(articleLink as NSString, forKey: CodingKeys.articleLink)
        coder.encode(articleTitle as NSString, forKey: CodingKeys.articleTitle)
        coder.encode(selectedText as NSString, forKey: CodingKeys.selectedText)
        coder.encode(color.rawValue, forKey: CodingKeys.color)
        coder.encode(annotation as NSString?, forKey: CodingKeys.annotation)
        coder.encode(createdDate as NSDate, forKey: CodingKeys.createdDate)
    }
    
    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: CodingKeys.id) as String?,
              let articleLink = coder.decodeObject(of: NSString.self, forKey: CodingKeys.articleLink) as String?,
              let articleTitle = coder.decodeObject(of: NSString.self, forKey: CodingKeys.articleTitle) as String?,
              let selectedText = coder.decodeObject(of: NSString.self, forKey: CodingKeys.selectedText) as String?,
              let createdDate = coder.decodeObject(of: NSDate.self, forKey: CodingKeys.createdDate) as Date? else {
            return nil
        }
        
        self.id = id
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.selectedText = selectedText
        self.color = HighlightColor(rawValue: coder.decodeInteger(forKey: CodingKeys.color)) ?? .yellow
        self.annotation = coder.decodeObject(of: NSString.self, forKey: CodingKeys.annotation) as String?
        self.createdDate = createdDate
        super.init()
    }
}
