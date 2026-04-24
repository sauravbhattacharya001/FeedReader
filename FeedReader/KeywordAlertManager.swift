//
//  KeywordAlertManager.swift
//  FeedReader
//
//  Manages keyword alerts — user-defined topics that flag matching stories
//  for attention. Provides CRUD operations, persistent storage, and batch
//  matching against story feeds.
//

import Foundation
import os.log

/// Notification posted when keyword alerts change (add/remove/toggle).
extension Notification.Name {
    static let keywordAlertsDidChange = Notification.Name("KeywordAlertsDidChangeNotification")
}

/// A story that matched one or more keyword alerts.
struct AlertedStory {
    let story: Story
    let matchedAlerts: [KeywordAlert]
    
    /// Highest priority among matched alerts.
    var highestPriority: AlertPriority {
        return matchedAlerts
            .map { $0.priority }
            .min(by: { $0.sortOrder < $1.sortOrder }) ?? .low
    }
}

class KeywordAlertManager {
    
    // MARK: - Singleton
    
    static let shared = KeywordAlertManager()
    
    // MARK: - Properties
    
    private(set) var alerts: [KeywordAlert] = []
    
    var activeAlerts: [KeywordAlert] {
        return alerts.filter { $0.isActive }
    }
    
    private static let archiveURL: URL = {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("keywordAlerts")
    }()
    
    // MARK: - Initialization
    
    private init() {
        loadAlerts()
    }
    
    // MARK: - CRUD
    
    /// Add a new keyword alert. Returns false if limit reached or keyword is empty.
    @discardableResult
    func addAlert(_ alert: KeywordAlert) -> Bool {
        guard alerts.count < KeywordAlert.maxAlerts else { return false }
        
        // Prevent exact duplicate keywords
        let lowerKeyword = alert.keyword.lowercased()
        guard !alerts.contains(where: { $0.keyword.lowercased() == lowerKeyword }) else {
            return false
        }
        
        alerts.append(alert)
        saveAlerts()
        NotificationCenter.default.post(name: .keywordAlertsDidChange, object: nil)
        return true
    }
    
    /// Create and add an alert from just a keyword string.
    @discardableResult
    func addAlert(keyword: String, priority: AlertPriority = .medium,
                  matchScope: KeywordAlert.MatchScope = .both,
                  colorHex: String? = nil) -> Bool {
        guard let alert = KeywordAlert(keyword: keyword, priority: priority,
                                        matchScope: matchScope, colorHex: colorHex) else {
            return false
        }
        return addAlert(alert)
    }
    
    /// Remove an alert by ID.
    @discardableResult
    func removeAlert(id: String) -> Bool {
        let before = alerts.count
        alerts.removeAll { $0.id == id }
        if alerts.count < before {
            saveAlerts()
            NotificationCenter.default.post(name: .keywordAlertsDidChange, object: nil)
            return true
        }
        return false
    }
    
    /// Toggle an alert's active state.
    func toggleAlert(id: String) {
        guard let alert = alerts.first(where: { $0.id == id }) else { return }
        alert.isActive = !alert.isActive
        saveAlerts()
        NotificationCenter.default.post(name: .keywordAlertsDidChange, object: nil)
    }
    
    /// Update an alert's priority.
    func setPriority(id: String, priority: AlertPriority) {
        guard let alert = alerts.first(where: { $0.id == id }) else { return }
        alert.priority = priority
        saveAlerts()
        NotificationCenter.default.post(name: .keywordAlertsDidChange, object: nil)
    }
    
    /// Remove all alerts.
    func removeAll() {
        alerts.removeAll()
        saveAlerts()
        NotificationCenter.default.post(name: .keywordAlertsDidChange, object: nil)
    }
    
    // MARK: - Matching
    
    /// Check a single story against all active alerts.
    /// Returns matched alerts (empty if no match).
    func matchingAlerts(for story: Story) -> [KeywordAlert] {
        return activeAlerts.filter { alert in
            alert.matches(title: story.title, body: story.body)
        }
    }
    
    /// Check if a story matches any active alert.
    func isAlerted(story: Story) -> Bool {
        return activeAlerts.contains { alert in
            alert.matches(title: story.title, body: story.body)
        }
    }
    
    /// Scan a list of stories and return only those matching at least one alert.
    /// Results are sorted by highest alert priority, then by story order.
    /// Also increments match counts on alerts.
    func scanStories(_ stories: [Story]) -> [AlertedStory] {
        var results: [AlertedStory] = []
        
        for story in stories {
            let matched = matchingAlerts(for: story)
            if !matched.isEmpty {
                // Increment match counts
                for alert in matched {
                    alert.matchCount += 1
                }
                results.append(AlertedStory(story: story, matchedAlerts: matched))
            }
        }
        
        // Sort: high priority first
        results.sort { $0.highestPriority.sortOrder < $1.highestPriority.sortOrder }
        
        if !results.isEmpty {
            saveAlerts() // Persist updated match counts
        }
        
        return results
    }
    
    /// Get a summary of alert activity.
    func summary() -> String {
        let total = alerts.count
        let active = activeAlerts.count
        let totalMatches = alerts.reduce(0) { $0 + $1.matchCount }
        
        var parts: [String] = []
        parts.append("\(total) alert\(total == 1 ? "" : "s")")
        parts.append("\(active) active")
        parts.append("\(totalMatches) total match\(totalMatches == 1 ? "" : "es")")
        return parts.joined(separator: ", ")
    }
    
    // MARK: - Persistence
    
    private func saveAlerts() {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: alerts as NSArray,
                requiringSecureCoding: true
            )
            try data.write(to: KeywordAlertManager.archiveURL)
        } catch {
            os_log("Failed to save alerts: %{private}s", log: FeedReaderLogger.alerts, type: .error, error.localizedDescription)
        }
    }
    
    private func loadAlerts() {
        guard let data = try? Data(contentsOf: KeywordAlertManager.archiveURL) else {
            alerts = []
            return
        }
        
        do {
            let allowedClasses: [AnyClass] = [NSArray.self, KeywordAlert.self, NSString.self, NSDate.self, NSNumber.self]
            let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)
            alerts = (unarchived as? [KeywordAlert]) ?? []
        } catch {
            os_log("Failed to load alerts: %{private}s", log: FeedReaderLogger.alerts, type: .error, error.localizedDescription)
            alerts = []
        }
    }
}
