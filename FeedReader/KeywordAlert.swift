//
//  KeywordAlert.swift
//  FeedReader
//
//  Data model for keyword-based alerts. While ContentFilter mutes unwanted
//  stories, KeywordAlert highlights stories that match topics the user cares
//  about — ensuring important articles aren't missed in a busy feed.
//

import Foundation

/// Priority level for keyword alerts, affecting sort order and visual treatment.
enum AlertPriority: String, Codable {
    case low
    case medium
    case high
    
    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

/// A keyword-based alert rule that flags matching stories for the user's attention.
class KeywordAlert: NSObject, NSSecureCoding, Codable {
    
    // MARK: - NSSecureCoding
    
    static var supportsSecureCoding: Bool { return true }
    
    struct PropertyKey {
        static let idKey = "keywordAlertId"
        static let keywordKey = "keywordAlertKeyword"
        static let isActiveKey = "keywordAlertIsActive"
        static let priorityKey = "keywordAlertPriority"
        static let matchScopeKey = "keywordAlertMatchScope"
        static let createdAtKey = "keywordAlertCreatedAt"
        static let matchCountKey = "keywordAlertMatchCount"
        static let colorHexKey = "keywordAlertColorHex"
    }
    
    // MARK: - Types
    
    enum MatchScope: String, Codable {
        case title
        case body
        case both
    }
    
    // MARK: - Limits
    
    static let maxKeywordLength = 200
    static let maxAlerts = 50
    
    // MARK: - Properties
    
    var id: String
    var keyword: String
    var isActive: Bool
    var priority: AlertPriority
    var matchScope: MatchScope
    var createdAt: Date
    var matchCount: Int
    /// Optional hex color for visual tagging (e.g. "#FF6B6B").
    var colorHex: String?
    
    // MARK: - Initialization
    
    init?(id: String = UUID().uuidString, keyword: String, isActive: Bool = true,
          priority: AlertPriority = .medium, matchScope: MatchScope = .both,
          createdAt: Date = Date(), matchCount: Int = 0, colorHex: String? = nil) {
        
        let trimmed = String(keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(KeywordAlert.maxKeywordLength))
        guard !trimmed.isEmpty else { return nil }
        
        self.id = id
        self.keyword = trimmed
        self.isActive = isActive
        self.priority = priority
        self.matchScope = matchScope
        self.createdAt = createdAt
        self.matchCount = matchCount
        self.colorHex = colorHex
        
        super.init()
    }
    
    // MARK: - Matching
    
    /// Check if a story matches this alert's keyword.
    func matches(title: String, body: String) -> Bool {
        guard isActive else { return false }
        let lowerKeyword = keyword.lowercased()
        
        switch matchScope {
        case .title:
            return title.lowercased().contains(lowerKeyword)
        case .body:
            return body.lowercased().contains(lowerKeyword)
        case .both:
            return title.lowercased().contains(lowerKeyword)
                || body.lowercased().contains(lowerKeyword)
        }
    }
    
    // MARK: - NSCoding
    
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: PropertyKey.idKey)
        coder.encode(keyword, forKey: PropertyKey.keywordKey)
        coder.encode(isActive, forKey: PropertyKey.isActiveKey)
        coder.encode(priority.rawValue, forKey: PropertyKey.priorityKey)
        coder.encode(matchScope.rawValue, forKey: PropertyKey.matchScopeKey)
        coder.encode(createdAt as NSDate, forKey: PropertyKey.createdAtKey)
        coder.encode(matchCount, forKey: PropertyKey.matchCountKey)
        coder.encode(colorHex as NSString?, forKey: PropertyKey.colorHexKey)
    }
    
    required convenience init?(coder decoder: NSCoder) {
        guard let id = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.idKey) as String?,
              let keyword = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.keywordKey) as String? else {
            return nil
        }
        
        let isActive = decoder.decodeBool(forKey: PropertyKey.isActiveKey)
        let priorityRaw = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.priorityKey) as String? ?? "medium"
        let scopeRaw = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.matchScopeKey) as String? ?? "both"
        let createdAt = decoder.decodeObject(of: NSDate.self, forKey: PropertyKey.createdAtKey) as Date? ?? Date()
        let matchCount = decoder.decodeInteger(forKey: PropertyKey.matchCountKey)
        let colorHex = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.colorHexKey) as String?
        
        let priority = AlertPriority(rawValue: priorityRaw) ?? .medium
        let matchScope = MatchScope(rawValue: scopeRaw) ?? .both
        
        self.init(id: id, keyword: keyword, isActive: isActive,
                  priority: priority, matchScope: matchScope,
                  createdAt: createdAt, matchCount: matchCount, colorHex: colorHex)
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, keyword, isActive, priority, matchScope, createdAt, matchCount, colorHex
    }
}
