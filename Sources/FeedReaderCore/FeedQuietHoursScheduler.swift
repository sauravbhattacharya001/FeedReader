//
//  FeedQuietHoursScheduler.swift
//  FeedReaderCore
//
//  Learns user reading patterns and recommends quiet hours — time windows
//  when the app should suppress notifications and defer feed fetching.
//  Proactive, pattern-aware scheduling that adapts to the user's rhythm.
//

import Foundation

// MARK: - Models

/// A time-of-day slot (hour 0-23).
public struct HourSlot: Sendable, Equatable, Hashable {
    public let hour: Int // 0-23

    public init(hour: Int) {
        self.hour = max(0, min(23, hour))
    }
}

/// A contiguous quiet window.
public struct QuietWindow: Sendable, Equatable {
    public let startHour: Int
    public let endHour: Int // exclusive, wraps around midnight
    public let confidence: Double // 0.0-1.0

    public init(startHour: Int, endHour: Int, confidence: Double) {
        self.startHour = max(0, min(23, startHour))
        self.endHour = max(0, min(23, endHour))
        self.confidence = max(0.0, min(1.0, confidence))
    }

    /// Duration in hours (handles midnight wrap).
    public var durationHours: Int {
        if endHour > startHour {
            return endHour - startHour
        } else {
            return (24 - startHour) + endHour
        }
    }
}

/// Verdict for the current schedule.
public enum ScheduleVerdict: String, Sendable, CaseIterable {
    case quietNow = "quietNow"
    case activeNow = "activeNow"
    case transitioningSoon = "transitioningSoon"
    case insufficientData = "insufficientData"
}

/// Day type classification.
public enum DayType: String, Sendable, CaseIterable {
    case weekday = "weekday"
    case weekend = "weekend"
}

/// Configuration for the scheduler.
public struct QuietHoursConfig: Sendable {
    /// Minimum events needed before making recommendations.
    public let minEventsForRecommendation: Int
    /// Minimum consecutive quiet hours to form a window.
    public let minQuietWindowHours: Int
    /// Activity threshold — hours with reads below this fraction of peak are "quiet".
    public let quietThresholdFraction: Double
    /// Whether to separate weekday vs weekend patterns.
    public let separateWeekends: Bool

    public init(
        minEventsForRecommendation: Int = 20,
        minQuietWindowHours: Int = 2,
        quietThresholdFraction: Double = 0.15,
        separateWeekends: Bool = true
    ) {
        self.minEventsForRecommendation = max(5, minEventsForRecommendation)
        self.minQuietWindowHours = max(1, min(8, minQuietWindowHours))
        self.quietThresholdFraction = max(0.05, min(0.5, quietThresholdFraction))
        self.separateWeekends = separateWeekends
    }
}

/// A reading timestamp event used for pattern analysis.
public struct ReadingTimestamp: Sendable {
    public let date: Date
    public let articleId: String?

    public init(date: Date, articleId: String? = nil) {
        self.date = date
        self.articleId = articleId
    }
}

/// Full schedule report.
public struct QuietHoursReport: Sendable {
    public let weekdayQuietWindows: [QuietWindow]
    public let weekendQuietWindows: [QuietWindow]
    public let currentVerdict: ScheduleVerdict
    public let peakReadingHours: [HourSlot]
    public let quietHoursPerDay: Int
    public let totalEventsAnalyzed: Int
    public let generatedAt: Date

    /// Whether a given hour is in a quiet window for the given day type.
    public func isQuiet(hour: Int, dayType: DayType) -> Bool {
        let windows = dayType == .weekday ? weekdayQuietWindows : weekendQuietWindows
        for window in windows {
            if windowContains(window, hour: hour) {
                return true
            }
        }
        return false
    }

    private func windowContains(_ window: QuietWindow, hour: Int) -> Bool {
        if window.endHour > window.startHour {
            return hour >= window.startHour && hour < window.endHour
        } else {
            // wraps midnight
            return hour >= window.startHour || hour < window.endHour
        }
    }
}

// MARK: - Scheduler

/// Learns reading patterns and recommends quiet hours.
public final class FeedQuietHoursScheduler: @unchecked Sendable {
    private let config: QuietHoursConfig
    private let calendar: Calendar
    private let nowProvider: () -> Date

    public init(
        config: QuietHoursConfig = QuietHoursConfig(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.config = config
        self.calendar = calendar
        self.nowProvider = now
    }

    /// Analyze reading timestamps and produce a quiet hours report.
    public func analyze(events: [ReadingTimestamp]) -> QuietHoursReport {
        let now = nowProvider()

        guard events.count >= config.minEventsForRecommendation else {
            return QuietHoursReport(
                weekdayQuietWindows: [],
                weekendQuietWindows: [],
                currentVerdict: .insufficientData,
                peakReadingHours: [],
                quietHoursPerDay: 0,
                totalEventsAnalyzed: events.count,
                generatedAt: now
            )
        }

        // Build hour histograms
        var weekdayHist = [Int](repeating: 0, count: 24)
        var weekendHist = [Int](repeating: 0, count: 24)

        for event in events {
            let hour = calendar.component(.hour, from: event.date)
            let weekday = calendar.component(.weekday, from: event.date)
            let isWeekend = (weekday == 1 || weekday == 7) // Sun=1, Sat=7

            if config.separateWeekends && isWeekend {
                weekendHist[hour] += 1
            } else {
                weekdayHist[hour] += 1
            }
        }

        let weekdayWindows = findQuietWindows(histogram: weekdayHist)
        let weekendWindows: [QuietWindow]
        if config.separateWeekends {
            weekendWindows = findQuietWindows(histogram: weekendHist)
        } else {
            weekendWindows = weekdayWindows
        }

        // Find peak hours (top 3 by activity)
        let combinedHist = zip(weekdayHist, weekendHist).map { $0 + $1 }
        let sortedHours = combinedHist.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(3)
            .filter { $0.element > 0 }
            .map { HourSlot(hour: $0.offset) }

        // Current verdict
        let currentHour = calendar.component(.hour, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        let currentDayType: DayType = (currentWeekday == 1 || currentWeekday == 7) ? .weekend : .weekday
        let currentWindows = currentDayType == .weekday ? weekdayWindows : weekendWindows

        let verdict: ScheduleVerdict
        if isInQuietWindow(hour: currentHour, windows: currentWindows) {
            verdict = .quietNow
        } else if isTransitioningSoon(hour: currentHour, windows: currentWindows) {
            verdict = .transitioningSoon
        } else {
            verdict = .activeNow
        }

        // Total quiet hours per day (weekday)
        let quietCount = (0..<24).filter { h in
            weekdayWindows.contains { windowContains($0, hour: h) }
        }.count

        return QuietHoursReport(
            weekdayQuietWindows: weekdayWindows,
            weekendQuietWindows: weekendWindows,
            currentVerdict: verdict,
            peakReadingHours: Array(sortedHours),
            quietHoursPerDay: quietCount,
            totalEventsAnalyzed: events.count,
            generatedAt: now
        )
    }

    /// Check if notifications should be suppressed right now.
    public func shouldSuppressNow(events: [ReadingTimestamp]) -> Bool {
        let report = analyze(events: events)
        return report.currentVerdict == .quietNow
    }

    /// Suggest next fetch time (returns nil if should fetch now).
    public func nextFetchTime(events: [ReadingTimestamp]) -> Date? {
        let report = analyze(events: events)
        guard report.currentVerdict == .quietNow else { return nil }

        let now = nowProvider()
        let currentHour = calendar.component(.hour, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        let dayType: DayType = (currentWeekday == 1 || currentWeekday == 7) ? .weekend : .weekday
        let windows = dayType == .weekday ? report.weekdayQuietWindows : report.weekendQuietWindows

        // Find end of current quiet window
        for window in windows {
            if windowContains(window, hour: currentHour) {
                let hoursUntilEnd: Int
                if window.endHour > currentHour {
                    hoursUntilEnd = window.endHour - currentHour
                } else {
                    hoursUntilEnd = (24 - currentHour) + window.endHour
                }
                return calendar.date(byAdding: .hour, value: hoursUntilEnd, to: now)
            }
        }
        return nil
    }

    /// Format the report as markdown.
    public func formatMarkdown(report: QuietHoursReport) -> String {
        var lines = [String]()
        lines.append("## Quiet Hours Schedule")
        lines.append("")
        lines.append("**Status:** \(report.currentVerdict.rawValue)")
        lines.append("**Events analyzed:** \(report.totalEventsAnalyzed)")
        lines.append("**Quiet hours/day:** \(report.quietHoursPerDay)")
        lines.append("")

        if !report.peakReadingHours.isEmpty {
            let peakStr = report.peakReadingHours.map { formatHour($0.hour) }.joined(separator: ", ")
            lines.append("**Peak reading hours:** \(peakStr)")
            lines.append("")
        }

        if !report.weekdayQuietWindows.isEmpty {
            lines.append("### Weekday Quiet Windows")
            lines.append("")
            for window in report.weekdayQuietWindows {
                lines.append("- \(formatHour(window.startHour)) – \(formatHour(window.endHour)) (\(window.durationHours)h, confidence: \(String(format: "%.0f", window.confidence * 100))%)")
            }
            lines.append("")
        }

        if !report.weekendQuietWindows.isEmpty {
            lines.append("### Weekend Quiet Windows")
            lines.append("")
            for window in report.weekendQuietWindows {
                lines.append("- \(formatHour(window.startHour)) – \(formatHour(window.endHour)) (\(window.durationHours)h, confidence: \(String(format: "%.0f", window.confidence * 100))%)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func findQuietWindows(histogram: [Int]) -> [QuietWindow] {
        let peak = histogram.max() ?? 0
        guard peak > 0 else { return [] }

        let threshold = Double(peak) * config.quietThresholdFraction

        // Mark each hour as quiet or active
        var isQuiet = [Bool](repeating: false, count: 24)
        for h in 0..<24 {
            isQuiet[h] = Double(histogram[h]) <= threshold
        }

        // Find contiguous quiet runs (wrapping around midnight)
        var windows = [QuietWindow]()
        var visited = [Bool](repeating: false, count: 24)

        for startSearch in 0..<24 {
            guard isQuiet[startSearch] && !visited[startSearch] else { continue }

            var length = 0
            var h = startSearch
            while isQuiet[h % 24] && !visited[h % 24] && length < 24 {
                visited[h % 24] = true
                length += 1
                h += 1
            }

            if length >= config.minQuietWindowHours {
                // Confidence based on how far below threshold the hours are
                let avgActivity = (startSearch..<(startSearch + length)).reduce(0.0) { sum, idx in
                    sum + Double(histogram[idx % 24])
                } / Double(length)
                let confidence = max(0.0, min(1.0, 1.0 - (avgActivity / Double(peak))))

                let endHour = (startSearch + length) % 24
                windows.append(QuietWindow(
                    startHour: startSearch,
                    endHour: endHour,
                    confidence: confidence
                ))
            }
        }

        return windows.sorted { $0.confidence > $1.confidence }
    }

    private func isInQuietWindow(hour: Int, windows: [QuietWindow]) -> Bool {
        windows.contains { windowContains($0, hour: hour) }
    }

    private func isTransitioningSoon(hour: Int, windows: [QuietWindow]) -> Bool {
        // Within 1 hour of a quiet window starting
        let nextHour = (hour + 1) % 24
        return windows.contains { $0.startHour == nextHour }
    }

    private func windowContains(_ window: QuietWindow, hour: Int) -> Bool {
        if window.endHour > window.startHour {
            return hour >= window.startHour && hour < window.endHour
        } else {
            return hour >= window.startHour || hour < window.endHour
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h):00 \(ampm)"
    }
}
