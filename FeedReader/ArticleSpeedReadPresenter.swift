//
//  ArticleSpeedReadPresenter.swift
//  FeedReader
//
//  Rapid Serial Visual Presentation (RSVP) speed reading engine.
//  Presents article text one word at a time at a configurable WPM,
//  enabling users to read articles 2-3x faster than normal reading.
//
//  Features:
//    - Configurable words-per-minute (100–1000 WPM, default 300)
//    - Optimal Recognition Point (ORP) calculation for each word
//    - Pause on punctuation (configurable delay multiplier)
//    - Play/pause/restart/skip-forward/skip-back controls
//    - Chunk mode: show 2–5 words at a time instead of single words
//    - Progress tracking (current position, percentage, ETA)
//    - Sentence and paragraph boundary awareness
//    - Speed adjustment during playback (faster/slower)
//    - Callback-based architecture for UI integration
//    - Session statistics (actual time vs estimated normal reading time)
//
//  Persistence: Settings via UserDefaults.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when speed read playback state changes.
    static let speedReadStateDidChange = Notification.Name("SpeedReadStateDidChangeNotification")
    /// Posted when a speed read session completes.
    static let speedReadSessionDidComplete = Notification.Name("SpeedReadSessionDidCompleteNotification")
}

// MARK: - Models

/// Playback state for the speed reader.
enum SpeedReadState: String, Codable {
    case idle
    case playing
    case paused
    case completed
}

/// A single word token with metadata for RSVP display.
struct SpeedReadToken: Codable, Equatable {
    /// The word to display.
    let word: String
    /// Index of the Optimal Recognition Point character (for centering).
    let orpIndex: Int
    /// Whether this token ends a sentence (extra pause).
    let endsSentence: Bool
    /// Whether this token ends a paragraph (longer pause).
    let endsParagraph: Bool
    /// Index in the full token array.
    let position: Int
}

/// Configuration for a speed reading session.
struct SpeedReadConfig: Codable, Equatable {
    /// Words per minute (100–1000).
    var wpm: Int
    /// Number of words to show at once (1–5).
    var chunkSize: Int
    /// Multiplier for pause duration at sentence boundaries.
    var sentencePauseMultiplier: Double
    /// Multiplier for pause duration at paragraph boundaries.
    var paragraphPauseMultiplier: Double

    static let `default` = SpeedReadConfig(
        wpm: 300,
        chunkSize: 1,
        sentencePauseMultiplier: 2.0,
        paragraphPauseMultiplier: 3.0
    )

    /// Clamp values to valid ranges.
    func validated() -> SpeedReadConfig {
        return SpeedReadConfig(
            wpm: max(100, min(1000, wpm)),
            chunkSize: max(1, min(5, chunkSize)),
            sentencePauseMultiplier: max(1.0, min(5.0, sentencePauseMultiplier)),
            paragraphPauseMultiplier: max(1.0, min(8.0, paragraphPauseMultiplier))
        )
    }
}

/// Statistics for a completed speed reading session.
struct SpeedReadSessionStats: Codable {
    let articleTitle: String
    let totalWords: Int
    let configuredWPM: Int
    let actualDurationSeconds: Double
    let estimatedNormalDurationSeconds: Double
    let speedupFactor: Double
    let completionDate: Date
    let percentRead: Double
}

// MARK: - Speed Read Presenter

/// Engine for RSVP speed reading. Tokenizes article text and presents
/// words at a configurable rate with intelligent pausing.
final class ArticleSpeedReadPresenter {

    // MARK: - Properties

    private(set) var state: SpeedReadState = .idle {
        didSet {
            onStateChange?(state)
            NotificationCenter.default.post(name: .speedReadStateDidChange, object: self)
        }
    }

    private(set) var tokens: [SpeedReadToken] = []
    private(set) var currentIndex: Int = 0
    private(set) var config: SpeedReadConfig

    private var timer: Timer?
    private var sessionStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var lastPauseTime: Date?
    private var articleTitle: String = ""

    /// Called with the current token(s) to display.
    var onDisplayToken: (([SpeedReadToken]) -> Void)?
    /// Called when playback state changes.
    var onStateChange: ((SpeedReadState) -> Void)?
    /// Called with progress (0.0–1.0).
    var onProgress: ((Double) -> Void)?
    /// Called when session completes with stats.
    var onSessionComplete: ((SpeedReadSessionStats) -> Void)?

    // MARK: - Settings Persistence

    private static let configKey = "SpeedReadConfig"

    // MARK: - Init

    init(config: SpeedReadConfig? = nil) {
        if let config = config {
            self.config = config.validated()
        } else if let data = UserDefaults.standard.data(forKey: Self.configKey),
                  let saved = try? JSONDecoder().decode(SpeedReadConfig.self, from: data) {
            self.config = saved.validated()
        } else {
            self.config = .default
        }
    }

    // MARK: - Tokenization

    /// Tokenize article text into SpeedReadTokens with ORP and boundary metadata.
    func prepare(text: String, title: String = "") {
        stop()
        articleTitle = title

        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var allTokens: [SpeedReadToken] = []
        var position = 0

        for (pIdx, paragraph) in paragraphs.enumerated() {
            let words = paragraph.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            let isLastParagraph = pIdx == paragraphs.count - 1

            for (wIdx, word) in words.enumerated() {
                let isLastWord = wIdx == words.count - 1
                let endsSentence = Self.isSentenceEnding(word)
                let endsParagraph = isLastWord && !isLastParagraph

                let token = SpeedReadToken(
                    word: word,
                    orpIndex: Self.calculateORP(word),
                    endsSentence: endsSentence,
                    endsParagraph: endsParagraph,
                    position: position
                )
                allTokens.append(token)
                position += 1
            }
        }

        tokens = allTokens
        currentIndex = 0
        state = .idle
    }

    /// Calculate the Optimal Recognition Point for a word.
    /// ORP is roughly at 25-35% of word length, biased left.
    static func calculateORP(_ word: String) -> Int {
        let len = word.count
        switch len {
        case 0...1: return 0
        case 2...5: return 1
        case 6...9: return 2
        case 10...13: return 3
        default: return 4
        }
    }

    /// Check if a word ends a sentence.
    static func isSentenceEnding(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .alphanumerics.inverted)
        guard !trimmed.isEmpty else { return false }
        let last = word.last ?? Character(" ")
        return last == "." || last == "!" || last == "?" ||
               word.hasSuffix(".\"") || word.hasSuffix("!\"") || word.hasSuffix("?\"") ||
               word.hasSuffix(".'") || word.hasSuffix("!'") || word.hasSuffix("?'")
    }

    // MARK: - Playback Controls

    /// Start or resume playback.
    func play() {
        guard !tokens.isEmpty else { return }

        if state == .paused, let pauseTime = lastPauseTime {
            totalPausedDuration += Date().timeIntervalSince(pauseTime)
            lastPauseTime = nil
        }

        if state == .idle || state == .completed {
            currentIndex = 0
            sessionStartTime = Date()
            totalPausedDuration = 0
            lastPauseTime = nil
        }

        state = .playing
        scheduleNextToken()
    }

    /// Pause playback.
    func pause() {
        guard state == .playing else { return }
        timer?.invalidate()
        timer = nil
        lastPauseTime = Date()
        state = .paused
    }

    /// Stop and reset to beginning.
    func stop() {
        timer?.invalidate()
        timer = nil
        currentIndex = 0
        sessionStartTime = nil
        totalPausedDuration = 0
        lastPauseTime = nil
        state = .idle
    }

    /// Toggle between play and pause.
    func togglePlayPause() {
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    /// Skip forward by a number of words.
    func skipForward(_ count: Int = 10) {
        currentIndex = min(currentIndex + count, tokens.count - 1)
        emitCurrentToken()
    }

    /// Skip backward by a number of words.
    func skipBackward(_ count: Int = 10) {
        currentIndex = max(currentIndex - count, 0)
        emitCurrentToken()
    }

    /// Jump to a specific position (0.0–1.0).
    func seekTo(progress: Double) {
        let clamped = max(0, min(1, progress))
        currentIndex = Int(Double(tokens.count - 1) * clamped)
        emitCurrentToken()
    }

    // MARK: - Speed Adjustment

    /// Increase WPM by increment.
    func speedUp(by increment: Int = 25) {
        config.wpm = min(1000, config.wpm + increment)
        saveConfig()
        if state == .playing {
            timer?.invalidate()
            scheduleNextToken()
        }
    }

    /// Decrease WPM by decrement.
    func slowDown(by decrement: Int = 25) {
        config.wpm = max(100, config.wpm - decrement)
        saveConfig()
        if state == .playing {
            timer?.invalidate()
            scheduleNextToken()
        }
    }

    /// Update the full config.
    func updateConfig(_ newConfig: SpeedReadConfig) {
        config = newConfig.validated()
        saveConfig()
    }

    // MARK: - Progress Info

    /// Current progress as a fraction (0.0–1.0).
    var progress: Double {
        guard !tokens.isEmpty else { return 0 }
        return Double(currentIndex) / Double(tokens.count)
    }

    /// Estimated time remaining in seconds at current WPM.
    var estimatedTimeRemaining: TimeInterval {
        let remaining = tokens.count - currentIndex
        let wordsPerSecond = Double(config.wpm) / 60.0
        return Double(remaining) / wordsPerSecond
    }

    /// Total words in the prepared text.
    var totalWords: Int { tokens.count }

    /// Current word being displayed.
    var currentToken: SpeedReadToken? {
        guard currentIndex < tokens.count else { return nil }
        return tokens[currentIndex]
    }

    // MARK: - Private

    private func scheduleNextToken() {
        guard state == .playing, currentIndex < tokens.count else { return }

        let token = tokens[currentIndex]
        let baseInterval = 60.0 / Double(config.wpm)

        var interval = baseInterval
        if token.endsParagraph {
            interval *= config.paragraphPauseMultiplier
        } else if token.endsSentence {
            interval *= config.sentencePauseMultiplier
        }

        // Longer words get slightly more time
        let lengthFactor = max(1.0, Double(token.word.count) / 5.0)
        interval *= min(lengthFactor, 1.5)

        emitCurrentToken()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.advanceToken()
        }
    }

    private func advanceToken() {
        currentIndex += config.chunkSize

        if currentIndex >= tokens.count {
            completeSession()
            return
        }

        onProgress?(progress)
        scheduleNextToken()
    }

    private func emitCurrentToken() {
        guard currentIndex < tokens.count else { return }
        let endIdx = min(currentIndex + config.chunkSize, tokens.count)
        let chunk = Array(tokens[currentIndex..<endIdx])
        onDisplayToken?(chunk)
        onProgress?(progress)
    }

    private func completeSession() {
        timer?.invalidate()
        timer = nil
        state = .completed

        guard let startTime = sessionStartTime else { return }
        let actualDuration = Date().timeIntervalSince(startTime) - totalPausedDuration
        let normalDuration = Double(tokens.count) / (238.0 / 60.0) // 238 WPM average
        let speedup = normalDuration / max(actualDuration, 1)

        let stats = SpeedReadSessionStats(
            articleTitle: articleTitle,
            totalWords: tokens.count,
            configuredWPM: config.wpm,
            actualDurationSeconds: actualDuration,
            estimatedNormalDurationSeconds: normalDuration,
            speedupFactor: speedup,
            completionDate: Date(),
            percentRead: 1.0
        )

        onSessionComplete?(stats)
        NotificationCenter.default.post(name: .speedReadSessionDidComplete, object: self, userInfo: ["stats": stats])
        saveSessionHistory(stats)
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }

    // MARK: - Session History

    private static let historyKey = "SpeedReadSessionHistory"
    private static let maxHistoryEntries = 100

    private func saveSessionHistory(_ stats: SpeedReadSessionStats) {
        var history = Self.loadHistory()
        history.insert(stats, at: 0)
        if history.count > Self.maxHistoryEntries {
            history = Array(history.prefix(Self.maxHistoryEntries))
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    /// Load past speed reading session history.
    static func loadHistory() -> [SpeedReadSessionStats] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([SpeedReadSessionStats].self, from: data) else {
            return []
        }
        return history
    }

    /// Average speedup factor across all sessions.
    static func averageSpeedup() -> Double? {
        let history = loadHistory()
        guard !history.isEmpty else { return nil }
        let total = history.reduce(0.0) { $0 + $1.speedupFactor }
        return total / Double(history.count)
    }

    /// Total time saved across all sessions (in seconds).
    static func totalTimeSaved() -> TimeInterval {
        let history = loadHistory()
        return history.reduce(0.0) { $0 + ($1.estimatedNormalDurationSeconds - $1.actualDurationSeconds) }
    }

    /// Clear all session history.
    static func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
