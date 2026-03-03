//
//  ArticleSentimentAnalyzer.swift
//  FeedReader
//
//  Analyzes article text for emotional tone and sentiment using
//  keyword-based lexicon scoring. Provides an overall sentiment
//  classification (positive/negative/neutral/mixed), per-sentence
//  breakdown, and dominant emotion detection.
//
//  Uses a curated sentiment lexicon with ~200 positive and ~200
//  negative terms plus modifier handling (negation, intensifiers).
//  All methods are pure and stateless — no external dependencies.
//

import Foundation

// MARK: - Result Models

/// Overall sentiment classification for an article.
enum SentimentLabel: String, CaseIterable {
    case veryPositive = "Very Positive"
    case positive = "Positive"
    case slightlyPositive = "Slightly Positive"
    case neutral = "Neutral"
    case slightlyNegative = "Slightly Negative"
    case negative = "Negative"
    case veryNegative = "Very Negative"
    case mixed = "Mixed"

    /// Short emoji for UI display.
    var emoji: String {
        switch self {
        case .veryPositive: return "😄"
        case .positive: return "🙂"
        case .slightlyPositive: return "🙂"
        case .neutral: return "😐"
        case .slightlyNegative: return "😕"
        case .negative: return "😟"
        case .veryNegative: return "😢"
        case .mixed: return "🎭"
        }
    }
}

/// Dominant emotion detected in the text.
enum DominantEmotion: String, CaseIterable {
    case joy = "Joy"
    case trust = "Trust"
    case anticipation = "Anticipation"
    case surprise = "Surprise"
    case fear = "Fear"
    case sadness = "Sadness"
    case anger = "Anger"
    case disgust = "Disgust"
    case none = "None"

    var emoji: String {
        switch self {
        case .joy: return "😊"
        case .trust: return "🤝"
        case .anticipation: return "🔮"
        case .surprise: return "😮"
        case .fear: return "😨"
        case .sadness: return "😢"
        case .anger: return "😠"
        case .disgust: return "🤢"
        case .none: return "😐"
        }
    }
}

/// Sentiment analysis result for an article.
struct SentimentResult {
    /// Normalized sentiment score from -1.0 (most negative) to 1.0 (most positive).
    let score: Double
    /// Overall sentiment classification.
    let label: SentimentLabel
    /// Number of positive words found.
    let positiveWordCount: Int
    /// Number of negative words found.
    let negativeWordCount: Int
    /// Ratio of sentiment-bearing words to total words.
    let subjectivity: Double
    /// Dominant emotion detected.
    let dominantEmotion: DominantEmotion
    /// Per-sentence sentiment scores (for sparkline / detail views).
    let sentenceSentiments: [Double]
    /// Top positive terms found (up to 5).
    let topPositiveTerms: [String]
    /// Top negative terms found (up to 5).
    let topNegativeTerms: [String]
    /// Total words analyzed.
    let wordCount: Int
}

// MARK: - Analyzer

/// Stateless sentiment analyzer using keyword-based lexicon scoring.
///
/// Usage:
/// ```swift
/// let result = ArticleSentimentAnalyzer.analyze("Great article about amazing discoveries!")
/// print(result.label)    // "Positive"
/// print(result.score)    // 0.65
/// print(result.emoji)    // "🙂"
/// ```
class ArticleSentimentAnalyzer {

    // MARK: - Sentiment Lexicon

    /// Positive words with intensity weights (0.0-1.0).
    /// Curated for news/article context — avoids ambiguous terms.
    static let positiveLexicon: [String: Double] = [
        // Strong positive (0.8-1.0)
        "excellent": 0.9, "outstanding": 0.9, "brilliant": 0.9,
        "extraordinary": 0.9, "phenomenal": 0.9, "exceptional": 0.9,
        "magnificent": 0.9, "superb": 0.9, "triumph": 0.9,
        "breakthrough": 0.85, "revolutionary": 0.85, "remarkable": 0.85,
        "incredible": 0.85, "wonderful": 0.85, "fantastic": 0.85,
        "amazing": 0.85, "impressive": 0.8, "inspiring": 0.8,
        "thriving": 0.8, "celebrate": 0.8, "victory": 0.8,

        // Moderate positive (0.5-0.7)
        "great": 0.7, "good": 0.6, "positive": 0.6, "successful": 0.7,
        "beneficial": 0.7, "promising": 0.65, "innovative": 0.7,
        "effective": 0.65, "efficient": 0.6, "progress": 0.65,
        "growth": 0.6, "improve": 0.65, "improved": 0.65,
        "improvement": 0.65, "advance": 0.65, "achievement": 0.7,
        "accomplish": 0.65, "accomplish": 0.65, "award": 0.6,
        "praise": 0.65, "recommend": 0.6, "advantage": 0.6,
        "opportunity": 0.55, "solution": 0.55, "support": 0.5,
        "helpful": 0.6, "valuable": 0.65, "reliable": 0.6,
        "strong": 0.55, "prosper": 0.7, "flourish": 0.7,
        "optimistic": 0.65, "confident": 0.6, "delight": 0.75,
        "enjoy": 0.6, "pleased": 0.6, "excited": 0.65,
        "enthusiasm": 0.65, "hope": 0.55, "hopeful": 0.6,
        "encourage": 0.6, "encouraging": 0.65, "empower": 0.65,

        // Mild positive (0.3-0.5)
        "nice": 0.45, "fine": 0.35, "okay": 0.3, "fair": 0.35,
        "adequate": 0.3, "stable": 0.4, "steady": 0.4,
        "comfortable": 0.45, "safe": 0.45, "secure": 0.45,
        "calm": 0.4, "peaceful": 0.5, "pleasant": 0.5,
        "satisfy": 0.5, "satisfied": 0.5, "agree": 0.4,
        "accept": 0.35, "welcome": 0.5, "gain": 0.45,
        "win": 0.55, "succeed": 0.6, "recover": 0.5,
        "resilient": 0.55, "robust": 0.5, "boost": 0.55,
    ]

    /// Negative words with intensity weights (0.0-1.0).
    static let negativeLexicon: [String: Double] = [
        // Strong negative (0.8-1.0)
        "terrible": 0.9, "horrible": 0.9, "catastrophic": 0.95,
        "devastating": 0.9, "disastrous": 0.9, "tragic": 0.9,
        "atrocious": 0.9, "appalling": 0.9, "dreadful": 0.85,
        "crisis": 0.8, "collapse": 0.85, "destruction": 0.9,
        "lethal": 0.9, "fatal": 0.9, "killed": 0.85,
        "massacre": 0.95, "genocide": 0.95, "terrorist": 0.9,
        "corruption": 0.8, "scandal": 0.8, "fraud": 0.85,

        // Moderate negative (0.5-0.7)
        "bad": 0.6, "poor": 0.6, "negative": 0.55, "fail": 0.7,
        "failure": 0.7, "problem": 0.55, "issue": 0.4,
        "concern": 0.45, "risk": 0.5, "danger": 0.65,
        "threat": 0.6, "harmful": 0.65, "damage": 0.65,
        "decline": 0.6, "decrease": 0.5, "loss": 0.6,
        "lose": 0.55, "deficit": 0.55, "debt": 0.5,
        "recession": 0.7, "inflation": 0.5, "unemployment": 0.6,
        "conflict": 0.6, "dispute": 0.5, "controversy": 0.55,
        "criticism": 0.5, "criticized": 0.55, "oppose": 0.5,
        "reject": 0.55, "ban": 0.55, "restrict": 0.5,
        "struggle": 0.55, "suffer": 0.65, "pain": 0.6,
        "anxious": 0.55, "anxiety": 0.6, "stress": 0.55,
        "frustrated": 0.6, "angry": 0.65, "outrage": 0.7,
        "alarming": 0.65, "warning": 0.5, "vulnerable": 0.55,
        "exploit": 0.6, "abuse": 0.7, "violence": 0.75,

        // Mild negative (0.3-0.5)
        "difficult": 0.4, "hard": 0.35, "challenging": 0.35,
        "slow": 0.35, "delay": 0.4, "obstacle": 0.45,
        "complain": 0.45, "complaint": 0.45, "disappoint": 0.55,
        "disappointing": 0.55, "unfortunate": 0.5, "mistake": 0.5,
        "error": 0.45, "bug": 0.4, "flaw": 0.45,
        "weak": 0.45, "limited": 0.35, "lack": 0.4,
        "miss": 0.35, "missing": 0.4, "confuse": 0.4,
        "unclear": 0.35, "doubt": 0.45, "uncertain": 0.4,
    ]

    /// Emotion lexicon — maps words to primary emotions.
    static let emotionLexicon: [String: DominantEmotion] = [
        // Joy
        "happy": .joy, "joy": .joy, "delight": .joy, "celebrate": .joy,
        "wonderful": .joy, "fantastic": .joy, "cheerful": .joy,
        "pleased": .joy, "excited": .joy, "thrilled": .joy,
        "laugh": .joy, "smile": .joy, "fun": .joy, "enjoy": .joy,

        // Trust
        "trust": .trust, "reliable": .trust, "honest": .trust,
        "faithful": .trust, "loyal": .trust, "secure": .trust,
        "confident": .trust, "dependable": .trust, "credible": .trust,
        "integrity": .trust, "transparent": .trust,

        // Anticipation
        "anticipate": .anticipation, "expect": .anticipation,
        "hope": .anticipation, "future": .anticipation,
        "upcoming": .anticipation, "promise": .anticipation,
        "plan": .anticipation, "prepare": .anticipation,
        "launch": .anticipation, "announce": .anticipation,

        // Surprise
        "surprise": .surprise, "unexpected": .surprise,
        "shocking": .surprise, "astonishing": .surprise,
        "remarkable": .surprise, "unprecedented": .surprise,
        "sudden": .surprise, "unbelievable": .surprise,

        // Fear
        "fear": .fear, "afraid": .fear, "terrified": .fear,
        "panic": .fear, "horror": .fear, "scared": .fear,
        "alarming": .fear, "threat": .fear, "danger": .fear,
        "risk": .fear, "vulnerable": .fear, "anxious": .fear,

        // Sadness
        "sad": .sadness, "sorrow": .sadness, "grief": .sadness,
        "mourn": .sadness, "tragic": .sadness, "loss": .sadness,
        "lonely": .sadness, "depressed": .sadness, "heartbreak": .sadness,
        "miss": .sadness, "regret": .sadness, "unfortunate": .sadness,

        // Anger
        "angry": .anger, "furious": .anger, "outrage": .anger,
        "rage": .anger, "hostile": .anger, "aggression": .anger,
        "frustrated": .anger, "resent": .anger, "hatred": .anger,
        "condemn": .anger, "protest": .anger, "revolt": .anger,

        // Disgust
        "disgust": .disgust, "repulsive": .disgust, "revolting": .disgust,
        "vile": .disgust, "corrupt": .disgust, "filthy": .disgust,
        "toxic": .disgust, "contaminate": .disgust, "pollute": .disgust,
        "offensive": .disgust, "obscene": .disgust,
    ]

    /// Negation words that flip the sentiment of the following word.
    static let negators: Set<String> = [
        "not", "no", "never", "neither", "nobody", "nothing",
        "nowhere", "nor", "cannot", "can't", "don't", "doesn't",
        "didn't", "won't", "wouldn't", "shouldn't", "couldn't",
        "isn't", "aren't", "wasn't", "weren't", "hasn't", "haven't",
        "hardly", "barely", "scarcely", "seldom", "rarely",
    ]

    /// Intensifier words that amplify the sentiment of the following word.
    static let intensifiers: [String: Double] = [
        "very": 1.3, "extremely": 1.5, "incredibly": 1.5,
        "absolutely": 1.4, "completely": 1.3, "totally": 1.3,
        "utterly": 1.4, "highly": 1.3, "deeply": 1.3,
        "really": 1.2, "so": 1.2, "quite": 1.1,
        "particularly": 1.2, "especially": 1.3, "remarkably": 1.3,
        "enormously": 1.4, "tremendously": 1.4, "significantly": 1.2,
    ]

    /// Diminisher words that reduce sentiment intensity.
    static let diminishers: [String: Double] = [
        "somewhat": 0.7, "slightly": 0.6, "a bit": 0.7,
        "barely": 0.5, "marginally": 0.6, "partly": 0.7,
        "mildly": 0.6, "moderately": 0.8, "fairly": 0.8,
        "rather": 0.8, "kind of": 0.6, "sort of": 0.6,
    ]

    // MARK: - Analysis

    /// Analyze the sentiment of the given text.
    ///
    /// - Parameter text: The article body text to analyze.
    /// - Returns: A `SentimentResult` with scores, classification, and details.
    static func analyze(_ text: String) -> SentimentResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SentimentResult(
                score: 0, label: .neutral, positiveWordCount: 0,
                negativeWordCount: 0, subjectivity: 0,
                dominantEmotion: .none, sentenceSentiments: [],
                topPositiveTerms: [], topNegativeTerms: [], wordCount: 0
            )
        }

        let sentences = splitSentences(text)
        var totalPositiveScore: Double = 0
        var totalNegativeScore: Double = 0
        var positiveCount = 0
        var negativeCount = 0
        var emotionCounts: [DominantEmotion: Int] = [:]
        var sentenceSentiments: [Double] = []
        var positiveTerms: [String: Double] = [:]
        var negativeTerms: [String: Double] = [:]
        var totalWords = 0

        for sentence in sentences {
            let (sentScore, posCount, negCount, posTerms, negTerms, wc, emotions) =
                analyzeSentence(sentence)
            sentenceSentiments.append(sentScore)
            positiveCount += posCount
            negativeCount += negCount
            totalWords += wc

            for (term, score) in posTerms {
                positiveTerms[term, default: 0] += score
                totalPositiveScore += score
            }
            for (term, score) in negTerms {
                negativeTerms[term, default: 0] += score
                totalNegativeScore += score
            }
            for (emotion, count) in emotions {
                emotionCounts[emotion, default: 0] += count
            }
        }

        // Normalize score to -1.0 ... 1.0
        let rawScore = totalPositiveScore - totalNegativeScore
        let magnitude = totalPositiveScore + totalNegativeScore
        let normalizedScore: Double
        if magnitude > 0 {
            normalizedScore = max(-1.0, min(1.0, rawScore / magnitude))
        } else {
            normalizedScore = 0
        }

        // Determine if sentiment is mixed (lots of both positive and negative)
        let label = classifySentiment(
            score: normalizedScore,
            positiveCount: positiveCount,
            negativeCount: negativeCount
        )

        // Subjectivity: ratio of sentiment-bearing words to total
        let sentimentWordCount = positiveCount + negativeCount
        let subjectivity = totalWords > 0
            ? min(1.0, Double(sentimentWordCount) / Double(totalWords))
            : 0

        // Dominant emotion
        let dominantEmotion = emotionCounts
            .max(by: { $0.value < $1.value })?.key ?? .none

        // Top terms (sorted by accumulated score, take top 5)
        let topPos = positiveTerms.sorted { $0.value > $1.value }
            .prefix(5).map { $0.key }
        let topNeg = negativeTerms.sorted { $0.value > $1.value }
            .prefix(5).map { $0.key }

        return SentimentResult(
            score: (normalizedScore * 100).rounded() / 100,
            label: label,
            positiveWordCount: positiveCount,
            negativeWordCount: negativeCount,
            subjectivity: (subjectivity * 100).rounded() / 100,
            dominantEmotion: dominantEmotion,
            sentenceSentiments: sentenceSentiments,
            topPositiveTerms: Array(topPos),
            topNegativeTerms: Array(topNeg),
            wordCount: totalWords
        )
    }

    // MARK: - Private Helpers

    /// Split text into sentences using punctuation boundaries.
    static func splitSentences(_ text: String) -> [String] {
        // Split on sentence-ending punctuation followed by whitespace or end
        let pattern = "[.!?]+[\\s]+|[.!?]+$"
        let parts = text.components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                guard let regex = try? NSRegularExpression(pattern: pattern) else {
                    return [line]
                }
                let nsRange = NSRange(line.startIndex..., in: line)
                var sentences: [String] = []
                var lastEnd = line.startIndex

                regex.enumerateMatches(in: line, range: nsRange) { match, _, _ in
                    guard let matchRange = match?.range,
                          let range = Range(matchRange, in: line) else { return }
                    let sentence = String(line[lastEnd..<range.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty { sentences.append(sentence) }
                    lastEnd = range.upperBound
                }

                // Remaining text after last punctuation
                let remaining = String(line[lastEnd...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !remaining.isEmpty { sentences.append(remaining) }

                return sentences
            }

        return parts.filter { !$0.isEmpty }
    }

    /// Analyze a single sentence for sentiment.
    /// Returns (score, posCount, negCount, posTerms, negTerms, wordCount, emotions).
    private static func analyzeSentence(_ sentence: String)
        -> (Double, Int, Int, [String: Double], [String: Double], Int, [DominantEmotion: Int])
    {
        let words = tokenize(sentence)
        var posScore: Double = 0
        var negScore: Double = 0
        var posCount = 0
        var negCount = 0
        var posTerms: [String: Double] = [:]
        var negTerms: [String: Double] = [:]
        var emotions: [DominantEmotion: Int] = [:]
        var modifier: Double = 1.0
        var negated = false

        for (i, word) in words.enumerated() {
            let lower = word.lowercased()

            // Check negation
            if negators.contains(lower) {
                negated = true
                continue
            }

            // Check intensifiers
            if let intensity = intensifiers[lower] {
                modifier *= intensity
                continue
            }

            // Check diminishers
            if let diminish = diminishers[lower] {
                modifier *= diminish
                continue
            }

            // Check emotion
            if let emotion = emotionLexicon[lower] {
                emotions[emotion, default: 0] += 1
            }

            // Score the word
            if let posWeight = positiveLexicon[lower] {
                let adjusted = posWeight * modifier
                if negated {
                    negScore += adjusted
                    negCount += 1
                    negTerms[lower, default: 0] += adjusted
                } else {
                    posScore += adjusted
                    posCount += 1
                    posTerms[lower, default: 0] += adjusted
                }
                negated = false
                modifier = 1.0
            } else if let negWeight = negativeLexicon[lower] {
                let adjusted = negWeight * modifier
                if negated {
                    posScore += adjusted * 0.5  // Negated negative is weakly positive
                    posCount += 1
                    posTerms[lower, default: 0] += adjusted * 0.5
                } else {
                    negScore += adjusted
                    negCount += 1
                    negTerms[lower, default: 0] += adjusted
                }
                negated = false
                modifier = 1.0
            } else {
                // Non-sentiment word: reset negation after 2 words
                if negated && i > 0 {
                    let prevIdx = i - 1
                    if prevIdx > 0 {
                        let prevPrev = words[prevIdx - 1].lowercased()
                        if !negators.contains(prevPrev) {
                            negated = false
                        }
                    }
                }
                modifier = 1.0
            }
        }

        // Sentence-level score normalized by word count
        let sentScore: Double
        if words.count > 0 {
            sentScore = max(-1.0, min(1.0, (posScore - negScore) / max(posScore + negScore, 1)))
        } else {
            sentScore = 0
        }

        return (sentScore, posCount, negCount, posTerms, negTerms, words.count, emotions)
    }

    /// Tokenize text into lowercase words, stripping punctuation.
    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Classify the overall sentiment based on score and word counts.
    private static func classifySentiment(
        score: Double, positiveCount: Int, negativeCount: Int
    ) -> SentimentLabel {
        // Detect mixed sentiment: significant amounts of both
        let total = positiveCount + negativeCount
        if total >= 4 {
            let minRatio = Double(min(positiveCount, negativeCount)) / Double(total)
            if minRatio > 0.35 && abs(score) < 0.3 {
                return .mixed
            }
        }

        switch score {
        case 0.6...: return .veryPositive
        case 0.3..<0.6: return .positive
        case 0.1..<0.3: return .slightlyPositive
        case -0.1..<0.1: return .neutral
        case -0.3 ..< -0.1: return .slightlyNegative
        case -0.6 ..< -0.3: return .negative
        default: return .veryNegative
        }
    }
}
