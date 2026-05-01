//
//  FeedTemporalOptimizer.swift
//  FeedReader
//
//  Autonomous publishing-pattern analyzer that learns *when* each feed
//  publishes articles (hour-of-day, day-of-week) and recommends optimal
//  check-in windows for maximum freshness.
//
//  Key capabilities:
//  - Record article publish timestamps per feed
//  - Build hourly (0-23) and daily (Mon-Sun) frequency histograms
//  - Detect publishing rhythms: periodic, burst, round-the-clock, sporadic
//  - Identify peak publishing windows (consecutive hours with high output)
//  - Recommend optimal check-in times to catch articles within minutes
//  - Detect schedule shifts when a feed changes its publishing cadence
//  - Calculate freshness scores: how quickly the user reads after publish
//  - Fleet-wide "golden hours" — best times to open the app across all feeds
//  - Autonomous insights generation
//  - Export to JSON
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when temporal data is updated.
    static let temporalOptimizerDidUpdate = Notification.Name("FeedTemporalOptimizerDidUpdate")
    /// Posted when a schedule shift is detected for a feed.
    static let temporalScheduleShiftDetected = Notification.Name("FeedTemporalScheduleShiftDetected")
}

// MARK: - Models

/// A single recorded article publish event.
struct TemporalPublishEvent: Codable, Equatable {
    let id: String
    let feedURL: String
    let feedName: String
    let articleTitle: String
    let publishedAt: Date
    let recordedAt: Date
    /// Hour of day (0-23) in user's local timezone at publish time.
    let publishHour: Int
    /// Day of week (1=Sunday … 7=Saturday).
    let publishDayOfWeek: Int

    init(feedURL: String, feedName: String, articleTitle: String,
         publishedAt: Date, recordedAt: Date = Date(),
         calendar: Calendar = .current) {
        self.id = UUID().uuidString
        self.feedURL = feedURL
        self.feedName = feedName
        self.articleTitle = articleTitle
        self.publishedAt = publishedAt
        self.recordedAt = recordedAt
        self.publishHour = calendar.component(.hour, from: publishedAt)
        self.publishDayOfWeek = calendar.component(.weekday, from: publishedAt)
    }
}

/// Frequency histogram for a 24-hour or 7-day distribution.
struct TemporalHistogram: Equatable {
    let bucketLabels: [String]
    let counts: [Int]
    let total: Int

    var peak: (index: Int, count: Int)? {
        guard let maxCount = counts.max(), maxCount > 0,
              let idx = counts.firstIndex(of: maxCount) else { return nil }
        return (idx, maxCount)
    }

    /// Proportion of total for each bucket.
    var proportions: [Double] {
        guard total > 0 else { return counts.map { _ in 0.0 } }
        return counts.map { Double($0) / Double(total) }
    }

    /// Shannon entropy (bits) — higher = more spread out.
    var entropy: Double {
        let props = proportions.filter { $0 > 0 }
        guard !props.isEmpty else { return 0 }
        return -props.reduce(0.0) { $0 + $1 * log2($1) }
    }
}

/// Detected publishing rhythm pattern.
enum PublishingRhythm: String, Codable, CaseIterable {
    case periodic     = "Periodic"      // concentrated in specific hours/days
    case burst        = "Burst"         // many articles in short windows
    case roundTheClock = "Round-the-Clock" // spread across all hours
    case sporadic     = "Sporadic"      // irregular, no clear pattern
    case dormant      = "Dormant"       // very few recent articles

    var emoji: String {
        switch self {
        case .periodic:      return "⏰"
        case .burst:         return "💥"
        case .roundTheClock: return "🌍"
        case .sporadic:      return "🎲"
        case .dormant:       return "💤"
        }
    }

    var description: String {
        switch self {
        case .periodic:      return "Publishes on a regular schedule"
        case .burst:         return "Publishes many articles in short bursts"
        case .roundTheClock: return "Publishes throughout the day"
        case .sporadic:      return "No clear publishing pattern"
        case .dormant:       return "Rarely publishes new content"
        }
    }
}

/// A recommended check-in window.
struct CheckInRecommendation: Equatable {
    let feedURL: String
    let feedName: String
    /// Start hour (0-23).
    let startHour: Int
    /// End hour (0-23, exclusive). Can wrap around midnight.
    let endHour: Int
    /// Confidence 0-1 that checking in this window catches fresh articles.
    let confidence: Double
    /// Expected articles in this window per day.
    let expectedArticles: Double
    /// Human-readable label.
    let label: String

    var timeRangeLabel: String {
        let fmt = { (h: Int) -> String in
            let suffix = h < 12 ? "AM" : "PM"
            let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
            return "\(display) \(suffix)"
        }
        return "\(fmt(startHour)) – \(fmt(endHour))"
    }
}

/// Detected schedule shift event.
struct ScheduleShift: Codable, Equatable {
    let feedURL: String
    let feedName: String
    let detectedAt: Date
    let previousPeakHours: [Int]
    let newPeakHours: [Int]
    let shiftDescription: String
}

/// Per-feed temporal profile summary.
struct FeedTemporalProfile: Equatable {
    let feedURL: String
    let feedName: String
    let totalEvents: Int
    let rhythm: PublishingRhythm
    let hourlyHistogram: TemporalHistogram
    let dailyHistogram: TemporalHistogram
    let peakHours: [Int]
    let peakDays: [Int]
    let recommendations: [CheckInRecommendation]
    let avgFreshnessMinutes: Double?
    let insights: [String]
}

/// Fleet-wide golden hours.
struct GoldenHours: Equatable {
    let hours: [Int]
    let totalExpectedArticles: Double
    let feedsCovered: Int
    let label: String
}

/// Autonomous insight.
struct TemporalInsight: Equatable {
    let category: String
    let message: String
    let priority: Int // 1=high, 2=medium, 3=low
}

// MARK: - Persistence

struct TemporalOptimizerState: Codable {
    var events: [TemporalPublishEvent]
    var shifts: [ScheduleShift]
    var lastAnalyzedAt: Date?

    static let empty = TemporalOptimizerState(events: [], shifts: [], lastAnalyzedAt: nil)
}

// MARK: - FeedTemporalOptimizer

/// Learns feed publishing patterns and recommends optimal check-in times.
class FeedTemporalOptimizer {

    // MARK: - Configuration

    /// Maximum events retained per feed.
    static let maxEventsPerFeed = 500
    /// Maximum total events across all feeds.
    static let maxTotalEvents = 5000
    /// Minimum events to produce meaningful analysis.
    static let minEventsForAnalysis = 5
    /// Window size (hours) for peak detection.
    static let peakWindowSize = 3
    /// Entropy threshold: below this ⇒ periodic; above ⇒ spread out.
    static let periodicEntropyThreshold = 3.0
    /// Proportion threshold to qualify as a peak hour.
    static let peakProportionThreshold = 0.08
    /// Days of history to consider "recent" for shift detection.
    static let recentDays = 14

    // MARK: - State

    private(set) var state: TemporalOptimizerState
    private let dateProvider: () -> Date
    private let calendar: Calendar
    private let persistenceKey = "FeedTemporalOptimizerState"
    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard,
         dateProvider: @escaping () -> Date = { Date() },
         calendar: Calendar = .current) {
        self.defaults = defaults
        self.dateProvider = dateProvider
        self.calendar = calendar
        if let data = defaults.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode(TemporalOptimizerState.self, from: data) {
            self.state = saved
        } else {
            self.state = .empty
        }
    }

    // MARK: - Recording

    /// Record an article's publish timestamp.
    @discardableResult
    func recordPublishEvent(feedURL: String, feedName: String,
                            articleTitle: String, publishedAt: Date) -> TemporalPublishEvent {
        let event = TemporalPublishEvent(
            feedURL: feedURL, feedName: feedName,
            articleTitle: articleTitle, publishedAt: publishedAt,
            recordedAt: dateProvider(), calendar: calendar
        )
        state.events.append(event)
        enforceEventLimits()
        save()
        NotificationCenter.default.post(name: .temporalOptimizerDidUpdate, object: self)
        return event
    }

    /// Batch-record multiple events.
    func recordBatch(_ items: [(feedURL: String, feedName: String, articleTitle: String, publishedAt: Date)]) {
        for item in items {
            let event = TemporalPublishEvent(
                feedURL: item.feedURL, feedName: item.feedName,
                articleTitle: item.articleTitle, publishedAt: item.publishedAt,
                recordedAt: dateProvider(), calendar: calendar
            )
            state.events.append(event)
        }
        enforceEventLimits()
        save()
        NotificationCenter.default.post(name: .temporalOptimizerDidUpdate, object: self)
    }

    // MARK: - Analysis

    /// Build the temporal profile for a single feed.
    func profile(for feedURL: String) -> FeedTemporalProfile? {
        let events = eventsForFeed(feedURL)
        guard events.count >= Self.minEventsForAnalysis else { return nil }

        let feedName = events.last?.feedName ?? feedURL
        let hourly = buildHourlyHistogram(events)
        let daily = buildDailyHistogram(events)
        let rhythm = classifyRhythm(hourly: hourly, daily: daily, events: events)
        let peakHours = detectPeakHours(hourly)
        let peakDays = detectPeakDays(daily)
        let recs = generateRecommendations(feedURL: feedURL, feedName: feedName,
                                           hourly: hourly, peakHours: peakHours)
        let freshness = computeAvgFreshness(events)
        let insights = generateFeedInsights(feedName: feedName, rhythm: rhythm,
                                            hourly: hourly, daily: daily,
                                            peakHours: peakHours, peakDays: peakDays)

        return FeedTemporalProfile(
            feedURL: feedURL, feedName: feedName,
            totalEvents: events.count, rhythm: rhythm,
            hourlyHistogram: hourly, dailyHistogram: daily,
            peakHours: peakHours, peakDays: peakDays,
            recommendations: recs,
            avgFreshnessMinutes: freshness,
            insights: insights
        )
    }

    /// Profiles for all tracked feeds.
    func allProfiles() -> [FeedTemporalProfile] {
        let urls = Set(state.events.map { $0.feedURL })
        return urls.compactMap { profile(for: $0) }
            .sorted { $0.totalEvents > $1.totalEvents }
    }

    /// Fleet-wide golden hours — best times to open the app.
    func goldenHours(topN: Int = 3) -> GoldenHours {
        let profiles = allProfiles()
        guard !profiles.isEmpty else {
            return GoldenHours(hours: [], totalExpectedArticles: 0,
                               feedsCovered: 0, label: "Not enough data")
        }

        // Aggregate hourly counts across all feeds
        var aggregated = [Int](repeating: 0, count: 24)
        for p in profiles {
            for (i, c) in p.hourlyHistogram.counts.enumerated() {
                aggregated[i] += c
            }
        }

        // Find top N hours
        let ranked = aggregated.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(topN)

        let hours = ranked.map { $0.offset }.sorted()
        let total = ranked.reduce(0.0) { $0 + Double($1.element) }
        let feedsCovered = profiles.count

        let label = hours.isEmpty ? "No data" :
            "Best times: " + hours.map { formatHour($0) }.joined(separator: ", ")

        return GoldenHours(hours: hours, totalExpectedArticles: total,
                           feedsCovered: feedsCovered, label: label)
    }

    /// Detect schedule shifts by comparing recent vs historical patterns.
    func detectScheduleShifts() -> [ScheduleShift] {
        let now = dateProvider()
        let recentCutoff = calendar.date(byAdding: .day, value: -Self.recentDays, to: now) ?? now
        let urls = Set(state.events.map { $0.feedURL })
        var newShifts: [ScheduleShift] = []

        for url in urls {
            let allEvents = eventsForFeed(url)
            guard allEvents.count >= Self.minEventsForAnalysis * 2 else { continue }

            let recent = allEvents.filter { $0.publishedAt >= recentCutoff }
            let historical = allEvents.filter { $0.publishedAt < recentCutoff }
            guard recent.count >= Self.minEventsForAnalysis,
                  historical.count >= Self.minEventsForAnalysis else { continue }

            let recentPeaks = detectPeakHours(buildHourlyHistogram(recent))
            let historicalPeaks = detectPeakHours(buildHourlyHistogram(historical))

            // Shift detected if peaks differ significantly
            let overlap = Set(recentPeaks).intersection(Set(historicalPeaks))
            let maxPeaks = max(recentPeaks.count, historicalPeaks.count)
            guard maxPeaks > 0 else { continue }
            let overlapRatio = Double(overlap.count) / Double(maxPeaks)

            if overlapRatio < 0.5 {
                let feedName = allEvents.last?.feedName ?? url
                let shift = ScheduleShift(
                    feedURL: url, feedName: feedName, detectedAt: now,
                    previousPeakHours: historicalPeaks, newPeakHours: recentPeaks,
                    shiftDescription: "\(feedName) shifted from \(historicalPeaks.map { formatHour($0) }.joined(separator: ", ")) to \(recentPeaks.map { formatHour($0) }.joined(separator: ", "))"
                )
                newShifts.append(shift)
                state.shifts.append(shift)
            }
        }

        if !newShifts.isEmpty {
            save()
            for shift in newShifts {
                NotificationCenter.default.post(
                    name: .temporalScheduleShiftDetected, object: self,
                    userInfo: ["shift": shift]
                )
            }
        }

        return newShifts
    }

    /// Generate fleet-wide autonomous insights.
    func autonomousInsights() -> [TemporalInsight] {
        var insights: [TemporalInsight] = []
        let profiles = allProfiles()

        // Golden hours insight
        let golden = goldenHours()
        if !golden.hours.isEmpty {
            insights.append(TemporalInsight(
                category: "Golden Hours",
                message: "Open the app at \(golden.hours.map { formatHour($0) }.joined(separator: ", ")) to catch the most fresh articles across \(golden.feedsCovered) feeds.",
                priority: 1
            ))
        }

        // Dormant feeds
        let dormant = profiles.filter { $0.rhythm == .dormant }
        if !dormant.isEmpty {
            insights.append(TemporalInsight(
                category: "Dormant Feeds",
                message: "\(dormant.count) feed(s) rarely publish: \(dormant.prefix(3).map { $0.feedName }.joined(separator: ", ")). Consider unsubscribing or checking less often.",
                priority: 2
            ))
        }

        // Burst publishers
        let bursters = profiles.filter { $0.rhythm == .burst }
        if !bursters.isEmpty {
            insights.append(TemporalInsight(
                category: "Burst Publishers",
                message: "\(bursters.count) feed(s) publish in bursts: \(bursters.prefix(3).map { $0.feedName }.joined(separator: ", ")). Check right after their peak hours for best freshness.",
                priority: 2
            ))
        }

        // Weekend vs weekday imbalance
        let weekdayTotal = profiles.reduce(0) { sum, p in
            sum + (2...6).reduce(0) { $0 + p.dailyHistogram.counts[$1 - 1] }
        }
        let weekendTotal = profiles.reduce(0) { sum, p in
            sum + p.dailyHistogram.counts[0] + p.dailyHistogram.counts[6]
        }
        if weekdayTotal > 0 && weekendTotal > 0 {
            let ratio = Double(weekdayTotal) / Double(weekendTotal)
            if ratio > 5 {
                insights.append(TemporalInsight(
                    category: "Weekend Gap",
                    message: "Your feeds publish \(String(format: "%.1f", ratio))× more on weekdays than weekends. Weekends are great for catching up on longer reads.",
                    priority: 3
                ))
            }
        }

        // Night owl feeds
        let nightFeeds = profiles.filter { p in
            let nightCount = (0..<6).reduce(0) { $0 + p.hourlyHistogram.counts[$1] }
            return Double(nightCount) / Double(max(p.totalEvents, 1)) > 0.4
        }
        if !nightFeeds.isEmpty {
            insights.append(TemporalInsight(
                category: "Night Owl Feeds",
                message: "\(nightFeeds.count) feed(s) publish heavily between midnight and 6 AM: \(nightFeeds.prefix(3).map { $0.feedName }.joined(separator: ", ")).",
                priority: 3
            ))
        }

        // Schedule shifts
        if !state.shifts.isEmpty {
            let recentShifts = state.shifts.suffix(3)
            for shift in recentShifts {
                insights.append(TemporalInsight(
                    category: "Schedule Shift",
                    message: shift.shiftDescription,
                    priority: 2
                ))
            }
        }

        return insights.sorted { $0.priority < $1.priority }
    }

    // MARK: - Export

    /// Export all data as JSON.
    func exportJSON() -> Data? {
        struct Export: Codable {
            let exportedAt: String
            let totalEvents: Int
            let feedCount: Int
            let profiles: [[String: String]]
            let goldenHours: [Int]
            let shifts: [ScheduleShift]
        }

        let profiles = allProfiles().map { p -> [String: String] in
            [
                "feedURL": p.feedURL,
                "feedName": p.feedName,
                "events": "\(p.totalEvents)",
                "rhythm": p.rhythm.rawValue,
                "peakHours": p.peakHours.map { "\($0)" }.joined(separator: ","),
                "peakDays": p.peakDays.map { "\($0)" }.joined(separator: ","),
            ]
        }

        let export = Export(
            exportedAt: ISO8601DateFormatter().string(from: dateProvider()),
            totalEvents: state.events.count,
            feedCount: Set(state.events.map { $0.feedURL }).count,
            profiles: profiles,
            goldenHours: goldenHours().hours,
            shifts: state.shifts
        )

        return try? JSONEncoder().encode(export)
    }

    // MARK: - Management

    /// Remove all data for a feed.
    func removeFeed(_ feedURL: String) {
        state.events.removeAll { $0.feedURL == feedURL }
        state.shifts.removeAll { $0.feedURL == feedURL }
        save()
    }

    /// Clear all data.
    func reset() {
        state = .empty
        save()
    }

    /// Total tracked feeds.
    var trackedFeedCount: Int {
        Set(state.events.map { $0.feedURL }).count
    }

    /// All tracked feed URLs.
    var trackedFeedURLs: [String] {
        Array(Set(state.events.map { $0.feedURL })).sorted()
    }

    // MARK: - Private Helpers

    private func eventsForFeed(_ feedURL: String) -> [TemporalPublishEvent] {
        state.events.filter { $0.feedURL == feedURL }
            .sorted { $0.publishedAt < $1.publishedAt }
    }

    private func buildHourlyHistogram(_ events: [TemporalPublishEvent]) -> TemporalHistogram {
        var counts = [Int](repeating: 0, count: 24)
        for e in events { counts[e.publishHour] += 1 }
        let labels = (0..<24).map { formatHour($0) }
        return TemporalHistogram(bucketLabels: labels, counts: counts, total: events.count)
    }

    private func buildDailyHistogram(_ events: [TemporalPublishEvent]) -> TemporalHistogram {
        var counts = [Int](repeating: 0, count: 7)
        for e in events { counts[e.publishDayOfWeek - 1] += 1 }
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return TemporalHistogram(bucketLabels: labels, counts: counts, total: events.count)
    }

    private func classifyRhythm(hourly: TemporalHistogram, daily: TemporalHistogram,
                                events: [TemporalPublishEvent]) -> PublishingRhythm {
        guard events.count >= Self.minEventsForAnalysis else { return .dormant }

        // Check if dormant: fewer than 1 article per week over last 30 days
        let now = dateProvider()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let recentCount = events.filter { $0.publishedAt >= thirtyDaysAgo }.count
        if recentCount < 4 { return .dormant }

        let entropy = hourly.entropy

        // Low entropy = concentrated in few hours
        if entropy < Self.periodicEntropyThreshold {
            // Check if burst: many articles in single hours
            let maxProportion = hourly.proportions.max() ?? 0
            if maxProportion > 0.3 { return .burst }
            return .periodic
        }

        // High entropy = spread out
        if entropy > 4.0 { return .roundTheClock }

        return .sporadic
    }

    private func detectPeakHours(_ histogram: TemporalHistogram) -> [Int] {
        guard histogram.total > 0 else { return [] }
        let props = histogram.proportions
        return props.enumerated()
            .filter { $0.element >= Self.peakProportionThreshold }
            .sorted { $0.element > $1.element }
            .prefix(Self.peakWindowSize * 2)
            .map { $0.offset }
            .sorted()
    }

    private func detectPeakDays(_ histogram: TemporalHistogram) -> [Int] {
        guard histogram.total > 0 else { return [] }
        let avg = Double(histogram.total) / 7.0
        return histogram.counts.enumerated()
            .filter { Double($0.element) > avg * 1.2 }
            .sorted { $0.element > $1.element }
            .map { $0.offset + 1 } // 1-indexed weekday
    }

    private func generateRecommendations(feedURL: String, feedName: String,
                                         hourly: TemporalHistogram,
                                         peakHours: [Int]) -> [CheckInRecommendation] {
        guard !peakHours.isEmpty else { return [] }

        // Group consecutive peak hours into windows
        var windows: [[Int]] = []
        var current: [Int] = [peakHours[0]]

        for i in 1..<peakHours.count {
            if peakHours[i] == current.last! + 1 {
                current.append(peakHours[i])
            } else {
                windows.append(current)
                current = [peakHours[i]]
            }
        }
        windows.append(current)

        return windows.prefix(3).map { window in
            let start = window.first!
            let end = (window.last! + 1) % 24
            let windowCount = window.reduce(0.0) { $0 + Double(hourly.counts[$1]) }
            let confidence = min(windowCount / Double(max(hourly.total, 1)) * 2, 1.0)
            let expected = windowCount / max(Double(Self.recentDays), 1.0)

            return CheckInRecommendation(
                feedURL: feedURL, feedName: feedName,
                startHour: start, endHour: end,
                confidence: confidence, expectedArticles: expected,
                label: "Check \(feedName) at \(formatHour(start))"
            )
        }
    }

    private func computeAvgFreshness(_ events: [TemporalPublishEvent]) -> Double? {
        let withDelay = events.filter { $0.recordedAt > $0.publishedAt }
        guard !withDelay.isEmpty else { return nil }
        let totalMinutes = withDelay.reduce(0.0) {
            $0 + $1.recordedAt.timeIntervalSince($1.publishedAt) / 60.0
        }
        return totalMinutes / Double(withDelay.count)
    }

    private func generateFeedInsights(feedName: String, rhythm: PublishingRhythm,
                                      hourly: TemporalHistogram, daily: TemporalHistogram,
                                      peakHours: [Int], peakDays: [Int]) -> [String] {
        var insights: [String] = []

        insights.append("\(rhythm.emoji) \(feedName) has a \(rhythm.rawValue.lowercased()) publishing pattern.")

        if !peakHours.isEmpty {
            let peakLabels = peakHours.prefix(3).map { formatHour($0) }
            insights.append("Peak publishing hours: \(peakLabels.joined(separator: ", ")).")
        }

        if !peakDays.isEmpty {
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let labels = peakDays.prefix(3).compactMap { d -> String? in
                guard d >= 1, d <= 7 else { return nil }
                return dayNames[d - 1]
            }
            if !labels.isEmpty {
                insights.append("Most active days: \(labels.joined(separator: ", ")).")
            }
        }

        // Entropy-based spread assessment
        if hourly.entropy > 4.0 {
            insights.append("Articles are spread throughout the day — no single best check-in time.")
        } else if hourly.entropy < 2.0 {
            insights.append("Highly concentrated publishing — checking at peak hours captures most articles.")
        }

        return insights
    }

    private func formatHour(_ h: Int) -> String {
        let suffix = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display) \(suffix)"
    }

    private func enforceEventLimits() {
        // Per-feed limit
        let grouped = Dictionary(grouping: state.events) { $0.feedURL }
        var trimmed: [TemporalPublishEvent] = []
        for (_, events) in grouped {
            let sorted = events.sorted { $0.publishedAt < $1.publishedAt }
            trimmed.append(contentsOf: sorted.suffix(Self.maxEventsPerFeed))
        }
        state.events = trimmed

        // Total limit
        if state.events.count > Self.maxTotalEvents {
            state.events.sort { $0.publishedAt < $1.publishedAt }
            state.events = Array(state.events.suffix(Self.maxTotalEvents))
        }
    }

    private func save() {
        state.lastAnalyzedAt = dateProvider()
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: persistenceKey)
        }
    }
}
