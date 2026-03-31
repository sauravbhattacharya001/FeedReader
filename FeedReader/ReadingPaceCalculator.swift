//
//  ReadingPaceCalculator.swift
//  FeedReader
//
//  Calculates reading pace from historical data and projects when the user
//  will clear their reading queue. Provides daily article targets, estimated
//  completion dates, and pace trend analysis.
//
//  Features:
//  - Rolling average reading pace (articles/day, minutes/day)
//  - Queue completion date forecast based on current pace
//  - Daily article target to hit a user-set deadline
//  - Pace trend detection (accelerating, steady, slowing)
//  - Weekly pace summaries with comparison to prior weeks
//  - "Inbox zero" projections accounting for new article inflow
//  - Export pace report as JSON
//
//  Persistence: JSON file in Documents directory.
//  Integrates with ReadingQueueManager, ReadingStreakTracker, and
//  ReadingSpeedTracker for data.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new pace snapshot is recorded or a projection changes.
    static let readingPaceDidUpdate = Notification.Name("ReadingPaceDidUpdateNotification")
}

// MARK: - Models

/// A daily snapshot of reading activity for pace computation.
struct PaceDailySnapshot: Codable, Equatable {
    let date: String              // "yyyy-MM-dd"
    var articlesRead: Int
    var minutesSpent: Double
    var queueSizeAtEnd: Int
    var newArticlesAdded: Int
}

/// Trend direction for reading pace.
enum PaceTrend: String, Codable {
    case accelerating
    case steady
    case slowing
    case insufficientData = "insufficient_data"
}

/// A weekly pace summary.
struct WeeklyPaceSummary: Codable {
    let weekStartDate: String     // Monday "yyyy-MM-dd"
    let articlesRead: Int
    let minutesSpent: Double
    let avgArticlesPerDay: Double
    let avgMinutesPerDay: Double
    let netQueueChange: Int       // negative = shrinking queue
}

/// Projection for queue completion.
struct QueueProjection: Codable {
    let currentQueueSize: Int
    let currentPaceArticlesPerDay: Double
    let newArticlesPerDay: Double
    let netBurnPerDay: Double     // articles cleared minus new articles
    let estimatedDaysToEmpty: Double?  // nil if pace <= inflow
    let estimatedCompletionDate: String?
    let dailyTargetForDeadline: Int?
    let deadlineDate: String?
}

// MARK: - ReadingPaceCalculator

class ReadingPaceCalculator {

    // MARK: - Singleton

    static let shared = ReadingPaceCalculator()

    // MARK: - Properties

    private var snapshots: [PaceDailySnapshot] = []
    private let fileURL: URL
    private let calendar = Calendar.current

    /// User-set deadline to clear the queue (optional).
    var targetDeadline: Date? {
        didSet { save() }
    }

    /// Number of days to use for rolling average (default 14).
    var rollingWindowDays: Int = 14

    // MARK: - Date Formatting

    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Init

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("reading_pace_data.json")
        load()
    }

    // MARK: - Recording

    /// Record today's reading activity. Call at end of day or on each article completion.
    /// If a snapshot for today exists, it's updated (merged).
    func recordToday(articlesRead: Int, minutesSpent: Double, currentQueueSize: Int, newArticlesAdded: Int) {
        let todayStr = dateFormatter.string(from: Date())
        if let idx = snapshots.firstIndex(where: { $0.date == todayStr }) {
            snapshots[idx].articlesRead += articlesRead
            snapshots[idx].minutesSpent += minutesSpent
            snapshots[idx].queueSizeAtEnd = currentQueueSize
            snapshots[idx].newArticlesAdded += newArticlesAdded
        } else {
            let snap = PaceDailySnapshot(
                date: todayStr,
                articlesRead: articlesRead,
                minutesSpent: minutesSpent,
                queueSizeAtEnd: currentQueueSize,
                newArticlesAdded: newArticlesAdded
            )
            snapshots.append(snap)
        }
        snapshots.sort { $0.date < $1.date }
        save()
        NotificationCenter.default.post(name: .readingPaceDidUpdate, object: self)
    }

    // MARK: - Pace Calculations

    /// Rolling average articles read per day over the window.
    func averageArticlesPerDay(windowDays: Int? = nil) -> Double {
        let window = windowDays ?? rollingWindowDays
        let recent = recentSnapshots(days: window)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0) { $0 + $1.articlesRead }
        return Double(total) / Double(window)
    }

    /// Rolling average reading minutes per day.
    func averageMinutesPerDay(windowDays: Int? = nil) -> Double {
        let window = windowDays ?? rollingWindowDays
        let recent = recentSnapshots(days: window)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0.0) { $0 + $1.minutesSpent }
        return total / Double(window)
    }

    /// Average new articles arriving per day.
    func averageNewArticlesPerDay(windowDays: Int? = nil) -> Double {
        let window = windowDays ?? rollingWindowDays
        let recent = recentSnapshots(days: window)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0) { $0 + $1.newArticlesAdded }
        return Double(total) / Double(window)
    }

    /// Net articles cleared per day (read - new inflow).
    func netBurnRate(windowDays: Int? = nil) -> Double {
        return averageArticlesPerDay(windowDays: windowDays) - averageNewArticlesPerDay(windowDays: windowDays)
    }

    // MARK: - Trend Detection

    /// Compare recent pace to prior period to detect trend.
    func paceTrend() -> PaceTrend {
        let half = rollingWindowDays / 2
        guard half >= 3 else { return .insufficientData }
        let recentPace = averageArticlesPerDay(windowDays: half)
        // Compute prior half
        let allRecent = recentSnapshots(days: rollingWindowDays)
        guard allRecent.count >= rollingWindowDays / 2 else { return .insufficientData }
        let priorSnapshots = Array(allRecent.prefix(half))
        let priorTotal = priorSnapshots.reduce(0) { $0 + $1.articlesRead }
        let priorPace = Double(priorTotal) / Double(half)

        guard priorPace > 0 else { return .insufficientData }
        let changeRatio = (recentPace - priorPace) / priorPace
        if changeRatio > 0.15 { return .accelerating }
        if changeRatio < -0.15 { return .slowing }
        return .steady
    }

    // MARK: - Projections

    /// Project when the reading queue will be empty.
    func queueProjection(currentQueueSize: Int) -> QueueProjection {
        let pace = averageArticlesPerDay()
        let inflow = averageNewArticlesPerDay()
        let net = pace - inflow

        var estDays: Double? = nil
        var estDate: String? = nil
        if net > 0 && currentQueueSize > 0 {
            estDays = Double(currentQueueSize) / net
            let completionDate = calendar.date(byAdding: .day, value: Int(ceil(estDays!)), to: Date())!
            estDate = dateFormatter.string(from: completionDate)
        }

        var dailyTarget: Int? = nil
        var deadlineStr: String? = nil
        if let deadline = targetDeadline {
            deadlineStr = dateFormatter.string(from: deadline)
            let daysLeft = calendar.dateComponents([.day], from: Date(), to: deadline).day ?? 0
            if daysLeft > 0 {
                // Must read enough to clear queue + handle inflow by deadline
                let totalNeeded = Double(currentQueueSize) + (inflow * Double(daysLeft))
                dailyTarget = Int(ceil(totalNeeded / Double(daysLeft)))
            }
        }

        return QueueProjection(
            currentQueueSize: currentQueueSize,
            currentPaceArticlesPerDay: pace,
            newArticlesPerDay: inflow,
            netBurnPerDay: net,
            estimatedDaysToEmpty: estDays,
            estimatedCompletionDate: estDate,
            dailyTargetForDeadline: dailyTarget,
            deadlineDate: deadlineStr
        )
    }

    // MARK: - Weekly Summaries

    /// Generate weekly pace summaries for the last N weeks.
    func weeklySummaries(weeks: Int = 4) -> [WeeklyPaceSummary] {
        var result: [WeeklyPaceSummary] = []
        let today = Date()

        for w in 0..<weeks {
            // Find Monday of this week offset
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -w, to: today)!
            guard let weekStart = mondayOfWeek(containing: weekEnd) else { continue }
            let startStr = dateFormatter.string(from: weekStart)
            let endStr = dateFormatter.string(from: calendar.date(byAdding: .day, value: 6, to: weekStart)!)

            let weekSnaps = snapshots.filter { $0.date >= startStr && $0.date <= endStr }
            let articles = weekSnaps.reduce(0) { $0 + $1.articlesRead }
            let minutes = weekSnaps.reduce(0.0) { $0 + $1.minutesSpent }
            let queueChange: Int
            if let first = weekSnaps.first, let last = weekSnaps.last {
                queueChange = last.queueSizeAtEnd - first.queueSizeAtEnd
            } else {
                queueChange = 0
            }

            result.append(WeeklyPaceSummary(
                weekStartDate: startStr,
                articlesRead: articles,
                minutesSpent: minutes,
                avgArticlesPerDay: Double(articles) / 7.0,
                avgMinutesPerDay: minutes / 7.0,
                netQueueChange: queueChange
            ))
        }
        return result
    }

    // MARK: - Export

    /// Export all pace data as a JSON dictionary.
    func exportAsJSON(currentQueueSize: Int) -> [String: Any] {
        let projection = queueProjection(currentQueueSize: currentQueueSize)
        let trend = paceTrend()
        let summaries = weeklySummaries()

        return [
            "generatedAt": dateFormatter.string(from: Date()),
            "rollingWindowDays": rollingWindowDays,
            "averageArticlesPerDay": averageArticlesPerDay(),
            "averageMinutesPerDay": averageMinutesPerDay(),
            "averageNewArticlesPerDay": averageNewArticlesPerDay(),
            "netBurnRate": netBurnRate(),
            "trend": trend.rawValue,
            "projection": [
                "currentQueueSize": projection.currentQueueSize,
                "paceArticlesPerDay": projection.currentPaceArticlesPerDay,
                "newArticlesPerDay": projection.newArticlesPerDay,
                "netBurnPerDay": projection.netBurnPerDay,
                "estimatedDaysToEmpty": projection.estimatedDaysToEmpty as Any,
                "estimatedCompletionDate": projection.estimatedCompletionDate as Any,
                "dailyTargetForDeadline": projection.dailyTargetForDeadline as Any,
                "deadlineDate": projection.deadlineDate as Any
            ],
            "weeklySummaries": summaries.map { s in
                [
                    "weekStart": s.weekStartDate,
                    "articlesRead": s.articlesRead,
                    "minutesSpent": s.minutesSpent,
                    "avgArticlesPerDay": s.avgArticlesPerDay,
                    "avgMinutesPerDay": s.avgMinutesPerDay,
                    "netQueueChange": s.netQueueChange
                ] as [String: Any]
            },
            "totalSnapshotDays": snapshots.count
        ]
    }

    // MARK: - Snapshot Access

    /// All recorded snapshots, sorted by date.
    var allSnapshots: [PaceDailySnapshot] { snapshots }

    /// Total articles read across all history.
    var totalArticlesRead: Int { snapshots.reduce(0) { $0 + $1.articlesRead } }

    /// Total reading minutes across all history.
    var totalMinutesSpent: Double { snapshots.reduce(0.0) { $0 + $1.minutesSpent } }

    // MARK: - Reset

    func resetAllData() {
        snapshots = []
        targetDeadline = nil
        save()
    }

    // MARK: - Private Helpers

    private func recentSnapshots(days: Int) -> [PaceDailySnapshot] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let cutoffStr = dateFormatter.string(from: cutoff)
        return snapshots.filter { $0.date > cutoffStr }
    }

    private func mondayOfWeek(containing date: Date) -> Date? {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps)
    }

    // MARK: - Persistence

    private struct PersistenceWrapper: Codable {
        var snapshots: [PaceDailySnapshot]
        var targetDeadline: String?
        var rollingWindowDays: Int
    }

    private func save() {
        let wrapper = PersistenceWrapper(
            snapshots: snapshots,
            targetDeadline: targetDeadline.map { dateFormatter.string(from: $0) },
            rollingWindowDays: rollingWindowDays
        )
        do {
            let data = try JSONEncoder().encode(wrapper)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ReadingPaceCalculator] Save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let wrapper = try JSONDecoder().decode(PersistenceWrapper.self, from: data)
            snapshots = wrapper.snapshots
            rollingWindowDays = wrapper.rollingWindowDays
            if let ds = wrapper.targetDeadline {
                targetDeadline = dateFormatter.date(from: ds)
            }
        } catch {
            print("[ReadingPaceCalculator] Load failed: \(error)")
        }
    }
}
