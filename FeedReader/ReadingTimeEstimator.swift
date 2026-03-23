//
//  ReadingTimeEstimator.swift
//  FeedReader
//
//  Estimates reading time for articles based on word count,
//  with configurable reading speed (words per minute).
//

import Foundation

/// Estimates reading time for articles and collections of articles.
///
/// Uses word count and average reading speed (WPM) to provide
/// time estimates. Supports per-article estimates, queue totals,
/// and categorized breakdowns (quick/medium/long reads).
///
/// Usage:
/// ```swift
/// let estimator = ReadingTimeEstimator()
/// let time = estimator.estimate(text: article.body)
/// print(time.formatted) // "3 min read"
///
/// let queueTime = estimator.estimateQueue(stories)
/// print(queueTime.formattedTotal) // "About 45 minutes"
/// ```
class ReadingTimeEstimator {
    
    // MARK: - Reading Speed Presets
    
    /// Common reading speed presets in words per minute.
    enum ReadingSpeed: Int {
        case slow = 150
        case average = 200
        case fast = 300
        case skimming = 450
        
        var label: String {
            switch self {
            case .slow: return "Slow"
            case .average: return "Average"
            case .fast: return "Fast"
            case .skimming: return "Skimming"
            }
        }
    }
    
    // MARK: - Result Types
    
    /// Estimated reading time for a single article.
    struct Estimate {
        /// Number of words in the text.
        let wordCount: Int
        /// Estimated reading time in seconds.
        let seconds: Int
        /// Reading speed used (words per minute).
        let wordsPerMinute: Int
        
        /// Minutes component (rounded up for display).
        var minutes: Int {
            return max(1, Int(ceil(Double(seconds) / 60.0)))
        }
        
        /// Human-readable time string.
        var formatted: String {
            if minutes < 1 {
                return "< 1 min read"
            } else if minutes == 1 {
                return "1 min read"
            } else {
                return "\(minutes) min read"
            }
        }
        
        /// Category based on estimated time.
        var category: ReadCategory {
            switch minutes {
            case 0...2: return .quick
            case 3...7: return .medium
            default: return .long
            }
        }
    }
    
    /// Reading time category for filtering/sorting.
    enum ReadCategory: String {
        case quick = "Quick Read"
        case medium = "Medium Read"
        case long = "Long Read"
        
        var emoji: String {
            switch self {
            case .quick: return "⚡"
            case .medium: return "📖"
            case .long: return "📚"
            }
        }
    }
    
    /// Summary of reading time for a queue of articles.
    struct QueueEstimate {
        /// Individual article estimates.
        let articles: [(story: Story, estimate: Estimate)]
        /// Total seconds for all articles.
        let totalSeconds: Int
        /// Number of articles.
        let count: Int
        
        /// Total minutes (rounded).
        var totalMinutes: Int {
            return max(1, Int(ceil(Double(totalSeconds) / 60.0)))
        }
        
        /// Human-readable total time.
        var formattedTotal: String {
            if totalMinutes < 60 {
                return "About \(totalMinutes) minute\(totalMinutes == 1 ? "" : "s")"
            } else {
                let hours = totalMinutes / 60
                let mins = totalMinutes % 60
                if mins == 0 {
                    return "About \(hours) hour\(hours == 1 ? "" : "s")"
                }
                return "About \(hours)h \(mins)m"
            }
        }
        
        /// Breakdown by reading category.
        var categoryBreakdown: [ReadCategory: Int] {
            var breakdown: [ReadCategory: Int] = [.quick: 0, .medium: 0, .long: 0]
            for (_, estimate) in articles {
                breakdown[estimate.category, default: 0] += 1
            }
            return breakdown
        }
        
        /// Articles sorted shortest to longest.
        var sortedByTime: [(story: Story, estimate: Estimate)] {
            return articles.sorted { $0.estimate.seconds < $1.estimate.seconds }
        }
        
        /// Articles that fit within a given time budget (in minutes).
        func articlesWithin(minutes budget: Int) -> [(story: Story, estimate: Estimate)] {
            var remaining = budget * 60
            var result: [(story: Story, estimate: Estimate)] = []
            for item in sortedByTime {
                if item.estimate.seconds <= remaining {
                    result.append(item)
                    remaining -= item.estimate.seconds
                }
            }
            return result
        }
    }
    
    // MARK: - Properties
    
    /// Words per minute for estimation.
    private(set) var wordsPerMinute: Int
    
    /// Additional seconds per image in an article.
    private let secondsPerImage: Int = 12
    
    // MARK: - Initialization
    
    /// Creates an estimator with a specific reading speed.
    /// - Parameter speed: Reading speed preset (default: .average / 200 WPM).
    init(speed: ReadingSpeed = .average) {
        self.wordsPerMinute = speed.rawValue
    }
    
    /// Creates an estimator with a custom WPM.
    /// - Parameter wordsPerMinute: Custom words per minute (clamped to 50-1000).
    init(wordsPerMinute: Int) {
        self.wordsPerMinute = max(50, min(1000, wordsPerMinute))
    }
    
    // MARK: - Estimation
    
    /// Estimates reading time for a text string.
    /// - Parameters:
    ///   - text: The article body text.
    ///   - imageCount: Number of images in the article (adds time per image).
    /// - Returns: An `Estimate` with word count, seconds, and formatted output.
    func estimate(text: String, imageCount: Int = 0) -> Estimate {
        let words = countWords(in: text)
        let readingSeconds = Int(ceil(Double(words) / Double(wordsPerMinute) * 60.0))
        let imageSeconds = imageCount * secondsPerImage
        let totalSeconds = readingSeconds + imageSeconds
        
        return Estimate(
            wordCount: words,
            seconds: totalSeconds,
            wordsPerMinute: wordsPerMinute
        )
    }
    
    /// Estimates reading time for a Story.
    /// - Parameter story: The story to estimate.
    /// - Returns: An `Estimate` for the story's body text.
    func estimate(story: Story) -> Estimate {
        let imageCount = story.imagePath != nil ? 1 : 0
        return estimate(text: story.body, imageCount: imageCount)
    }
    
    /// Estimates total reading time for a queue of stories.
    /// - Parameter stories: Array of stories to estimate.
    /// - Returns: A `QueueEstimate` with per-article and total times.
    func estimateQueue(_ stories: [Story]) -> QueueEstimate {
        let estimates = stories.map { story in
            (story: story, estimate: estimate(story: story))
        }
        let totalSeconds = estimates.reduce(0) { $0 + $1.estimate.seconds }
        
        return QueueEstimate(
            articles: estimates,
            totalSeconds: totalSeconds,
            count: stories.count
        )
    }
    
    /// Updates the reading speed.
    /// - Parameter speed: New reading speed preset.
    func setSpeed(_ speed: ReadingSpeed) {
        self.wordsPerMinute = speed.rawValue
    }
    
    /// Updates the reading speed with a custom WPM.
    /// - Parameter wpm: Custom words per minute (clamped to 50-1000).
    func setSpeed(wordsPerMinute wpm: Int) {
        self.wordsPerMinute = max(50, min(1000, wpm))
    }
    
    // MARK: - Word Counting
    
    /// Counts words in a string using natural language word boundaries.
    /// Falls back to whitespace splitting if needed.
    private func countWords(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        
        // Use component separation by whitespace and newlines,
        // filtering empty components for accuracy.
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }
}
