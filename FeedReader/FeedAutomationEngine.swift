//
//  FeedAutomationEngine.swift
//  FeedReader
//
//  Rule-based article automation engine. Users define rules with
//  conditions (title/body/feed/author matches) and actions (tag, star,
//  mark read, move to collection, notify). Rules are evaluated in
//  priority order against incoming articles. Supports AND/OR condition
//  groups, regex and keyword matching, feed-scoped rules, rate limiting,
//  dry-run mode, execution history, and JSON import/export.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let automationRulesDidChange = Notification.Name("AutomationRulesDidChangeNotification")
    static let automationRuleTriggered = Notification.Name("AutomationRuleTriggeredNotification")
}

// MARK: - Condition Types

/// How a text field should be matched.
enum MatchMode: String, Codable {
    case contains
    case exactMatch
    case startsWith
    case endsWith
    case regex
    
    func matches(_ text: String, pattern: String) -> Bool {
        let lowerText = text.lowercased()
        let lowerPattern = pattern.lowercased()
        
        switch self {
        case .contains:
            return lowerText.contains(lowerPattern)
        case .exactMatch:
            return lowerText == lowerPattern
        case .startsWith:
            return lowerText.hasPrefix(lowerPattern)
        case .endsWith:
            return lowerText.hasSuffix(lowerPattern)
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            // ReDoS protection: cap the text length to prevent catastrophic
            // backtracking on adversarial input. Article titles/bodies can be
            // arbitrarily long; capping at 10,000 chars is generous for any
            // reasonable feed content while preventing worst-case O(2^n)
            // backtracking on patterns like (a+)+$ against long strings.
            let safeText: String
            if text.count > 10_000 {
                safeText = String(text.prefix(10_000))
            } else {
                safeText = text
            }
            let range = NSRange(safeText.startIndex..<safeText.endIndex, in: safeText)
            return regex.firstMatch(in: safeText, range: range) != nil
        }
    }
}

/// Which article field to match against.
enum ConditionField: String, Codable {
    case title
    case body
    case link
    case feedName
    case any  // matches against title + body + feedName
}

/// A single condition that checks one field of an article.
struct AutomationCondition: Codable, Equatable {
    let field: ConditionField
    let mode: MatchMode
    let pattern: String
    var negate: Bool
    
    init(field: ConditionField, mode: MatchMode = .contains, pattern: String, negate: Bool = false) {
        self.field = field
        self.mode = mode
        self.pattern = pattern
        self.negate = negate
    }
    
    /// Evaluate this condition against a story.
    func evaluate(title: String, body: String, link: String, feedName: String) -> Bool {
        let fields: [String]
        switch field {
        case .title:    fields = [title]
        case .body:     fields = [body]
        case .link:     fields = [link]
        case .feedName: fields = [feedName]
        case .any:      fields = [title, body, feedName]
        }
        
        let matched = fields.contains { mode.matches($0, pattern: pattern) }
        return negate ? !matched : matched
    }
}

/// How multiple conditions combine within a group.
enum ConditionLogic: String, Codable {
    case all  // AND — every condition must match
    case any  // OR — at least one must match
}

/// A group of conditions with AND/OR logic.
struct ConditionGroup: Codable, Equatable {
    var logic: ConditionLogic
    var conditions: [AutomationCondition]
    
    init(logic: ConditionLogic = .all, conditions: [AutomationCondition]) {
        self.logic = logic
        self.conditions = conditions
    }
    
    func evaluate(title: String, body: String, link: String, feedName: String) -> Bool {
        guard !conditions.isEmpty else { return false }
        
        switch logic {
        case .all:
            return conditions.allSatisfy { $0.evaluate(title: title, body: body, link: link, feedName: feedName) }
        case .any:
            return conditions.contains { $0.evaluate(title: title, body: body, link: link, feedName: feedName) }
        }
    }
}

// MARK: - Action Types

/// What to do when a rule matches an article.
enum AutomationAction: Codable, Equatable {
    case addTag(String)
    case markRead
    case markStarred
    case moveToCollection(String)
    case setHighPriority
    case notify(String)  // notification message template
    case markHidden      // hide from main feed
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type, value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .addTag(let tag):
            try container.encode("addTag", forKey: .type)
            try container.encode(tag, forKey: .value)
        case .markRead:
            try container.encode("markRead", forKey: .type)
        case .markStarred:
            try container.encode("markStarred", forKey: .type)
        case .moveToCollection(let name):
            try container.encode("moveToCollection", forKey: .type)
            try container.encode(name, forKey: .value)
        case .setHighPriority:
            try container.encode("setHighPriority", forKey: .type)
        case .notify(let msg):
            try container.encode("notify", forKey: .type)
            try container.encode(msg, forKey: .value)
        case .markHidden:
            try container.encode("markHidden", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "addTag":
            let value = try container.decode(String.self, forKey: .value)
            self = .addTag(value)
        case "markRead":
            self = .markRead
        case "markStarred":
            self = .markStarred
        case "moveToCollection":
            let value = try container.decode(String.self, forKey: .value)
            self = .moveToCollection(value)
        case "setHighPriority":
            self = .setHighPriority
        case "notify":
            let value = try container.decode(String.self, forKey: .value)
            self = .notify(value)
        case "markHidden":
            self = .markHidden
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown action type: \(type)")
        }
    }
}

// MARK: - Execution Record

/// Record of a single rule execution against an article.
struct AutomationExecution: Codable {
    let ruleId: String
    let ruleName: String
    let articleTitle: String
    let articleLink: String
    let actions: [AutomationAction]
    let timestamp: Date
    let dryRun: Bool
}

// MARK: - Automation Rule

/// A complete automation rule: conditions + actions + metadata.
struct AutomationRule: Codable, Equatable {
    let id: String
    var name: String
    var conditionGroup: ConditionGroup
    var actions: [AutomationAction]
    var isEnabled: Bool
    var priority: Int  // lower = higher priority (evaluated first)
    var stopProcessing: Bool  // if true, skip remaining rules after this one matches
    var feedScope: [String]?  // nil = all feeds; otherwise only these feed names
    var createdAt: Date
    var lastTriggeredAt: Date?
    var triggerCount: Int
    var maxTriggersPerDay: Int?  // rate limit; nil = unlimited
    
    /// Daily trigger timestamps for rate limiting.
    var dailyTriggers: [Date]
    
    init(name: String,
         conditions: [AutomationCondition],
         logic: ConditionLogic = .all,
         actions: [AutomationAction],
         priority: Int = 100,
         stopProcessing: Bool = false,
         feedScope: [String]? = nil,
         maxTriggersPerDay: Int? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.conditionGroup = ConditionGroup(logic: logic, conditions: conditions)
        self.actions = actions
        self.isEnabled = true
        self.priority = priority
        self.stopProcessing = stopProcessing
        self.feedScope = feedScope
        self.createdAt = Date()
        self.lastTriggeredAt = nil
        self.triggerCount = 0
        self.maxTriggersPerDay = maxTriggersPerDay
        self.dailyTriggers = []
    }
    
    static func == (lhs: AutomationRule, rhs: AutomationRule) -> Bool {
        return lhs.id == rhs.id
    }
    
    /// Check if this rule has exceeded its daily trigger limit.
    func isRateLimited(now: Date = Date()) -> Bool {
        guard let maxPerDay = maxTriggersPerDay else { return false }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let todayCount = dailyTriggers.filter { $0 >= todayStart }.count
        return todayCount >= maxPerDay
    }
    
    /// Prune daily triggers older than today.
    mutating func pruneDailyTriggers(now: Date = Date()) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        dailyTriggers = dailyTriggers.filter { $0 >= todayStart }
    }
}

// MARK: - Processing Result

/// Result of processing a single article through the automation engine.
struct AutomationResult {
    let articleTitle: String
    let articleLink: String
    let matchedRules: [AutomationRule]
    let executedActions: [AutomationAction]
    let skippedRules: [(rule: AutomationRule, reason: String)]
}

// MARK: - FeedAutomationEngine

/// Rule-based automation engine for processing articles.
///
/// Evaluates articles against user-defined rules in priority order,
/// executing actions (tag, star, mark read, etc.) on matches. Supports
/// AND/OR condition logic, regex matching, feed scoping, rate limiting,
/// dry-run mode, and execution history.
class FeedAutomationEngine {
    
    // MARK: - Properties
    
    private(set) var rules: [AutomationRule] = []
    private(set) var executionHistory: [AutomationExecution] = []
    
    /// Maximum execution history entries to retain.
    var maxHistorySize: Int = 1000
    
    // MARK: - Rule Management
    
    /// Add a new rule. Returns the rule ID.
    @discardableResult
    func addRule(_ rule: AutomationRule) -> String {
        guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        guard !rule.conditionGroup.conditions.isEmpty else {
            return ""
        }
        guard !rule.actions.isEmpty else {
            return ""
        }
        rules.append(rule)
        rules.sort { $0.priority < $1.priority }
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
        return rule.id
    }
    
    /// Remove a rule by ID. Returns true if found and removed.
    @discardableResult
    func removeRule(id: String) -> Bool {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return false
        }
        rules.remove(at: index)
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
        return true
    }
    
    /// Update an existing rule. Returns true if found and updated.
    @discardableResult
    func updateRule(_ updated: AutomationRule) -> Bool {
        guard let index = rules.firstIndex(where: { $0.id == updated.id }) else {
            return false
        }
        rules[index] = updated
        rules.sort { $0.priority < $1.priority }
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
        return true
    }
    
    /// Enable or disable a rule by ID.
    @discardableResult
    func setRuleEnabled(id: String, enabled: Bool) -> Bool {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return false
        }
        rules[index].isEnabled = enabled
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
        return true
    }
    
    /// Get a rule by ID.
    func getRule(id: String) -> AutomationRule? {
        return rules.first { $0.id == id }
    }
    
    /// Get all enabled rules sorted by priority.
    func enabledRules() -> [AutomationRule] {
        return rules.filter { $0.isEnabled }.sorted { $0.priority < $1.priority }
    }
    
    /// Reorder a rule's priority. Adjusts other rules as needed.
    func moveRule(id: String, toPriority newPriority: Int) -> Bool {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return false
        }
        rules[index].priority = newPriority
        rules.sort { $0.priority < $1.priority }
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
        return true
    }
    
    /// Duplicate a rule with a new name. Returns the new rule's ID.
    func duplicateRule(id: String, newName: String? = nil) -> String? {
        guard let original = getRule(id: id) else { return nil }
        var copy = AutomationRule(
            name: newName ?? "\(original.name) (Copy)",
            conditions: original.conditionGroup.conditions,
            logic: original.conditionGroup.logic,
            actions: original.actions,
            priority: original.priority + 1,
            stopProcessing: original.stopProcessing,
            feedScope: original.feedScope,
            maxTriggersPerDay: original.maxTriggersPerDay
        )
        copy.isEnabled = false  // start disabled so user can review
        return addRule(copy).isEmpty ? nil : copy.id
    }
    
    // MARK: - Article Processing
    
    /// Process a single article through all enabled rules.
    ///
    /// Returns the result describing which rules matched and what actions
    /// were collected. In dry-run mode, no state is mutated (trigger
    /// counts, history) but the result still shows what would happen.
    func processArticle(title: String, body: String, link: String,
                        feedName: String, dryRun: Bool = false,
                        now: Date = Date()) -> AutomationResult {
        var matchedRules: [AutomationRule] = []
        var executedActions: [AutomationAction] = []
        var skippedRules: [(rule: AutomationRule, reason: String)] = []
        var actionSet = Set<String>()  // dedup identical actions
        
        let activeRules = enabledRules()
        
        for rule in activeRules {
            // Feed scope check
            if let scope = rule.feedScope, !scope.isEmpty {
                let lowerFeed = feedName.lowercased()
                if !scope.contains(where: { $0.lowercased() == lowerFeed }) {
                    skippedRules.append((rule, "feed not in scope"))
                    continue
                }
            }
            
            // Rate limit check
            if rule.isRateLimited(now: now) {
                skippedRules.append((rule, "daily trigger limit reached"))
                continue
            }
            
            // Evaluate conditions
            let matched = rule.conditionGroup.evaluate(
                title: title, body: body, link: link, feedName: feedName
            )
            
            if matched {
                matchedRules.append(rule)
                
                // Collect unique actions
                for action in rule.actions {
                    let key = actionKey(action)
                    if !actionSet.contains(key) {
                        actionSet.insert(key)
                        executedActions.append(action)
                    }
                }
                
                if !dryRun {
                    // Update rule stats
                    if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                        rules[index].triggerCount += 1
                        rules[index].lastTriggeredAt = now
                        rules[index].dailyTriggers.append(now)
                        rules[index].pruneDailyTriggers(now: now)
                    }
                    
                    // Record execution
                    let execution = AutomationExecution(
                        ruleId: rule.id,
                        ruleName: rule.name,
                        articleTitle: title,
                        articleLink: link,
                        actions: rule.actions,
                        timestamp: now,
                        dryRun: false
                    )
                    addExecution(execution)
                    
                    NotificationCenter.default.post(
                        name: .automationRuleTriggered,
                        object: nil,
                        userInfo: ["ruleId": rule.id, "articleTitle": title]
                    )
                }
                
                // Stop processing if rule says so
                if rule.stopProcessing {
                    // Mark remaining rules as skipped
                    let remainingIndex = activeRules.firstIndex(where: { $0.id == rule.id })!
                    for i in (remainingIndex + 1)..<activeRules.count {
                        skippedRules.append((activeRules[i], "stopped by rule '\(rule.name)'"))
                    }
                    break
                }
            }
        }
        
        return AutomationResult(
            articleTitle: title,
            articleLink: link,
            matchedRules: matchedRules,
            executedActions: executedActions,
            skippedRules: skippedRules
        )
    }
    
    /// Process multiple articles in batch. Returns results for each.
    func processArticles(_ articles: [(title: String, body: String, link: String, feedName: String)],
                         dryRun: Bool = false, now: Date = Date()) -> [AutomationResult] {
        return articles.map { article in
            processArticle(title: article.title, body: article.body,
                          link: article.link, feedName: article.feedName,
                          dryRun: dryRun, now: now)
        }
    }
    
    // MARK: - Execution History
    
    /// Get execution history for a specific rule.
    func historyForRule(id: String) -> [AutomationExecution] {
        return executionHistory.filter { $0.ruleId == id }
    }
    
    /// Get execution history for a specific article link.
    func historyForArticle(link: String) -> [AutomationExecution] {
        return executionHistory.filter { $0.articleLink == link }
    }
    
    /// Get recent execution history (most recent first).
    func recentHistory(limit: Int = 50) -> [AutomationExecution] {
        let sorted = executionHistory.sorted { $0.timestamp > $1.timestamp }
        return Array(sorted.prefix(limit))
    }
    
    /// Clear all execution history.
    func clearHistory() {
        executionHistory.removeAll()
    }
    
    private func addExecution(_ execution: AutomationExecution) {
        executionHistory.append(execution)
        // Trim to max size
        if executionHistory.count > maxHistorySize {
            let excess = executionHistory.count - maxHistorySize
            executionHistory.removeFirst(excess)
        }
    }
    
    // MARK: - Statistics
    
    /// Summary statistics for the automation engine.
    struct EngineStats {
        let totalRules: Int
        let enabledRules: Int
        let disabledRules: Int
        let totalExecutions: Int
        let topRulesByTriggers: [(name: String, count: Int)]
        let rulesNeverTriggered: [String]
        let averageTriggersPerRule: Double
    }
    
    func statistics() -> EngineStats {
        let enabled = rules.filter { $0.isEnabled }.count
        let topRules = rules
            .filter { $0.triggerCount > 0 }
            .sorted { $0.triggerCount > $1.triggerCount }
            .prefix(10)
            .map { (name: $0.name, count: $0.triggerCount) }
        let neverTriggered = rules
            .filter { $0.triggerCount == 0 }
            .map { $0.name }
        let avgTriggers = rules.isEmpty ? 0.0 :
            Double(rules.reduce(0) { $0 + $1.triggerCount }) / Double(rules.count)
        
        return EngineStats(
            totalRules: rules.count,
            enabledRules: enabled,
            disabledRules: rules.count - enabled,
            totalExecutions: executionHistory.count,
            topRulesByTriggers: Array(topRules),
            rulesNeverTriggered: neverTriggered,
            averageTriggersPerRule: avgTriggers
        )
    }
    
    // MARK: - Preset Rules
    
    /// Create a preset rule for common automation patterns.
    static func presetMuteByKeyword(_ keyword: String) -> AutomationRule {
        return AutomationRule(
            name: "Mute: \(keyword)",
            conditions: [AutomationCondition(field: .any, pattern: keyword)],
            actions: [.markRead, .markHidden],
            priority: 50
        )
    }
    
    static func presetTagByFeed(feedName: String, tag: String) -> AutomationRule {
        return AutomationRule(
            name: "Tag \(feedName) as \(tag)",
            conditions: [AutomationCondition(field: .feedName, mode: .exactMatch, pattern: feedName)],
            actions: [.addTag(tag)],
            priority: 100
        )
    }
    
    static func presetStarByKeyword(_ keyword: String) -> AutomationRule {
        return AutomationRule(
            name: "Star: \(keyword)",
            conditions: [AutomationCondition(field: .title, pattern: keyword)],
            actions: [.markStarred],
            priority: 75
        )
    }
    
    static func presetNotifyOnKeyword(_ keyword: String) -> AutomationRule {
        return AutomationRule(
            name: "Notify: \(keyword)",
            conditions: [AutomationCondition(field: .any, pattern: keyword)],
            actions: [.notify("Article about '\(keyword)' found: {title}")],
            priority: 25,
            maxTriggersPerDay: 10
        )
    }
    
    // MARK: - Import/Export
    
    /// Export all rules as JSON data.
    func exportRules() -> Data? {
        let encoder = JSONCoding.iso8601PrettyEncoder
        return try? encoder.encode(rules)
    }
    
    /// Export rules as a JSON string.
    func exportRulesAsString() -> String? {
        guard let data = exportRules() else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Import rules from JSON data. Merges with existing rules by default.
    /// Set `replace` to true to clear existing rules first.
    @discardableResult
    func importRules(from data: Data, replace: Bool = false) -> Int {
        let decoder = JSONCoding.iso8601Decoder
        guard let imported = try? decoder.decode([AutomationRule].self, from: data) else {
            return 0
        }
        
        if replace {
            rules.removeAll()
        }
        
        var added = 0
        for rule in imported {
            // Skip duplicates by name
            if !rules.contains(where: { $0.name == rule.name }) {
                rules.append(rule)
                added += 1
            }
        }
        
        rules.sort { $0.priority < $1.priority }
        if added > 0 {
            NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
        }
        return added
    }
    
    /// Import rules from a JSON string.
    @discardableResult
    func importRules(from jsonString: String, replace: Bool = false) -> Int {
        // Size guard: reject input larger than 10 MB to prevent OOM
        // on adversarial or accidentally huge payloads (CWE-400).
        guard jsonString.utf8.count <= 10_485_760 else { return 0 }

        guard let data = jsonString.data(using: .utf8) else { return 0 }
        return importRules(from: data, replace: replace)
    }
    
    // MARK: - Rule Validation
    
    /// Validate a rule before adding it. Returns list of issues.
    func validateRule(_ rule: AutomationRule) -> [String] {
        var issues: [String] = []
        
        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Rule name cannot be empty")
        }
        
        if rule.conditionGroup.conditions.isEmpty {
            issues.append("Rule must have at least one condition")
        }
        
        if rule.actions.isEmpty {
            issues.append("Rule must have at least one action")
        }
        
        // Check for invalid regex patterns and ReDoS-prone patterns
        for condition in rule.conditionGroup.conditions where condition.mode == .regex {
            if (try? NSRegularExpression(pattern: condition.pattern)) == nil {
                issues.append("Invalid regex pattern: '\(condition.pattern)'")
            } else if Self.isReDoSRisk(condition.pattern) {
                issues.append("Regex pattern may cause excessive backtracking (ReDoS risk): '\(condition.pattern)'. Avoid nested quantifiers like (a+)+.")
            }
        }
        
        // Check for empty patterns
        for condition in rule.conditionGroup.conditions {
            if condition.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Condition pattern cannot be empty")
            }
        }
        
        // Warn about potential conflicts
        if let maxPerDay = rule.maxTriggersPerDay, maxPerDay <= 0 {
            issues.append("Max triggers per day must be positive")
        }
        
        return issues
    }
    
    // MARK: - Dry Run / Testing
    
    /// Test a single rule against sample text without adding it.
    func testRule(_ rule: AutomationRule, title: String, body: String = "",
                  link: String = "", feedName: String = "") -> Bool {
        if let scope = rule.feedScope, !scope.isEmpty {
            let lowerFeed = feedName.lowercased()
            if !scope.contains(where: { $0.lowercased() == lowerFeed }) {
                return false
            }
        }
        return rule.conditionGroup.evaluate(
            title: title, body: body, link: link, feedName: feedName
        )
    }
    
    // MARK: - Bulk Operations
    
    /// Enable all rules.
    func enableAll() {
        for i in rules.indices {
            rules[i].isEnabled = true
        }
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
    }
    
    /// Disable all rules.
    func disableAll() {
        for i in rules.indices {
            rules[i].isEnabled = false
        }
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
    }
    
    /// Remove all rules.
    func removeAll() {
        rules.removeAll()
        NotificationCenter.default.post(name: .automationRulesDidChange, object: nil)
    }
    
    /// Reset all trigger counts and history.
    func resetStats() {
        for i in rules.indices {
            rules[i].triggerCount = 0
            rules[i].lastTriggeredAt = nil
            rules[i].dailyTriggers.removeAll()
        }
        executionHistory.removeAll()
    }
    
    // MARK: - Search & Filter
    
    /// Find rules that reference a specific feed name.
    func rulesForFeed(_ feedName: String) -> [AutomationRule] {
        let lower = feedName.lowercased()
        return rules.filter { rule in
            if let scope = rule.feedScope {
                return scope.contains { $0.lowercased() == lower }
            }
            // Rules with no feed scope apply to all feeds
            return true
        }
    }
    
    /// Find rules that use a specific action type.
    func rulesWithAction(_ actionType: String) -> [AutomationRule] {
        return rules.filter { rule in
            rule.actions.contains { actionKey($0).hasPrefix(actionType) }
        }
    }
    
    /// Search rules by name.
    func searchRules(query: String) -> [AutomationRule] {
        let lower = query.lowercased()
        return rules.filter { $0.name.lowercased().contains(lower) }
    }
    
    // MARK: - ReDoS Protection

    /// Detect regex patterns prone to catastrophic backtracking (ReDoS).
    /// Catches common dangerous patterns: nested quantifiers like (a+)+,
    /// (a*)*,  (a+)*, and alternation with overlapping branches.
    /// This is a heuristic — not exhaustive — but catches the most
    /// common ReDoS patterns found in user-supplied rules.
    static func isReDoSRisk(_ pattern: String) -> Bool {
        // Nested quantifiers: (...)+ followed by +, *, or {n,}
        // Examples: (a+)+, (\w*)+, ([a-z]+)*
        let nestedQuantifier = try? NSRegularExpression(
            pattern: #"\([^)]*[+*][^)]*\)[+*{]"#
        )
        if let regex = nestedQuantifier {
            let range = NSRange(pattern.startIndex..<pattern.endIndex, in: pattern)
            if regex.firstMatch(in: pattern, range: range) != nil {
                return true
            }
        }
        // Overlapping alternation with quantifiers: (a|a)+, (\w|\d)+
        // Simplified: alternation inside a quantified group
        let overlappingAlt = try? NSRegularExpression(
            pattern: #"\([^)]*\|[^)]*\)[+*{]"#
        )
        if let regex = overlappingAlt {
            let range = NSRange(pattern.startIndex..<pattern.endIndex, in: pattern)
            if regex.firstMatch(in: pattern, range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Helpers
    
    /// Generate a stable key for deduplicating actions.
    private func actionKey(_ action: AutomationAction) -> String {
        switch action {
        case .addTag(let tag):          return "addTag:\(tag)"
        case .markRead:                 return "markRead"
        case .markStarred:              return "markStarred"
        case .moveToCollection(let c):  return "moveToCollection:\(c)"
        case .setHighPriority:          return "setHighPriority"
        case .notify(let msg):          return "notify:\(msg)"
        case .markHidden:               return "markHidden"
        }
    }
}
