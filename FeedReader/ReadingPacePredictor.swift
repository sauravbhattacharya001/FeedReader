//
//  ReadingPacePredictor.swift
//  FeedReader
//
//  Predicts when the user will finish their reading queue by combining
//  personalized reading speed (from ReadingSpeedTracker), daily reading
//  habits (from ReadingTimeBudget), and queue contents (from ReadingQueueManager).
//
//  Features:
//  - Queue completion forecast with estimated finish date
//  - Per-item predicted start/finish times in queue order
//  - Pace scenarios: current pace, optimistic (+25%), conservative (-25%)
//  - Backlog growth rate detection (are you adding faster than reading?)
//  - Weekly capacity analysis (how many articles you can handle)
//  - "Queue bankruptcy" warning when backlog exceeds reasonable timeframe
//  - Forecast comparison over time (are you gaining or losing ground?)
//  - Export forecast as JSON
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new forecast is generated.
    static let readingPaceForecastDidUpdate = Notification.Name("ReadingPaceForecastDidUpdateNotification")
    /// Posted when queue bankruptcy threshold is exceeded.
    static let readingQueueBankruptcyWarning = Notification.Name("ReadingQueueBankruptcyWarningNotification")
}

// MARK: - Models

/// A single forecast snapshot.
struct PaceForecast: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// When this forecast was generated.
    let generatedAt: Date
    /// Total unread items in queue at forecast time.
    let queueSize: Int
    /// Total estimated reading minutes for the entire queue.
    let totalMinutesNeeded: Double
    /// User's effective words per minute at forecast time.
    let effectiveWPM: Double
    /// Average daily reading minutes (from recent history).
    let avgDailyMinutes: Double
    /// Predicted finish date at current pace.
    let estimatedFinishDate: Date?
    /// Predicted finish date at optimistic pace (+25%).
    let optimisticFinishDate: Date?
    /// Predicted finish date at conservative pace (-25%).
    let conservativeFinishDate: Date?
    /// Days until queue completion at current pace (nil if infinite).
    let daysToComplete: Double?
    /// Whether backlog is growing faster than reading pace.
    let isBacklogGrowing: Bool
    /// Average articles added per day (last 30 days).
    let articlesAddedPerDay: Double
    /// Average articles completed per day (last 30 days).
    let articlesCompletedPerDay: Double
    /// Weekly article capacity at current pace.
    let weeklyCapacity: Int
    /// True if queue exceeds 90-day completion threshold.
    let isBankrupt: Bool

    static func == (lhs: PaceForecast, rhs: PaceForecast) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Per-item schedule prediction within the queue.
struct ItemSchedule: Codable, Equatable {
    /// Queue item ID.
    let itemId: String
    /// Article title.
    let articleTitle: String
    /// Position in queue (1-based).
    let position: Int
    /// Estimated reading minutes for this item.
    let estimatedMinutes: Double
    /// Predicted start date/time.
    let predictedStart: Date
    /// Predicted finish date/time.
    let predictedFinish: Date
    /// Cumulative minutes up to and including this item.
    let cumulativeMinutes: Double
}

/// Pace scenario for comparisons.
enum PaceScenario: String, Codable, CaseIterable {
    case conservative = "Conservative (-25%)"
    case current = "Current Pace"
    case optimistic = "Optimistic (+25%)"
    case aggressive = "Aggressive (+50%)"

    var multiplier: Double {
        switch self {
        case .conservative: return 0.75
        case .current: return 1.0
        case .optimistic: return 1.25
        case .aggressive: return 1.50
        }
    }
}

/// Trend direction for backlog analysis.
enum BacklogTrend: String, Codable {
    case shrinking = "Shrinking"
    case stable = "Stable"
    case growing = "Growing"
    case exploding = "Exploding"

    var emoji: String {
        switch self {
        case .shrinking: return "📉"
        case .stable: return "➡️"
        case .growing: return "📈"
        case .exploding: return "🚨"
        }
    }
}

// MARK: - ReadingPacePredictor

class ReadingPacePredictor {

    // MARK: - Singleton

    static let shared = ReadingPacePredictor()

    // MARK: - Constants

    /// Default reading speed if no speed data exists (average adult WPM).
    private let defaultWPM: Double = 238.0
    /// Default daily reading minutes if no budget/history data.
    private let defaultDailyMinutes: Double = 30.0
    /// Average words per article if word count unknown.
    private let defaultArticleWordCount: Int = 1200
    /// Bankruptcy threshold in days.
    private let bankruptcyThresholdDays: Double = 90.0
    /// Maximum forecast history entries to keep.
    private let maxForecastHistory: Int = 100
    /// Days of history to analyze for add/complete rates.
    private let analysisWindowDays: Int = 30

    // MARK: - Storage

    private var forecastHistory: [PaceForecast] = []
    private let storageKey = "ReadingPacePredictorForecasts"

    // MARK: - Init

    private init() {
        loadForecasts()
    }

    // MARK: - Public API

    /// Generate a fresh forecast based on current queue and reading data.
    func generateForecast() -> PaceForecast {
        let queueItems = getUnreadQueueItems()
        let queueSize = queueItems.count
        let effectiveWPM = getEffectiveWPM()
        let avgDaily = getAverageDailyReadingMinutes()
        let totalMinutes = calculateTotalReadingMinutes(items: queueItems, wpm: effectiveWPM)

        let daysToComplete: Double? = avgDaily > 0 ? totalMinutes / avgDaily : nil
        let finishDate: Date? = daysToComplete.map { Calendar.current.date(byAdding: .second, value: Int($0 * 86400), to: Date())! }

        let optimisticDays = daysToComplete.map { $0 / PaceScenario.optimistic.multiplier }
        let optimisticDate = optimisticDays.map { Calendar.current.date(byAdding: .second, value: Int($0 * 86400), to: Date())! }

        let conservativeDays = daysToComplete.map { $0 / PaceScenario.conservative.multiplier }
        let conservativeDate = conservativeDays.map { Calendar.current.date(byAdding: .second, value: Int($0 * 86400), to: Date())! }

        let addedPerDay = getArticlesAddedPerDay()
        let completedPerDay = getArticlesCompletedPerDay()
        let isGrowing = addedPerDay > completedPerDay && completedPerDay > 0
        let weeklyCapacity = avgDaily > 0 ? Int((avgDaily * 7) / (totalMinutes / max(Double(queueSize), 1))) : 0
        let isBankrupt = (daysToComplete ?? Double.infinity) > bankruptcyThresholdDays

        let forecast = PaceForecast(
            id: UUID().uuidString,
            generatedAt: Date(),
            queueSize: queueSize,
            totalMinutesNeeded: totalMinutes,
            effectiveWPM: effectiveWPM,
            avgDailyMinutes: avgDaily,
            estimatedFinishDate: finishDate,
            optimisticFinishDate: optimisticDate,
            conservativeFinishDate: conservativeDate,
            daysToComplete: daysToComplete,
            isBacklogGrowing: isGrowing,
            articlesAddedPerDay: addedPerDay,
            articlesCompletedPerDay: completedPerDay,
            weeklyCapacity: weeklyCapacity,
            isBankrupt: isBankrupt
        )

        appendForecast(forecast)

        if isBankrupt {
            NotificationCenter.default.post(name: .readingQueueBankruptcyWarning, object: forecast)
        }
        NotificationCenter.default.post(name: .readingPaceForecastDidUpdate, object: forecast)

        return forecast
    }

    /// Get per-item schedule predictions for the current queue.
    func generateSchedule() -> [ItemSchedule] {
        let items = getUnreadQueueItems()
        let effectiveWPM = getEffectiveWPM()
        let avgDaily = getAverageDailyReadingMinutes()
        guard avgDaily > 0 else { return [] }

        var schedule: [ItemSchedule] = []
        var cumulativeMinutes: Double = 0
        let now = Date()

        for (index, item) in items.enumerated() {
            let wordCount = Double(estimateWordCount(for: item))
            let readingMinutes = wordCount / effectiveWPM
            let startOffsetDays = cumulativeMinutes / avgDaily
            let predictedStart = Calendar.current.date(byAdding: .second, value: Int(startOffsetDays * 86400), to: now)!

            cumulativeMinutes += readingMinutes
            let finishOffsetDays = cumulativeMinutes / avgDaily
            let predictedFinish = Calendar.current.date(byAdding: .second, value: Int(finishOffsetDays * 86400), to: now)!

            schedule.append(ItemSchedule(
                itemId: item.id,
                articleTitle: item.articleTitle,
                position: index + 1,
                estimatedMinutes: readingMinutes,
                predictedStart: predictedStart,
                predictedFinish: predictedFinish,
                cumulativeMinutes: cumulativeMinutes
            ))
        }

        return schedule
    }

    /// Forecast for a specific scenario.
    func forecastForScenario(_ scenario: PaceScenario) -> (daysToComplete: Double?, finishDate: Date?) {
        let items = getUnreadQueueItems()
        let effectiveWPM = getEffectiveWPM()
        let avgDaily = getAverageDailyReadingMinutes() * scenario.multiplier
        let totalMinutes = calculateTotalReadingMinutes(items: items, wpm: effectiveWPM)
        guard avgDaily > 0 else { return (nil, nil) }

        let days = totalMinutes / avgDaily
        let date = Calendar.current.date(byAdding: .second, value: Int(days * 86400), to: Date())
        return (days, date)
    }

    /// Analyze backlog trend over recent forecasts.
    func analyzeBacklogTrend() -> BacklogTrend {
        let recent = Array(forecastHistory.suffix(10))
        guard recent.count >= 2 else { return .stable }

        let firstHalf = recent.prefix(recent.count / 2)
        let secondHalf = recent.suffix(recent.count / 2)

        let avgFirst = firstHalf.map { Double($0.queueSize) }.reduce(0, +) / Double(firstHalf.count)
        let avgSecond = secondHalf.map { Double($0.queueSize) }.reduce(0, +) / Double(secondHalf.count)

        let changeRate = avgFirst > 0 ? (avgSecond - avgFirst) / avgFirst : 0

        if changeRate < -0.1 { return .shrinking }
        if changeRate < 0.1 { return .stable }
        if changeRate < 0.5 { return .growing }
        return .exploding
    }

    /// Get queue health summary as a dictionary (useful for display).
    func queueHealthSummary() -> [String: Any] {
        let forecast = generateForecast()
        let trend = analyzeBacklogTrend()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        var summary: [String: Any] = [
            "queueSize": forecast.queueSize,
            "totalReadingHours": String(format: "%.1f", forecast.totalMinutesNeeded / 60),
            "readingSpeed": String(format: "%.0f WPM", forecast.effectiveWPM),
            "dailyReadingMinutes": String(format: "%.0f min", forecast.avgDailyMinutes),
            "backlogTrend": "\(trend.emoji) \(trend.rawValue)",
            "weeklyCapacity": "\(forecast.weeklyCapacity) articles",
            "articlesAddedPerDay": String(format: "%.1f", forecast.articlesAddedPerDay),
            "articlesCompletedPerDay": String(format: "%.1f", forecast.articlesCompletedPerDay),
            "isBankrupt": forecast.isBankrupt
        ]

        if let days = forecast.daysToComplete {
            summary["daysToComplete"] = String(format: "%.1f days", days)
        } else {
            summary["daysToComplete"] = "∞ (no reading activity)"
        }

        if let date = forecast.estimatedFinishDate {
            summary["estimatedFinishDate"] = formatter.string(from: date)
        }
        if let date = forecast.optimisticFinishDate {
            summary["optimisticFinishDate"] = formatter.string(from: date)
        }
        if let date = forecast.conservativeFinishDate {
            summary["conservativeFinishDate"] = formatter.string(from: date)
        }

        return summary
    }

    /// Get forecast history.
    func getForecastHistory() -> [PaceForecast] {
        return forecastHistory
    }

    /// Clear all forecast history.
    func clearHistory() {
        forecastHistory.removeAll()
        saveForecasts()
    }

    /// Export forecast data as JSON.
    func exportAsJSON() -> String? {
        let export: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "currentForecast": queueHealthSummary(),
            "forecastCount": forecastHistory.count
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: export, options: .prettyPrinted) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private Helpers

    private func getUnreadQueueItems() -> [ReadingQueueManager.QueueItem] {
        return ReadingQueueManager.shared.allItems().filter { !$0.isCompleted }
    }

    private func getEffectiveWPM() -> Double {
        let tracker = ReadingSpeedTracker.shared
        let avg = tracker.averageWPM()
        return avg > 0 ? avg : defaultWPM
    }

    private func getAverageDailyReadingMinutes() -> Double {
        // Try to get from ReadingTimeBudget tracked sessions
        let budget = ReadingTimeBudget.shared
        let weekReport = budget.weeklyReport()
        let dailyAvg = weekReport.compactMap { entry -> Double? in
            let mins = entry.value as? Double ?? (entry.value as? Int).map { Double($0) }
            return mins
        }
        if !dailyAvg.isEmpty {
            let avg = dailyAvg.reduce(0, +) / Double(dailyAvg.count)
            if avg > 0 { return avg }
        }
        return defaultDailyMinutes
    }

    private func calculateTotalReadingMinutes(items: [ReadingQueueManager.QueueItem], wpm: Double) -> Double {
        guard wpm > 0 else { return 0 }
        return items.reduce(0.0) { total, item in
            let words = Double(estimateWordCount(for: item))
            return total + (words / wpm)
        }
    }

    private func estimateWordCount(for item: ReadingQueueManager.QueueItem) -> Int {
        // Use the item's estimated reading time to back-calculate word count
        if item.estimatedReadingTimeMinutes > 0 {
            return Int(item.estimatedReadingTimeMinutes * defaultWPM)
        }
        return defaultArticleWordCount
    }

    private func getArticlesAddedPerDay() -> Double {
        let queue = ReadingQueueManager.shared
        let all = queue.allItems()
        let windowStart = Calendar.current.date(byAdding: .day, value: -analysisWindowDays, to: Date())!
        let recentlyAdded = all.filter { $0.addedDate >= windowStart }
        return Double(recentlyAdded.count) / Double(analysisWindowDays)
    }

    private func getArticlesCompletedPerDay() -> Double {
        let queue = ReadingQueueManager.shared
        let all = queue.allItems()
        let windowStart = Calendar.current.date(byAdding: .day, value: -analysisWindowDays, to: Date())!
        let recentlyCompleted = all.filter { $0.isCompleted && ($0.completedDate ?? .distantPast) >= windowStart }
        return Double(recentlyCompleted.count) / Double(analysisWindowDays)
    }

    private func appendForecast(_ forecast: PaceForecast) {
        forecastHistory.append(forecast)
        if forecastHistory.count > maxForecastHistory {
            forecastHistory.removeFirst(forecastHistory.count - maxForecastHistory)
        }
        saveForecasts()
    }

    // MARK: - Persistence

    private func saveForecasts() {
        guard let data = try? JSONEncoder().encode(forecastHistory) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadForecasts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PaceForecast].self, from: data) else { return }
        forecastHistory = decoded
    }
}
