//
//  ArticleBiasDetector.swift
//  FeedReader
//
//  Analyzes article text for media bias indicators including loaded
//  language, emotional manipulation, hedging, source attribution,
//  generalization, and framing patterns. Produces a composite bias
//  score with per-dimension breakdowns and flagged phrases.
//
//  All methods are pure and stateless — no external dependencies.
//  Uses curated lexicons and heuristic pattern matching.
//

import Foundation

// MARK: - Result Models

/// A specific bias indicator found in the text.
struct BiasFlag: Codable, Equatable {
    let phrase: String
    let category: BiasCategory
    let severity: BiasSeverity
    let sentenceIndex: Int
    let suggestion: String?
}

/// Categories of bias detected.
enum BiasCategory: String, Codable, CaseIterable {
    case loadedLanguage = "Loaded Language"
    case emotionalAppeal = "Emotional Appeal"
    case unattributedClaim = "Unattributed Claim"
    case overgeneralization = "Overgeneralization"
    case hedging = "Hedging"
    case adverbialBias = "Adverbial Bias"
    case falseBalance = "False Balance"
    case labelBias = "Label Bias"

    var emoji: String {
        switch self {
        case .loadedLanguage: return "⚡"
        case .emotionalAppeal: return "💔"
        case .unattributedClaim: return "❓"
        case .overgeneralization: return "🌐"
        case .hedging: return "🤷"
        case .adverbialBias: return "📢"
        case .falseBalance: return "⚖️"
        case .labelBias: return "🏷️"
        }
    }

    var description: String {
        switch self {
        case .loadedLanguage: return "Words with strong connotations that influence perception"
        case .emotionalAppeal: return "Phrases designed to trigger emotional rather than rational response"
        case .unattributedClaim: return "Assertions without clear sourcing"
        case .overgeneralization: return "Sweeping statements without nuance"
        case .hedging: return "Vague qualifiers that obscure certainty"
        case .adverbialBias: return "Adverbs that editorialize in news reporting"
        case .falseBalance: return "Implying equal validity to unequal positions"
        case .labelBias: return "Politically or emotionally charged labels"
        }
    }
}

/// Severity of a bias flag.
enum BiasSeverity: String, Codable, CaseIterable, Comparable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: BiasSeverity, rhs: BiasSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    var emoji: String {
        switch self {
        case .low: return "🟡"
        case .medium: return "🟠"
        case .high: return "🔴"
        }
    }
}

/// Overall bias assessment level.
enum BiasLevel: String, Codable, CaseIterable {
    case minimal = "Minimal Bias"
    case slight = "Slight Bias"
    case moderate = "Moderate Bias"
    case significant = "Significant Bias"
    case heavy = "Heavy Bias"

    var emoji: String {
        switch self {
        case .minimal: return "✅"
        case .slight: return "🟢"
        case .moderate: return "🟡"
        case .significant: return "🟠"
        case .heavy: return "🔴"
        }
    }
}

/// Per-category score breakdown.
struct BiasDimensionScore: Codable {
    let category: BiasCategory
    let score: Double     // 0.0–1.0
    let flagCount: Int
}

/// Full bias analysis result.
struct BiasReport: Codable {
    let overallScore: Double       // 0.0 (unbiased) – 1.0 (heavily biased)
    let level: BiasLevel
    let flags: [BiasFlag]
    let dimensionScores: [BiasDimensionScore]
    let sentenceCount: Int
    let wordCount: Int
    let flagDensity: Double        // flags per 100 words
    let topCategories: [BiasCategory]
    let summary: String
}

// MARK: - Detector

/// Stateless media bias detector using lexicon-based heuristics.
struct ArticleBiasDetector {

    // MARK: - Public API

    /// Analyze the given text for bias indicators.
    static func analyze(_ text: String) -> BiasReport {
        guard !text.isEmpty else { return emptyReport }

        let sentences = splitSentences(text)
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let wordCount = words.count
        let lower = text.lowercased()

        var flags: [BiasFlag] = []

        for (idx, sentence) in sentences.enumerated() {
            let sl = sentence.lowercased()
            flags.append(contentsOf: detectLoadedLanguage(sl, sentenceIndex: idx))
            flags.append(contentsOf: detectEmotionalAppeal(sl, sentenceIndex: idx))
            flags.append(contentsOf: detectUnattributedClaims(sl, sentenceIndex: idx))
            flags.append(contentsOf: detectOvergeneralization(sl, sentenceIndex: idx))
            flags.append(contentsOf: detectHedging(sl, sentenceIndex: idx))
            flags.append(contentsOf: detectAdverbialBias(sl, sentenceIndex: idx))
            flags.append(contentsOf: detectFalseBalance(sl, sentenceIndex: idx))
            flags.append(contentsOf: detectLabelBias(sl, sentenceIndex: idx))
        }

        // Deduplicate flags with same phrase & sentence
        var seen = Set<String>()
        flags = flags.filter {
            let key = "\($0.sentenceIndex)|\($0.phrase)|\($0.category.rawValue)"
            return seen.insert(key).inserted
        }

        let dimensionScores = computeDimensionScores(flags: flags, sentenceCount: sentences.count)
        let overallScore = computeOverallScore(dimensionScores)
        let level = classifyLevel(overallScore)
        let density = wordCount > 0 ? Double(flags.count) / Double(wordCount) * 100.0 : 0
        let topCats = dimensionScores
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map { $0.category }

        let summary = generateSummary(level: level, flags: flags, topCategories: topCats, wordCount: wordCount)

        return BiasReport(
            overallScore: overallScore,
            level: level,
            flags: flags,
            dimensionScores: dimensionScores,
            sentenceCount: sentences.count,
            wordCount: wordCount,
            flagDensity: round(density * 100) / 100,
            topCategories: topCats,
            summary: summary
        )
    }

    /// Quick check — returns just the bias level.
    static func quickCheck(_ text: String) -> BiasLevel {
        analyze(text).level
    }

    /// Compare bias profiles of two articles.
    static func compare(_ textA: String, _ textB: String) -> (reportA: BiasReport, reportB: BiasReport, delta: Double) {
        let a = analyze(textA)
        let b = analyze(textB)
        return (a, b, abs(a.overallScore - b.overallScore))
    }

    /// Export report as formatted text.
    static func exportText(_ report: BiasReport) -> String {
        var lines: [String] = []
        lines.append("═══ BIAS ANALYSIS REPORT ═══")
        lines.append("")
        lines.append("\(report.level.emoji) Overall: \(report.level.rawValue) (score: \(String(format: "%.2f", report.overallScore)))")
        lines.append("Words: \(report.wordCount) | Sentences: \(report.sentenceCount) | Flags: \(report.flags.count) (\(String(format: "%.1f", report.flagDensity)) per 100 words)")
        lines.append("")

        if !report.dimensionScores.filter({ $0.score > 0 }).isEmpty {
            lines.append("── Dimensions ──")
            for d in report.dimensionScores.sorted(by: { $0.score > $1.score }) where d.score > 0 {
                let bar = String(repeating: "█", count: Int(d.score * 20))
                let pad = String(repeating: "░", count: 20 - Int(d.score * 20))
                lines.append("  \(d.category.emoji) \(d.category.rawValue): [\(bar)\(pad)] \(String(format: "%.0f%%", d.score * 100)) (\(d.flagCount) flags)")
            }
            lines.append("")
        }

        if !report.flags.isEmpty {
            lines.append("── Flags (\(report.flags.count)) ──")
            for f in report.flags.sorted(by: { $0.severity > $1.severity }) {
                lines.append("  \(f.severity.emoji) [\(f.category.rawValue)] \"\(f.phrase)\"")
                if let sug = f.suggestion {
                    lines.append("     → \(sug)")
                }
            }
            lines.append("")
        }

        lines.append("── Summary ──")
        lines.append(report.summary)
        return lines.joined(separator: "\n")
    }

    /// Export report as JSON string.
    static func exportJSON(_ report: BiasReport) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Sentence Splitting

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }

    // MARK: - Detection Functions

    private static func detectLoadedLanguage(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let terms: [(String, BiasSeverity, String?)] = [
            ("radical", .medium, "Consider specifying exact position"),
            ("extremist", .high, "Specify the group or actions"),
            ("regime", .medium, "Use 'government' or 'administration'"),
            ("propaganda", .medium, "Use 'messaging' or 'communication'"),
            ("mob", .high, "Use 'crowd' or 'group'"),
            ("thug", .high, "Describe specific actions instead"),
            ("slam", .medium, "Use 'criticize' or 'oppose'"),
            ("destroy", .medium, "Use specific description of impact"),
            ("crisis", .medium, "Specify what makes it a crisis"),
            ("chaos", .medium, "Describe the specific situation"),
            ("outrage", .medium, "Use 'criticism' or 'opposition'"),
            ("shocking", .medium, "Let readers decide what's shocking"),
            ("bombshell", .high, "Use 'significant' or 'notable'"),
            ("slaughter", .high, "Use precise casualty descriptions"),
            ("crusade", .medium, "Use 'campaign' or 'effort'"),
            ("witch hunt", .high, "Use 'investigation' or 'inquiry'"),
            ("brainwash", .high, "Use 'influence' or 'persuade'"),
            ("puppet", .medium, "Describe the specific relationship"),
            ("cronies", .high, "Use 'allies' or 'associates'"),
            ("elites", .medium, "Specify which group"),
            ("rigged", .high, "Present specific evidence"),
            ("hoax", .high, "Use 'disputed claim' or 'allegation'"),
            ("unleash", .medium, "Use 'implement' or 'begin'"),
            ("firestorm", .medium, "Use 'controversy' or 'debate'"),
            ("gutted", .medium, "Use 'reduced' or 'cut'"),
        ]
        return matchTerms(terms, in: sentence, sentenceIndex: sentenceIndex, category: .loadedLanguage)
    }

    private static func detectEmotionalAppeal(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let patterns: [(String, BiasSeverity, String?)] = [
            ("think of the children", .high, "Present evidence rather than emotional appeals"),
            ("innocent victims", .medium, "Use 'victims' or 'affected individuals'"),
            ("heartbreaking", .medium, "Let the facts speak for themselves"),
            ("gut-wrenching", .medium, "Describe the situation factually"),
            ("tears streaming", .medium, "Report actions, not emotional imagery"),
            ("blood on their hands", .high, "Attribute responsibility with evidence"),
            ("nightmare scenario", .medium, "Describe the specific risks"),
            ("wake up call", .low, "Describe the implications directly"),
            ("ticking time bomb", .medium, "Describe the urgency factually"),
            ("sends chills", .medium, "Report the facts directly"),
            ("unthinkable", .medium, "Describe what specifically occurred"),
            ("tragic", .low, "Provide factual context"),
            ("horrifying", .medium, "Describe what happened factually"),
            ("devastating blow", .medium, "Describe the specific impact"),
        ]
        return matchTerms(patterns, in: sentence, sentenceIndex: sentenceIndex, category: .emotionalAppeal)
    }

    private static func detectUnattributedClaims(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let patterns: [(String, BiasSeverity, String?)] = [
            ("experts say", .medium, "Name the specific experts"),
            ("sources say", .medium, "Identify the sources"),
            ("studies show", .medium, "Cite the specific study"),
            ("research shows", .medium, "Cite the specific research"),
            ("many people believe", .medium, "Provide polling data or named sources"),
            ("it is well known", .medium, "Provide a citation"),
            ("it is widely believed", .medium, "Provide evidence"),
            ("some say", .high, "Identify who says this"),
            ("critics say", .medium, "Name the specific critics"),
            ("observers note", .medium, "Name the observers"),
            ("insiders reveal", .medium, "Identify the insiders or outlet"),
            ("according to reports", .low, "Cite the specific report"),
            ("analysts predict", .medium, "Name the analysts"),
            ("sources close to", .medium, "Clarify the relationship"),
            ("people familiar with", .low, "Identify the people or publication"),
            ("officials say", .low, "Name the officials"),
        ]
        return matchTerms(patterns, in: sentence, sentenceIndex: sentenceIndex, category: .unattributedClaim)
    }

    private static func detectOvergeneralization(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let patterns: [(String, BiasSeverity, String?)] = [
            ("everyone knows", .high, "Provide evidence instead"),
            ("nobody believes", .high, "Qualify with data"),
            ("always", .low, "Consider 'often' or 'frequently'"),
            ("never", .low, "Consider 'rarely' or 'seldom'"),
            ("all americans", .medium, "Specify which group or cite polling"),
            ("the entire country", .medium, "Specify the scope"),
            ("no one wants", .high, "Provide polling or evidence"),
            ("everybody agrees", .high, "Cite evidence of agreement"),
            ("the whole world", .medium, "Specify the scope"),
            ("without exception", .medium, "Acknowledge potential exceptions"),
            ("unanimously", .low, "Verify if truly unanimous"),
            ("once and for all", .medium, "Describe the specific resolution"),
        ]
        return matchTerms(patterns, in: sentence, sentenceIndex: sentenceIndex, category: .overgeneralization)
    }

    private static func detectHedging(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let patterns: [(String, BiasSeverity, String?)] = [
            ("might possibly", .low, "Choose 'might' or 'possibly', not both"),
            ("could potentially", .low, "Choose 'could' or 'potentially'"),
            ("seems to suggest", .low, "State the suggestion directly"),
            ("appears to indicate", .low, "State what it indicates"),
            ("it would seem", .low, "State the finding directly"),
            ("one could argue", .medium, "Make the argument or attribute it"),
            ("perhaps maybe", .low, "Choose one qualifier"),
            ("sort of", .low, "Be specific"),
            ("kind of", .low, "Be specific"),
            ("more or less", .low, "Provide specific figures"),
        ]
        return matchTerms(patterns, in: sentence, sentenceIndex: sentenceIndex, category: .hedging)
    }

    private static func detectAdverbialBias(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let patterns: [(String, BiasSeverity, String?)] = [
            ("obviously", .medium, "Remove — let the reader decide"),
            ("clearly", .medium, "Present the evidence instead"),
            ("undeniably", .medium, "Present the evidence"),
            ("inevitably", .medium, "Describe the likelihood with evidence"),
            ("unsurprisingly", .medium, "Report the fact without editorializing"),
            ("predictably", .medium, "Report the fact neutrally"),
            ("ironically", .low, "Describe the contrast factually"),
            ("conveniently", .medium, "Describe the timing factually"),
            ("suspiciously", .medium, "Present the evidence for suspicion"),
            ("mysteriously", .medium, "Describe what is unknown"),
            ("remarkably", .low, "Let the reader judge significance"),
            ("stunningly", .medium, "Report the fact directly"),
            ("shockingly", .medium, "Report the fact directly"),
            ("inexplicably", .medium, "Describe what is not understood"),
        ]
        return matchTerms(patterns, in: sentence, sentenceIndex: sentenceIndex, category: .adverbialBias)
    }

    private static func detectFalseBalance(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let patterns: [(String, BiasSeverity, String?)] = [
            ("both sides", .low, "Consider whether sides have equal evidence"),
            ("on the other hand", .low, nil),
            ("some disagree", .low, "Quantify the disagreement"),
            ("the debate continues", .medium, "Specify what evidence exists on each side"),
            ("opinions differ", .low, "Present the evidence, not just opinions"),
            ("the jury is still out", .medium, "Describe the current state of evidence"),
            ("there are those who", .medium, "Name and quantify the groups"),
            ("while controversial", .low, "Specify the nature of controversy"),
        ]
        return matchTerms(patterns, in: sentence, sentenceIndex: sentenceIndex, category: .falseBalance)
    }

    private static func detectLabelBias(_ sentence: String, sentenceIndex: Int) -> [BiasFlag] {
        let patterns: [(String, BiasSeverity, String?)] = [
            ("far-right", .medium, "Specify the policies or positions"),
            ("far-left", .medium, "Specify the policies or positions"),
            ("ultra-conservative", .medium, "Describe specific positions"),
            ("radical left", .high, "Describe specific policies"),
            ("radical right", .high, "Describe specific policies"),
            ("so-called", .medium, "Use the term directly or explain the dispute"),
            ("self-proclaimed", .low, "Clarify the context"),
            ("notorious", .medium, "Describe the specific reputation"),
            ("controversial figure", .low, "Describe why they are controversial"),
            ("embattled", .medium, "Describe the specific challenges"),
            ("beleaguered", .medium, "Describe the specific situation"),
            ("firebrand", .medium, "Describe the person's specific positions"),
            ("hardliner", .medium, "Describe the specific positions held"),
            ("ideologue", .medium, "Describe the specific beliefs"),
        ]
        return matchTerms(patterns, in: sentence, sentenceIndex: sentenceIndex, category: .labelBias)
    }

    // MARK: - Helpers

    private static func matchTerms(
        _ terms: [(String, BiasSeverity, String?)],
        in sentence: String,
        sentenceIndex: Int,
        category: BiasCategory
    ) -> [BiasFlag] {
        var flags: [BiasFlag] = []
        for (term, severity, suggestion) in terms {
            if sentence.contains(term) {
                flags.append(BiasFlag(
                    phrase: term,
                    category: category,
                    severity: severity,
                    sentenceIndex: sentenceIndex,
                    suggestion: suggestion
                ))
            }
        }
        return flags
    }

    private static func computeDimensionScores(flags: [BiasFlag], sentenceCount: Int) -> [BiasDimensionScore] {
        BiasCategory.allCases.map { cat in
            let catFlags = flags.filter { $0.category == cat }
            let weightedCount = catFlags.reduce(0.0) { sum, f in
                switch f.severity {
                case .low: return sum + 0.5
                case .medium: return sum + 1.0
                case .high: return sum + 2.0
                }
            }
            let score = sentenceCount > 0 ? min(1.0, weightedCount / Double(max(sentenceCount, 5))) : 0
            return BiasDimensionScore(category: cat, score: round(score * 100) / 100, flagCount: catFlags.count)
        }
    }

    private static func computeOverallScore(_ dimensions: [BiasDimensionScore]) -> Double {
        let weights: [BiasCategory: Double] = [
            .loadedLanguage: 0.20,
            .emotionalAppeal: 0.15,
            .unattributedClaim: 0.15,
            .overgeneralization: 0.12,
            .hedging: 0.08,
            .adverbialBias: 0.10,
            .falseBalance: 0.08,
            .labelBias: 0.12,
        ]
        let weighted = dimensions.reduce(0.0) { sum, d in
            sum + d.score * (weights[d.category] ?? 0.1)
        }
        return round(min(1.0, weighted) * 100) / 100
    }

    private static func classifyLevel(_ score: Double) -> BiasLevel {
        switch score {
        case ..<0.10: return .minimal
        case ..<0.25: return .slight
        case ..<0.45: return .moderate
        case ..<0.65: return .significant
        default: return .heavy
        }
    }

    private static func generateSummary(level: BiasLevel, flags: [BiasFlag], topCategories: [BiasCategory], wordCount: Int) -> String {
        if flags.isEmpty {
            return "No significant bias indicators detected. The text appears to use neutral, factual language."
        }
        let highCount = flags.filter { $0.severity == .high }.count
        let catList = topCategories.map { $0.rawValue.lowercased() }.joined(separator: ", ")
        var s = "Analysis detected \(flags.count) bias indicator\(flags.count == 1 ? "" : "s") across \(wordCount) words. "
        s += "Primary concerns: \(catList). "
        if highCount > 0 {
            s += "\(highCount) high-severity flag\(highCount == 1 ? "" : "s") found. "
        }
        switch level {
        case .minimal:
            s += "Overall, the text is largely balanced with minor editorial touches."
        case .slight:
            s += "The text shows slight editorial leanings but is mostly factual."
        case .moderate:
            s += "Consider revising flagged phrases for more neutral presentation."
        case .significant:
            s += "The text contains notable bias that may influence reader perception."
        case .heavy:
            s += "The text is heavily slanted and should be read with critical awareness."
        }
        return s
    }

    private static var emptyReport: BiasReport {
        BiasReport(
            overallScore: 0,
            level: .minimal,
            flags: [],
            dimensionScores: BiasCategory.allCases.map { BiasDimensionScore(category: $0, score: 0, flagCount: 0) },
            sentenceCount: 0,
            wordCount: 0,
            flagDensity: 0,
            topCategories: [],
            summary: "No text provided for analysis."
        )
    }
}
