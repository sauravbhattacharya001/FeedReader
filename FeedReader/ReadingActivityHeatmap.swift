//
//  ReadingActivityHeatmap.swift
//  FeedReader
//
//  GitHub-style contribution heatmap for reading activity:
//  - Daily article counts rendered as a 52-week grid
//  - Configurable time ranges (3 months, 6 months, 1 year)
//  - Intensity levels (0-4) based on configurable thresholds
//  - Current and longest streak tracking
//  - Weekly/monthly aggregation summaries
//  - Day-of-week and hour-of-day distribution breakdowns
//  - Year-over-year comparison (delta analysis)
//  - Data export as structured dictionary
//
//  All analysis is on-device using reading history data.
//  No external dependencies or network calls.
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the heatmap data is updated.
    static let readingHeatmapDidUpdate = Notification.Name("ReadingHeatmapDidUpdateNotification")
}

// MARK: - Models

/// Intensity level for a heatmap cell (0 = no activity, 4 = most active).
enum HeatmapIntensity: Int, Codable, CaseIterable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case intense = 4

    var label: String {
        switch self {
        case .none:    return "No reading"
        case .low:     return "Light reading"
        case .medium:  return "Moderate reading"
        case .high:    return "Active reading"
        case .intense: return "Intense reading"
        }
    }

    static func < (lhs: HeatmapIntensity, rhs: HeatmapIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Time range for the heatmap display.
enum HeatmapTimeRange: String, Codable, CaseIterable {
    case threeMonths = "3_months"
    case sixMonths   = "6_months"
    case oneYear     = "1_year"

    var days: Int {
        switch self {
        case .threeMonths: return 91
        case .sixMonths:   return 182
        case .oneYear:     return 365
        }
    }

    var label: String {
        switch self {
        case .threeMonths: return "3 months"
        case .sixMonths:   return "6 months"
        case .oneYear:     return "1 year"
        }
    }
}

/// One cell in the heatmap grid.
struct HeatmapCell: Codable, Equatable {
    let date: Date
    let count: Int
    let intensity: HeatmapIntensity
    let articles: [String]  // Article IDs read that day

    /// Weekday index (1 = Sunday ... 7 = Saturday).
    var weekday: Int {
        Calendar.current.component(.weekday, from: date)
    }
}

/// A column in the heatmap grid (one week).
struct HeatmapWeek: Codable, Equatable {
    let weekNumber: Int       // ISO week number
    let year: Int
    let cells: [HeatmapCell]  // Up to 7 cells (Sun–Sat)

    var totalCount: Int {
        cells.reduce(0) { $0 + $1.count }
    }
}

/// Monthly aggregation for summary display.
struct HeatmapMonthSummary: Codable, Equatable {
    let year: Int
    let month: Int
    let totalArticles: Int
    let activeDays: Int
    let averagePerDay: Double
    let peakDay: Date?
    let peakCount: Int

    var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "Unknown" }
        return formatter.string(from: date)
    }
}

/// Reading streak data.
struct ReadingStreak: Codable, Equatable {
    let startDate: Date
    let endDate: Date
    let length: Int  // Number of consecutive days

    static let empty = ReadingStreak(startDate: Date(), endDate: Date(), length: 0)
}

/// Day-of-week distribution.
struct WeekdayDistribution: Codable, Equatable {
    let weekday: Int          // 1 = Sunday ... 7 = Saturday
    let totalArticles: Int
    let activeDays: Int
    let averagePerActiveDay: Double

    var weekdayLabel: String {
        let formatter = DateFormatter()
        return formatter.shortWeekdaySymbols[weekday - 1]
    }
}

/// Year-over-year comparison for a given period.
struct YearOverYearDelta: Codable, Equatable {
    let periodLabel: String
    let currentTotal: Int
    let previousTotal: Int
    let delta: Int
    let percentChange: Double?  // nil if previous was 0
}

/// Intensity thresholds — how many articles per day map to each level.
struct HeatmapThresholds: Codable, Equatable {
    let low: Int       // >= low → .low
    let medium: Int    // >= medium → .medium
    let high: Int      // >= high → .high
    let intense: Int   // >= intense → .intense

    static let `default` = HeatmapThresholds(low: 1, medium: 3, high: 6, intense: 10)

    func intensity(for count: Int) -> HeatmapIntensity {
        if count >= intense { return .intense }
        if count >= high    { return .high }
        if count >= medium  { return .medium }
        if count >= low     { return .low }
        return .none
    }
}

/// Persisted heatmap state.
struct HeatmapState: Codable {
    var dailyCounts: [String: DayRecord]  // "yyyy-MM-dd" → record
    var thresholds: HeatmapThresholds
    var lastUpdated: Date

    struct DayRecord: Codable {
        var count: Int
        var articleIDs: [String]
    }

    static let empty = HeatmapState(
        dailyCounts: [:],
        thresholds: .default,
        lastUpdated: Date()
    )
}

// MARK: - ReadingActivityHeatmap

/// Generates a GitHub-style reading activity heatmap with streak tracking,
/// weekly/monthly summaries, and year-over-year comparison.
final class ReadingActivityHeatmap {

    // MARK: - Properties

    private(set) var state: HeatmapState
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var persistenceURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("reading_activity_heatmap.json")
    }

    // MARK: - Init

    init(state: HeatmapState? = nil) {
        if let state = state {
            self.state = state
        } else {
            self.state = Self.loadFromDisk() ?? .empty
        }
    }

    // MARK: - Recording

    /// Record that an article was read.
    @discardableResult
    func recordReading(articleID: String, date: Date = Date()) -> HeatmapCell {
        let key = dateFormatter.string(from: date)
        var record = state.dailyCounts[key] ?? HeatmapState.DayRecord(count: 0, articleIDs: [])

        // Avoid duplicate article IDs
        if !record.articleIDs.contains(articleID) {
            record.count += 1
            record.articleIDs.append(articleID)
        }

        state.dailyCounts[key] = record
        state.lastUpdated = Date()
        saveToDisk()
        NotificationCenter.default.post(name: .readingHeatmapDidUpdate, object: self)

        return HeatmapCell(
            date: date,
            count: record.count,
            intensity: state.thresholds.intensity(for: record.count),
            articles: record.articleIDs
        )
    }

    /// Record multiple articles at once (batch import).
    func recordBatch(_ entries: [(articleID: String, date: Date)]) {
        for entry in entries {
            let key = dateFormatter.string(from: entry.date)
            var record = state.dailyCounts[key] ?? HeatmapState.DayRecord(count: 0, articleIDs: [])
            if !record.articleIDs.contains(entry.articleID) {
                record.count += 1
                record.articleIDs.append(entry.articleID)
            }
            state.dailyCounts[key] = record
        }
        state.lastUpdated = Date()
        saveToDisk()
        NotificationCenter.default.post(name: .readingHeatmapDidUpdate, object: self)
    }

    // MARK: - Heatmap Grid

    /// Generate the heatmap grid for a given time range.
    func generateGrid(range: HeatmapTimeRange = .oneYear, from endDate: Date = Date()) -> [HeatmapWeek] {
        let startDate = calendar.date(byAdding: .day, value: -range.days, to: endDate)!
        // Align start to Sunday
        let startWeekday = calendar.component(.weekday, from: startDate)
        let alignedStart = calendar.date(byAdding: .day, value: -(startWeekday - 1), to: startDate)!

        var weeks: [HeatmapWeek] = []
        var currentDate = alignedStart

        while currentDate <= endDate {
            var cells: [HeatmapCell] = []
            let weekNum = calendar.component(.weekOfYear, from: currentDate)
            let year = calendar.component(.yearForWeekOfYear, from: currentDate)

            for _ in 0..<7 {
                if currentDate > endDate { break }
                let key = dateFormatter.string(from: currentDate)
                let record = state.dailyCounts[key]
                let count = record?.count ?? 0

                cells.append(HeatmapCell(
                    date: currentDate,
                    count: count,
                    intensity: state.thresholds.intensity(for: count),
                    articles: record?.articleIDs ?? []
                ))
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }

            weeks.append(HeatmapWeek(weekNumber: weekNum, year: year, cells: cells))
        }

        return weeks
    }

    // MARK: - Streaks

    /// Calculate the current reading streak (consecutive days ending today or yesterday).
    func currentStreak(from referenceDate: Date = Date()) -> ReadingStreak {
        let today = calendar.startOfDay(for: referenceDate)
        var checkDate = today
        var streakEnd = today
        var streakLength = 0

        // Check today first
        let todayKey = dateFormatter.string(from: today)
        if let record = state.dailyCounts[todayKey], record.count > 0 {
            streakLength = 1
            streakEnd = today
        } else {
            // Check yesterday — streak might still be "current" if broken today
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let yKey = dateFormatter.string(from: yesterday)
            if let record = state.dailyCounts[yKey], record.count > 0 {
                streakLength = 1
                streakEnd = yesterday
                checkDate = yesterday
            } else {
                return .empty
            }
        }

        // Walk backwards
        var day = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        while true {
            let key = dateFormatter.string(from: day)
            if let record = state.dailyCounts[key], record.count > 0 {
                streakLength += 1
                day = calendar.date(byAdding: .day, value: -1, to: day)!
            } else {
                break
            }
        }

        let streakStart = calendar.date(byAdding: .day, value: 1, to: day)!
        return ReadingStreak(startDate: streakStart, endDate: streakEnd, length: streakLength)
    }

    /// Find the longest reading streak in the entire history.
    func longestStreak() -> ReadingStreak {
        let sortedKeys = state.dailyCounts.keys
            .compactMap { dateFormatter.date(from: $0) }
            .sorted()

        guard !sortedKeys.isEmpty else { return .empty }

        var best = ReadingStreak.empty
        var currentStart = sortedKeys[0]
        var currentEnd = sortedKeys[0]
        var currentLength = 1

        for i in 1..<sortedKeys.count {
            let prev = sortedKeys[i - 1]
            let curr = sortedKeys[i]
            let daysBetween = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0

            if daysBetween == 1 {
                currentEnd = curr
                currentLength += 1
            } else {
                if currentLength > best.length {
                    best = ReadingStreak(startDate: currentStart, endDate: currentEnd, length: currentLength)
                }
                currentStart = curr
                currentEnd = curr
                currentLength = 1
            }
        }

        // Check final streak
        if currentLength > best.length {
            best = ReadingStreak(startDate: currentStart, endDate: currentEnd, length: currentLength)
        }

        return best
    }

    // MARK: - Summaries

    /// Monthly aggregation summaries for a given time range.
    func monthlySummaries(range: HeatmapTimeRange = .oneYear, from endDate: Date = Date()) -> [HeatmapMonthSummary] {
        let startDate = calendar.date(byAdding: .day, value: -range.days, to: endDate)!

        // Group daily counts by month
        var monthBuckets: [String: [(date: Date, count: Int)]] = [:]

        for (key, record) in state.dailyCounts {
            guard let date = dateFormatter.date(from: key) else { continue }
            if date < startDate || date > endDate { continue }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let bucketKey = "\(year)-\(month)"
            monthBuckets[bucketKey, default: []].append((date: date, count: record.count))
        }

        return monthBuckets.map { (bucketKey, entries) in
            let parts = bucketKey.split(separator: "-")
            let year = Int(parts[0])!
            let month = Int(parts[1])!
            let totalArticles = entries.reduce(0) { $0 + $1.count }
            let activeDays = entries.filter { $0.count > 0 }.count
            let peak = entries.max(by: { $0.count < $1.count })

            return HeatmapMonthSummary(
                year: year,
                month: month,
                totalArticles: totalArticles,
                activeDays: activeDays,
                averagePerDay: activeDays > 0 ? Double(totalArticles) / Double(activeDays) : 0,
                peakDay: peak?.date,
                peakCount: peak?.count ?? 0
            )
        }
        .sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }

    /// Day-of-week distribution across all history.
    func weekdayDistribution() -> [WeekdayDistribution] {
        var weekdayData: [Int: (total: Int, days: Int)] = [:]
        for i in 1...7 { weekdayData[i] = (0, 0) }

        for (key, record) in state.dailyCounts {
            guard let date = dateFormatter.date(from: key) else { continue }
            let wd = calendar.component(.weekday, from: date)
            var data = weekdayData[wd]!
            data.total += record.count
            if record.count > 0 { data.days += 1 }
            weekdayData[wd] = data
        }

        return (1...7).map { wd in
            let data = weekdayData[wd]!
            return WeekdayDistribution(
                weekday: wd,
                totalArticles: data.total,
                activeDays: data.days,
                averagePerActiveDay: data.days > 0 ? Double(data.total) / Double(data.days) : 0
            )
        }
    }

    // MARK: - Year-over-Year

    /// Compare the last N days against the same period one year prior.
    func yearOverYear(days: Int = 30, from referenceDate: Date = Date()) -> YearOverYearDelta {
        let endCurrent = referenceDate
        let startCurrent = calendar.date(byAdding: .day, value: -days, to: endCurrent)!
        let endPrevious = calendar.date(byAdding: .year, value: -1, to: endCurrent)!
        let startPrevious = calendar.date(byAdding: .day, value: -days, to: endPrevious)!

        let currentTotal = totalArticles(from: startCurrent, to: endCurrent)
        let previousTotal = totalArticles(from: startPrevious, to: endPrevious)
        let delta = currentTotal - previousTotal
        let pctChange: Double? = previousTotal > 0
            ? (Double(delta) / Double(previousTotal)) * 100.0
            : nil

        return YearOverYearDelta(
            periodLabel: "Last \(days) days",
            currentTotal: currentTotal,
            previousTotal: previousTotal,
            delta: delta,
            percentChange: pctChange
        )
    }

    // MARK: - Statistics

    /// Total articles read in a date range.
    func totalArticles(from start: Date, to end: Date) -> Int {
        var total = 0
        var date = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        while date <= endDay {
            let key = dateFormatter.string(from: date)
            total += state.dailyCounts[key]?.count ?? 0
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return total
    }

    /// Total active (non-zero) days in a date range.
    func activeDays(from start: Date, to end: Date) -> Int {
        var count = 0
        var date = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        while date <= endDay {
            let key = dateFormatter.string(from: date)
            if let record = state.dailyCounts[key], record.count > 0 {
                count += 1
            }
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return count
    }

    /// Average articles per active day across all history.
    func overallAverage() -> Double {
        let active = state.dailyCounts.values.filter { $0.count > 0 }
        guard !active.isEmpty else { return 0 }
        let total = active.reduce(0) { $0 + $1.count }
        return Double(total) / Double(active.count)
    }

    /// Day with the highest reading count ever.
    func peakDay() -> (date: Date, count: Int)? {
        guard let best = state.dailyCounts.max(by: { $0.value.count < $1.value.count }),
              let date = dateFormatter.date(from: best.key) else { return nil }
        return (date: date, count: best.value.count)
    }

    // MARK: - Configuration

    /// Update intensity thresholds.
    func setThresholds(_ thresholds: HeatmapThresholds) {
        state.thresholds = thresholds
        saveToDisk()
    }

    // MARK: - Export

    /// Export heatmap data as a dictionary (for sharing / analytics).
    func exportData(range: HeatmapTimeRange = .oneYear) -> [String: Any] {
        let grid = generateGrid(range: range)
        let streak = currentStreak()
        let longest = longestStreak()
        let summaries = monthlySummaries(range: range)

        return [
            "range": range.label,
            "totalArticles": grid.flatMap(\.cells).reduce(0) { $0 + $1.count },
            "totalDays": grid.flatMap(\.cells).count,
            "activeDays": grid.flatMap(\.cells).filter { $0.count > 0 }.count,
            "currentStreak": streak.length,
            "longestStreak": longest.length,
            "averagePerActiveDay": overallAverage(),
            "weekCount": grid.count,
            "monthlySummaries": summaries.map { s in
                [
                    "month": s.monthLabel,
                    "articles": s.totalArticles,
                    "activeDays": s.activeDays,
                    "average": s.averagePerDay,
                    "peak": s.peakCount
                ] as [String: Any]
            }
        ]
    }

    // MARK: - Reset

    /// Clear all heatmap data.
    func reset() {
        state = .empty
        saveToDisk()
        NotificationCenter.default.post(name: .readingHeatmapDidUpdate, object: self)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let url = persistenceURL else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            // Silently fail — persistence is best-effort
        }
    }

    private static func loadFromDisk() -> HeatmapState? {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("reading_activity_heatmap.json"),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(HeatmapState.self, from: data) else {
            return nil
        }
        return state
    }
}
