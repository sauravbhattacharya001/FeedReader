//
//  ContentFilter.swift
//  FeedReader
//
//  Content filter model for muting unwanted stories by keyword/phrase.
//

import Foundation

/// A keyword-based content filter that can mute (hide) stories matching the keyword.
class ContentFilter: NSObject, NSSecureCoding, Codable {
    
    // MARK: - NSSecureCoding
    
    static var supportsSecureCoding: Bool { return true }
    
    // MARK: - Types
    
    enum MatchScope: String, Codable {
        case title
        case body
        case both
    }
    
    enum MatchMode: String, Codable {
        case contains
        case exactWord
        case regex
    }
    
    struct PropertyKey {
        static let idKey = "contentFilterId"
        static let keywordKey = "contentFilterKeyword"
        static let isActiveKey = "contentFilterIsActive"
        static let matchScopeKey = "contentFilterMatchScope"
        static let matchModeKey = "contentFilterMatchMode"
        static let createdAtKey = "contentFilterCreatedAt"
        static let mutedCountKey = "contentFilterMutedCount"
    }
    
    // MARK: - Limits
    
    static let maxKeywordLength = 200
    
    // MARK: - Properties
    
    var id: String
    var keyword: String
    var isActive: Bool
    var matchScope: MatchScope
    var matchMode: MatchMode
    var createdAt: Date
    var mutedCount: Int
    
    // MARK: - Initialization
    
    init?(id: String = UUID().uuidString, keyword: String, isActive: Bool = true,
          matchScope: MatchScope = .both, matchMode: MatchMode = .contains,
          createdAt: Date = Date(), mutedCount: Int = 0) {
        
        let trimmed = String(keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(ContentFilter.maxKeywordLength))
        guard !trimmed.isEmpty else { return nil }
        
        // For regex mode, validate the pattern compiles
        if matchMode == .regex {
            do {
                _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            } catch {
                return nil
            }
        }
        
        self.id = id
        self.keyword = trimmed
        self.isActive = isActive
        self.matchScope = matchScope
        self.matchMode = matchMode
        self.createdAt = createdAt
        self.mutedCount = mutedCount
        
        super.init()
    }
    
    // MARK: - NSCoding
    
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: PropertyKey.idKey)
        coder.encode(keyword, forKey: PropertyKey.keywordKey)
        coder.encode(isActive, forKey: PropertyKey.isActiveKey)
        coder.encode(matchScope.rawValue, forKey: PropertyKey.matchScopeKey)
        coder.encode(matchMode.rawValue, forKey: PropertyKey.matchModeKey)
        coder.encode(createdAt as NSDate, forKey: PropertyKey.createdAtKey)
        coder.encode(mutedCount, forKey: PropertyKey.mutedCountKey)
    }
    
    required convenience init?(coder decoder: NSCoder) {
        guard let id = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.idKey) as String?,
              let keyword = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.keywordKey) as String?,
              let scopeRaw = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.matchScopeKey) as String?,
              let modeRaw = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.matchModeKey) as String? else {
            return nil
        }
        
        let isActive = decoder.decodeBool(forKey: PropertyKey.isActiveKey)
        let createdAt = decoder.decodeObject(of: NSDate.self, forKey: PropertyKey.createdAtKey) as Date? ?? Date()
        let mutedCount = decoder.decodeInteger(forKey: PropertyKey.mutedCountKey)
        let matchScope = MatchScope(rawValue: scopeRaw) ?? .both
        let matchMode = MatchMode(rawValue: modeRaw) ?? .contains
        
        self.init(id: id, keyword: keyword, isActive: isActive,
                  matchScope: matchScope, matchMode: matchMode,
                  createdAt: createdAt, mutedCount: mutedCount)
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, keyword, isActive, matchScope, matchMode, createdAt, mutedCount
    }
}
