//
//  FeedPredictiveAlerts.swift
//  FeedReader
//
//  Autonomous Predictive Alert System
//  Learns feed publishing patterns and generates proactive alerts
//

import Foundation

// MARK: - Models

struct PredictiveAlert: Codable {
    let id: String
    let type: AlertType
    let severity: AlertSeverity
    let title: String
    let message: String
    let confidence: Double
    let predictedTime: Date?
    let feedURL: String?
    let topic: String?
    let generatedAt: Date
    let expiresAt: Date
    var dismissed: Bool
    var verified: Bool?
    
    enum AlertType: String, Codable {
        case publicationSurge
        case topicShift
        case breakingNews
        case feedSilence
        case qualityDrop
        case scheduleAnomaly
        case trendConvergence
        case readerFatigue
    }
    
    enum AlertSeverity: String, Codable, Comparable {
        case info = "info"
        case warning = "warning"
        case critical = "critical"
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            let order: [AlertSeverity] = [.info, .warning, .critical]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }
}

struct FeedPattern: Codable {
    let feedURL: String
    var hourlyRates: [Int: Double]
    var dailyRates: [Int: Double]
    var avgInterArticleSeconds: Double
    var topicDistribution: [String: Double]
    var lastPublishDate: Date?
    var observationCount: Int
    var lastUpdated: Date
}

struct AlertAccuracy: Codable {
    var totalGenerated: Int
    var verified: Int
    var correct: Int
    var falsePositives: Int
    var accuracy: Double { verified > 0 ? Double(correct) / Double(verified) : 0.0 }
    var byType: [String: TypeAccuracy]
    
    struct TypeAccuracy: Codable {
        var generated: Int
        var correct: Int
        var falsePositive: Int
    }
}

// MARK: - Engine

class FeedPredictiveAlerts {
    
    static let shared = FeedPredictiveAlerts()
    
    private var patterns: [String: FeedPattern] = [:]
    private var activeAlerts: [PredictiveAlert] = []
    private var alertHistory: [PredictiveAlert] = []
    private var accuracy: AlertAccuracy = AlertAccuracy(
        totalGenerated: 0, verified: 0, correct: 0, falsePositives: 0, byType: [:]
    )
    private var autoMonitorTimer: Timer?
    private var confidenceThreshold: Double = 0.6
    
    private let storageKey = "feedPredictiveAlerts"
    private let patternsKey = "feedPredictivePatterns"
    private let accuracyKey = "feedPredictiveAccuracy"
    
    private init() {
        loadState()
    }
    
    // MARK: - Pattern Learning
    
    func recordPublication(feedURL: String, title: String, date: Date, topics: [String] = []) {
        var pattern = patterns[feedURL] ?? FeedPattern(
            feedURL: feedURL, hourlyRates: [:], dailyRates: [:],
            avgInterArticleSeconds: 3600, topicDistribution: [:],
            lastPublishDate: nil, observationCount: 0, lastUpdated: Date()
        )
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        
        let prevHourly = pattern.hourlyRates[hour] ?? 0.0
        pattern.hourlyRates[hour] = prevHourly * 0.9 + 0.1
        
        let prevDaily = pattern.dailyRates[weekday] ?? 0.0
        pattern.dailyRates[weekday] = prevDaily * 0.9 + 0.1
        
        if let lastPub = pattern.lastPublishDate {
            let interval = date.timeIntervalSince(lastPub)
            if interval > 0 {
                pattern.avgInterArticleSeconds = pattern.avgInterArticleSeconds * 0.8 + interval * 0.2
            }
        }
        
        for topic in topics {
            let prev = pattern.topicDistribution[topic] ?? 0.0
            pattern.topicDistribution[topic] = prev * 0.9 + 0.1
        }
        for key in pattern.topicDistribution.keys where !topics.contains(key) {
            pattern.topicDistribution[key] = (pattern.topicDistribution[key] ?? 0) * 0.95
        }
        pattern.topicDistribution = pattern.topicDistribution.filter { $0.value > 0.001 }
        
        pattern.lastPublishDate = date
        pattern.observationCount += 1
        pattern.lastUpdated = Date()
        patterns[feedURL] = pattern
        saveState()
    }
    
    // MARK: - Prediction Engine
    
    @discardableResult
    func analyze(currentArticles: [(feedURL: String, title: String, date: Date, topics: [String])]) -> [PredictiveAlert] {
        for article in currentArticles {
            recordPublication(feedURL: article.feedURL, title: article.title,
                            date: article.date, topics: article.topics)
        }
        
        pruneExpiredAlerts()
        
        var newAlerts: [PredictiveAlert] = []
        newAlerts.append(contentsOf: detectPublicationSurge())
        newAlerts.append(contentsOf: detectTopicShift())
        newAlerts.append(contentsOf: detectFeedSilence())
        newAlerts.append(contentsOf: detectScheduleAnomaly())
        newAlerts.append(contentsOf: detectTrendConvergence(articles: currentArticles))
        newAlerts.append(contentsOf: detectReaderFatigue(articles: currentArticles))
        newAlerts.append(contentsOf: predictBreakingNews(articles: currentArticles))
        
        let filtered = newAlerts.filter { $0.confidence >= confidenceThreshold }
            .filter { alert in
                !activeAlerts.contains(where: {
                    $0.type == alert.type && $0.feedURL == alert.feedURL && $0.topic == alert.topic
                })
            }
        
        activeAlerts.append(contentsOf: filtered)
        accuracy.totalGenerated += filtered.count
        saveState()
        return filtered
    }
    
    // MARK: - Detection Channels
    
    private func detectPublicationSurge() -> [PredictiveAlert] {
        var alerts: [PredictiveAlert] = []
        let calendar = Calendar.current
        let nextHour = (calendar.component(.hour, from: Date()) + 1) % 24
        
        for (url, pattern) in patterns where pattern.observationCount >= 10 {
            let avgRate = pattern.hourlyRates.values.reduce(0, +) / max(Double(pattern.hourlyRates.count), 1)
            let nextRate = pattern.hourlyRates[nextHour] ?? 0
            
            if avgRate > 0 && nextRate > avgRate * 2.5 {
                let confidence = min(nextRate / (avgRate * 3.0), 1.0)
                alerts.append(PredictiveAlert(
                    id: UUID().uuidString, type: .publicationSurge,
                    severity: confidence > 0.8 ? .warning : .info,
                    title: "Publication Surge Expected",
                    message: "Feed typically publishes \(String(format: "%.1f", nextRate))x more articles in the next hour (avg: \(String(format: "%.1f", avgRate)))",
                    confidence: confidence,
                    predictedTime: calendar.date(bySettingHour: nextHour, minute: 0, second: 0, of: Date()),
                    feedURL: url, topic: nil, generatedAt: Date(),
                    expiresAt: Date().addingTimeInterval(7200), dismissed: false, verified: nil
                ))
            }
        }
        return alerts
    }
    
    private func detectTopicShift() -> [PredictiveAlert] {
        var alerts: [PredictiveAlert] = []
        for (url, pattern) in patterns where pattern.observationCount >= 20 {
            let sorted = pattern.topicDistribution.sorted { $0.value > $1.value }
            guard let top = sorted.first, sorted.count >= 3 else { continue }
            let secondValue = sorted[1].value
            if top.value > secondValue * 3 && top.value > 0.3 {
                alerts.append(PredictiveAlert(
                    id: UUID().uuidString, type: .topicShift, severity: .info,
                    title: "Topic Shift Detected",
                    message: "'\(top.key)' is dominating at \(Int(top.value * 100))% of recent content",
                    confidence: min(top.value, 0.95),
                    predictedTime: nil, feedURL: url, topic: top.key,
                    generatedAt: Date(), expiresAt: Date().addingTimeInterval(86400),
                    dismissed: false, verified: nil
                ))
            }
        }
        return alerts
    }
    
    private func detectFeedSilence() -> [PredictiveAlert] {
        var alerts: [PredictiveAlert] = []
        let now = Date()
        for (url, pattern) in patterns where pattern.observationCount >= 5 {
            guard let lastPub = pattern.lastPublishDate else { continue }
            let silenceDuration = now.timeIntervalSince(lastPub)
            let expectedInterval = pattern.avgInterArticleSeconds
            if expectedInterval > 0 && silenceDuration > expectedInterval * 3 {
                let ratio = silenceDuration / expectedInterval
                alerts.append(PredictiveAlert(
                    id: UUID().uuidString, type: .feedSilence,
                    severity: ratio > 5 ? .warning : .info,
                    title: "Unusual Feed Silence",
                    message: "No publications for \(formatDuration(silenceDuration)) (expected every \(formatDuration(expectedInterval)))",
                    confidence: min(ratio / 5.0, 0.95),
                    predictedTime: nil, feedURL: url, topic: nil,
                    generatedAt: Date(), expiresAt: Date().addingTimeInterval(43200),
                    dismissed: false, verified: nil
                ))
            }
        }
        return alerts
    }
    
    private func detectScheduleAnomaly() -> [PredictiveAlert] {
        var alerts: [PredictiveAlert] = []
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())
        let weekday = calendar.component(.weekday, from: Date())
        
        for (url, pattern) in patterns where pattern.observationCount >= 15 {
            let hourRate = pattern.hourlyRates[currentHour] ?? 0
            let dayRate = pattern.dailyRates[weekday] ?? 0
            let avgHour = pattern.hourlyRates.values.reduce(0, +) / max(Double(pattern.hourlyRates.count), 1)
            let avgDay = pattern.dailyRates.values.reduce(0, +) / max(Double(pattern.dailyRates.count), 1)
            
            if avgHour > 0 && hourRate < avgHour * 0.2 && dayRate > avgDay * 0.5 {
                alerts.append(PredictiveAlert(
                    id: UUID().uuidString, type: .scheduleAnomaly, severity: .info,
                    title: "Off-Schedule Publishing",
                    message: "Feed is unusually quiet at this hour (expected: \(String(format: "%.2f", avgHour)), actual: \(String(format: "%.2f", hourRate)))",
                    confidence: 0.65, predictedTime: nil, feedURL: url, topic: nil,
                    generatedAt: Date(), expiresAt: Date().addingTimeInterval(14400),
                    dismissed: false, verified: nil
                ))
            }
        }
        return alerts
    }
    
    private func detectTrendConvergence(articles: [(feedURL: String, title: String, date: Date, topics: [String])]) -> [PredictiveAlert] {
        var topicFeeds: [String: Set<String>] = [:]
        for article in articles {
            for topic in article.topics {
                var feeds = topicFeeds[topic] ?? Set()
                feeds.insert(article.feedURL)
                topicFeeds[topic] = feeds
            }
        }
        
        var alerts: [PredictiveAlert] = []
        for (topic, feeds) in topicFeeds where feeds.count >= 3 {
            alerts.append(PredictiveAlert(
                id: UUID().uuidString, type: .trendConvergence,
                severity: feeds.count >= 5 ? .warning : .info,
                title: "Trend Convergence: \(topic)",
                message: "\(feeds.count) feeds covering '\(topic)' simultaneously — possible emerging story",
                confidence: min(Double(feeds.count) / 5.0, 0.95),
                predictedTime: nil, feedURL: nil, topic: topic,
                generatedAt: Date(), expiresAt: Date().addingTimeInterval(43200),
                dismissed: false, verified: nil
            ))
        }
        return alerts
    }
    
    private func detectReaderFatigue(articles: [(feedURL: String, title: String, date: Date, topics: [String])]) -> [PredictiveAlert] {
        let now = Date()
        let recentCount = articles.filter { now.timeIntervalSince($0.date) < 3600 }.count
        if recentCount > 50 {
            return [PredictiveAlert(
                id: UUID().uuidString, type: .readerFatigue,
                severity: recentCount > 100 ? .warning : .info,
                title: "Reader Fatigue Warning",
                message: "\(recentCount) articles in the last hour — consider enabling smart filtering",
                confidence: min(Double(recentCount) / 80.0, 0.95),
                predictedTime: nil, feedURL: nil, topic: nil,
                generatedAt: Date(), expiresAt: Date().addingTimeInterval(7200),
                dismissed: false, verified: nil
            )]
        }
        return []
    }
    
    private func predictBreakingNews(articles: [(feedURL: String, title: String, date: Date, topics: [String])]) -> [PredictiveAlert] {
        let now = Date()
        let burstArticles = articles.filter { now.timeIntervalSince($0.date) < 900 }
        var topicBurst: [String: Int] = [:]
        for article in burstArticles {
            for topic in article.topics { topicBurst[topic, default: 0] += 1 }
        }
        
        var alerts: [PredictiveAlert] = []
        for (topic, count) in topicBurst where count >= 5 {
            alerts.append(PredictiveAlert(
                id: UUID().uuidString, type: .breakingNews, severity: .critical,
                title: "Possible Breaking News: \(topic)",
                message: "\(count) articles about '\(topic)' in the last 15 minutes — high probability of breaking story",
                confidence: min(Double(count) / 8.0, 0.95),
                predictedTime: nil, feedURL: nil, topic: topic,
                generatedAt: Date(), expiresAt: Date().addingTimeInterval(14400),
                dismissed: false, verified: nil
            ))
        }
        return alerts
    }
    
    // MARK: - Alert Management
    
    func getActiveAlerts(minSeverity: PredictiveAlert.AlertSeverity = .info) -> [PredictiveAlert] {
        return activeAlerts
            .filter { !$0.dismissed && $0.severity >= minSeverity }
            .sorted { $0.severity > $1.severity || ($0.severity == $1.severity && $0.confidence > $1.confidence) }
    }
    
    func dismissAlert(id: String) {
        if let idx = activeAlerts.firstIndex(where: { $0.id == id }) {
            activeAlerts[idx].dismissed = true
            alertHistory.append(activeAlerts[idx])
        }
        saveState()
    }
    
    func verifyAlert(id: String, wasCorrect: Bool) {
        if let idx = activeAlerts.firstIndex(where: { $0.id == id }) {
            activeAlerts[idx].verified = wasCorrect
            accuracy.verified += 1
            if wasCorrect { accuracy.correct += 1 } else { accuracy.falsePositives += 1 }
            
            let typeKey = activeAlerts[idx].type.rawValue
            var typeAcc = accuracy.byType[typeKey] ?? AlertAccuracy.TypeAccuracy(generated: 0, correct: 0, falsePositive: 0)
            if wasCorrect { typeAcc.correct += 1 } else { typeAcc.falsePositive += 1 }
            accuracy.byType[typeKey] = typeAcc
            
            if accuracy.verified >= 10 && accuracy.accuracy < 0.5 {
                confidenceThreshold = min(confidenceThreshold + 0.05, 0.9)
            } else if accuracy.verified >= 10 && accuracy.accuracy > 0.8 {
                confidenceThreshold = max(confidenceThreshold - 0.02, 0.4)
            }
        }
        saveState()
    }
    
    func getAccuracyReport() -> AlertAccuracy { return accuracy }
    
    func getSummary() -> String {
        let active = activeAlerts.filter { !$0.dismissed }
        let critical = active.filter { $0.severity == .critical }.count
        let warnings = active.filter { $0.severity == .warning }.count
        let infos = active.filter { $0.severity == .info }.count
        
        var lines: [String] = []
        lines.append("📡 Predictive Alerts")
        lines.append("  Active: \(active.count) (\(critical) critical, \(warnings) warnings, \(infos) info)")
        lines.append("  Patterns tracked: \(patterns.count) feeds")
        lines.append("  Confidence threshold: \(Int(confidenceThreshold * 100))%")
        if accuracy.verified > 0 {
            lines.append("  Accuracy: \(Int(accuracy.accuracy * 100))% (\(accuracy.verified) verified)")
        }
        
        if !active.isEmpty {
            lines.append("")
            lines.append("  Recent Alerts:")
            for alert in active.prefix(5) {
                let icon: String
                switch alert.severity {
                case .critical: icon = "🔴"
                case .warning: icon = "🟡"
                case .info: icon = "🔵"
                }
                lines.append("  \(icon) [\(Int(alert.confidence * 100))%] \(alert.title)")
                lines.append("     \(alert.message)")
            }
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Auto-Monitor
    
    func startAutoMonitor(intervalSeconds: TimeInterval = 300,
                          articleProvider: @escaping () -> [(feedURL: String, title: String, date: Date, topics: [String])]) {
        stopAutoMonitor()
        autoMonitorTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            let articles = articleProvider()
            let newAlerts = self?.analyze(currentArticles: articles) ?? []
            if !newAlerts.isEmpty {
                let critical = newAlerts.filter { $0.severity == .critical }
                if !critical.isEmpty {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FeedPredictiveAlertCritical"),
                        object: nil, userInfo: ["alerts": critical]
                    )
                }
                NotificationCenter.default.post(
                    name: NSNotification.Name("FeedPredictiveAlertNew"),
                    object: nil, userInfo: ["alerts": newAlerts]
                )
            }
        }
    }
    
    func stopAutoMonitor() {
        autoMonitorTimer?.invalidate()
        autoMonitorTimer = nil
    }
    
    // MARK: - JSON Export
    
    func exportJSON() -> String {
        let export: [String: Any] = [
            "activeAlerts": activeAlerts.filter { !$0.dismissed }.map { alertToDict($0) },
            "patterns": patterns.mapValues { patternToDict($0) },
            "accuracy": [
                "totalGenerated": accuracy.totalGenerated,
                "verified": accuracy.verified,
                "correct": accuracy.correct,
                "falsePositives": accuracy.falsePositives,
                "accuracy": accuracy.accuracy
            ],
            "confidenceThreshold": confidenceThreshold,
            "exportedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
    
    // MARK: - Helpers
    
    private func pruneExpiredAlerts() {
        let now = Date()
        let expired = activeAlerts.filter { $0.expiresAt < now }
        alertHistory.append(contentsOf: expired)
        activeAlerts.removeAll { $0.expiresAt < now }
        if alertHistory.count > 500 { alertHistory = Array(alertHistory.suffix(200)) }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return String(format: "%.1fh", seconds / 3600) }
        return String(format: "%.1fd", seconds / 86400)
    }
    
    private func alertToDict(_ alert: PredictiveAlert) -> [String: Any] {
        var d: [String: Any] = [
            "id": alert.id, "type": alert.type.rawValue,
            "severity": alert.severity.rawValue, "title": alert.title,
            "message": alert.message, "confidence": alert.confidence,
            "generatedAt": ISO8601DateFormatter().string(from: alert.generatedAt)
        ]
        if let t = alert.predictedTime { d["predictedTime"] = ISO8601DateFormatter().string(from: t) }
        if let f = alert.feedURL { d["feedURL"] = f }
        if let t = alert.topic { d["topic"] = t }
        return d
    }
    
    private func patternToDict(_ p: FeedPattern) -> [String: Any] {
        return [
            "feedURL": p.feedURL,
            "observationCount": p.observationCount,
            "avgInterArticleSeconds": p.avgInterArticleSeconds,
            "topTopics": Array(p.topicDistribution.sorted { $0.value > $1.value }.prefix(5).map { $0.key })
        ]
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(patterns) {
            UserDefaults.standard.set(data, forKey: patternsKey)
        }
        if let data = try? encoder.encode(activeAlerts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        if let data = try? encoder.encode(accuracy) {
            UserDefaults.standard.set(data, forKey: accuracyKey)
        }
    }
    
    private func loadState() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: patternsKey),
           let loaded = try? decoder.decode([String: FeedPattern].self, from: data) {
            patterns = loaded
        }
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? decoder.decode([PredictiveAlert].self, from: data) {
            activeAlerts = loaded
        }
        if let data = UserDefaults.standard.data(forKey: accuracyKey),
           let loaded = try? decoder.decode(AlertAccuracy.self, from: data) {
            accuracy = loaded
        }
    }
}
