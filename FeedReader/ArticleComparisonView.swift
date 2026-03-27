//
//  ArticleComparisonView.swift
//  FeedReader
//
//  Side-by-side article comparison tool. Lets users pick two articles
//  and see them compared across dimensions: length, readability,
//  publication date, source, shared keywords, and content overlap.
//

import UIKit

// MARK: - Comparison Result Model

/// Holds the computed comparison between two articles.
struct ArticleComparison {
    let articleA: Story
    let articleB: Story
    
    /// Word counts
    let wordCountA: Int
    let wordCountB: Int
    
    /// Character counts (excluding whitespace)
    let charCountA: Int
    let charCountB: Int
    
    /// Sentence counts
    let sentenceCountA: Int
    let sentenceCountB: Int
    
    /// Average words per sentence
    var avgWordsPerSentenceA: Double {
        sentenceCountA > 0 ? Double(wordCountA) / Double(sentenceCountA) : 0
    }
    var avgWordsPerSentenceB: Double {
        sentenceCountB > 0 ? Double(wordCountB) / Double(sentenceCountB) : 0
    }
    
    /// Estimated reading time in minutes (assuming 200 wpm)
    var readingTimeA: Double { Double(wordCountA) / 200.0 }
    var readingTimeB: Double { Double(wordCountB) / 200.0 }
    
    /// Keywords found in both articles
    let sharedKeywords: [String]
    
    /// Keywords unique to each article
    let uniqueKeywordsA: [String]
    let uniqueKeywordsB: [String]
    
    /// Jaccard similarity of word sets (0.0 – 1.0)
    let contentSimilarity: Double
    
    /// Which article is longer
    var longerArticle: String {
        if wordCountA > wordCountB { return articleA.title }
        if wordCountB > wordCountA { return articleB.title }
        return "Same length"
    }
}

// MARK: - Comparison Engine

/// Computes comparison metrics between two Story objects.
class ArticleComparisonEngine {
    
    /// Compare two articles and return a full comparison result.
    static func compare(_ a: Story, _ b: Story) -> ArticleComparison {
        let textA = a.body
        let textB = b.body
        
        let wordsA = extractWords(from: textA)
        let wordsB = extractWords(from: textB)
        
        let sentencesA = countSentences(in: textA)
        let sentencesB = countSentences(in: textB)
        
        let charsA = textA.filter { !$0.isWhitespace }.count
        let charsB = textB.filter { !$0.isWhitespace }.count
        
        let keywordsA = extractKeywords(from: wordsA, topN: 20)
        let keywordsB = extractKeywords(from: wordsB, topN: 20)
        
        let setA = Set(keywordsA)
        let setB = Set(keywordsB)
        let shared = setA.intersection(setB).sorted()
        let uniqueA = setA.subtracting(setB).sorted()
        let uniqueB = setB.subtracting(setA).sorted()
        
        let wordSetA = Set(wordsA.map { $0.lowercased() })
        let wordSetB = Set(wordsB.map { $0.lowercased() })
        let unionCount = wordSetA.union(wordSetB).count
        let similarity = unionCount > 0 ? Double(wordSetA.intersection(wordSetB).count) / Double(unionCount) : 0.0
        
        return ArticleComparison(
            articleA: a,
            articleB: b,
            wordCountA: wordsA.count,
            wordCountB: wordsB.count,
            charCountA: charsA,
            charCountB: charsB,
            sentenceCountA: sentencesA,
            sentenceCountB: sentencesB,
            sharedKeywords: shared,
            uniqueKeywordsA: uniqueA,
            uniqueKeywordsB: uniqueB,
            contentSimilarity: similarity
        )
    }
    
    // MARK: - Text Analysis Helpers
    
    private static func extractWords(from text: String) -> [String] {
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }
    }
    
    private static func countSentences(in text: String) -> Int {
        let pattern = "[.!?]+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex?.numberOfMatches(in: text, range: range) ?? 1
    }
    
    /// Extract top keywords by frequency, filtering stop words.
    private static func extractKeywords(from words: [String], topN: Int) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "is", "was", "are", "were", "be", "been",
            "being", "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "shall", "can", "this", "that",
            "these", "those", "it", "its", "not", "no", "nor", "as", "if", "than",
            "then", "so", "up", "out", "about", "into", "over", "after", "before",
            "between", "under", "above", "such", "each", "which", "their", "there",
            "they", "them", "we", "our", "he", "she", "his", "her", "my", "your",
            "i", "me", "you", "who", "what", "when", "where", "how", "all", "any",
            "both", "few", "more", "most", "other", "some", "very", "just", "also"
        ]
        
        var freq: [String: Int] = [:]
        for word in words {
            let lower = word.lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            guard lower.count > 2, !stopWords.contains(lower) else { continue }
            freq[lower, default: 0] += 1
        }
        
        return freq.sorted { $0.value > $1.value }
            .prefix(topN)
            .map { $0.key }
    }
}

// MARK: - Comparison View Controller

/// Displays a side-by-side comparison of two articles.
class ArticleComparisonViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    // MARK: - Properties
    
    private var comparison: ArticleComparison?
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var sections: [(title: String, rows: [(label: String, valueA: String, valueB: String)])] = []
    
    // MARK: - Initialization
    
    /// Create a comparison view for two articles.
    convenience init(articleA: Story, articleB: Story) {
        self.init(nibName: nil, bundle: nil)
        self.comparison = ArticleComparisonEngine.compare(articleA, articleB)
        buildSections()
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Compare Articles"
        view.backgroundColor = .systemBackground
        
        setupTableView()
        setupNavigationBar()
    }
    
    // MARK: - Setup
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareComparison)
        )
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(dismissSelf)
            )
        }
    }
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ComparisonCell.self, forCellReuseIdentifier: ComparisonCell.reuseID)
        tableView.register(ComparisonHeaderCell.self, forCellReuseIdentifier: ComparisonHeaderCell.reuseID)
        tableView.register(KeywordCell.self, forCellReuseIdentifier: KeywordCell.reuseID)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Build Sections
    
    private func buildSections() {
        guard let c = comparison else { return }
        
        sections = [
            (title: "📊 Overview", rows: [
                ("Word Count", "\(c.wordCountA)", "\(c.wordCountB)"),
                ("Characters", "\(c.charCountA)", "\(c.charCountB)"),
                ("Sentences", "\(c.sentenceCountA)", "\(c.sentenceCountB)"),
                ("Avg Words/Sentence", String(format: "%.1f", c.avgWordsPerSentenceA), String(format: "%.1f", c.avgWordsPerSentenceB)),
                ("Reading Time", String(format: "%.1f min", c.readingTimeA), String(format: "%.1f min", c.readingTimeB))
            ]),
            (title: "📰 Sources", rows: [
                ("Feed", c.articleA.sourceFeedName ?? "Unknown", c.articleB.sourceFeedName ?? "Unknown")
            ]),
            (title: "🔗 Similarity", rows: [
                ("Content Overlap", String(format: "%.1f%%", c.contentSimilarity * 100), ""),
                ("Shared Keywords", "\(c.sharedKeywords.count)", ""),
                ("Unique Keywords", "\(c.uniqueKeywordsA.count)", "\(c.uniqueKeywordsB.count)")
            ])
        ]
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        // +1 for header, +1 for shared keywords section
        return sections.count + 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 } // Header
        if section == sections.count + 1 { // Shared keywords
            return max(comparison?.sharedKeywords.count ?? 0, 1)
        }
        return sections[section - 1].rows.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return nil }
        if section == sections.count + 1 { return "🔑 Shared Keywords" }
        return sections[section - 1].title
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: ComparisonHeaderCell.reuseID, for: indexPath) as! ComparisonHeaderCell
            if let c = comparison {
                cell.configure(titleA: c.articleA.title, titleB: c.articleB.title)
            }
            return cell
        }
        
        if indexPath.section == sections.count + 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: KeywordCell.reuseID, for: indexPath) as! KeywordCell
            if let keywords = comparison?.sharedKeywords, !keywords.isEmpty {
                cell.textLabel?.text = keywords[indexPath.row]
            } else {
                cell.textLabel?.text = "No shared keywords"
                cell.textLabel?.textColor = .secondaryLabel
            }
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: ComparisonCell.reuseID, for: indexPath) as! ComparisonCell
        let row = sections[indexPath.section - 1].rows[indexPath.row]
        cell.configure(label: row.label, valueA: row.valueA, valueB: row.valueB)
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 { return 100 }
        return UITableView.automaticDimension
    }
    
    // MARK: - Actions
    
    @objc private func shareComparison() {
        guard let c = comparison else { return }
        
        var text = "Article Comparison\n"
        text += "==================\n\n"
        text += "A: \(c.articleA.title)\n"
        text += "B: \(c.articleB.title)\n\n"
        text += "Word Count: \(c.wordCountA) vs \(c.wordCountB)\n"
        text += "Reading Time: \(String(format: "%.1f", c.readingTimeA)) min vs \(String(format: "%.1f", c.readingTimeB)) min\n"
        text += "Content Similarity: \(String(format: "%.1f%%", c.contentSimilarity * 100))\n"
        text += "Shared Keywords: \(c.sharedKeywords.joined(separator: ", "))\n"
        
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        present(activity, animated: true)
    }
    
    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}

// MARK: - Comparison Header Cell

/// Shows article titles side by side.
private class ComparisonHeaderCell: UITableViewCell {
    static let reuseID = "ComparisonHeaderCell"
    
    private let labelA = UILabel()
    private let labelB = UILabel()
    private let vsLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        
        labelA.font = .preferredFont(forTextStyle: .headline)
        labelA.numberOfLines = 2
        labelA.textAlignment = .center
        
        labelB.font = .preferredFont(forTextStyle: .headline)
        labelB.numberOfLines = 2
        labelB.textAlignment = .center
        
        vsLabel.text = "vs"
        vsLabel.font = .preferredFont(forTextStyle: .caption1)
        vsLabel.textColor = .secondaryLabel
        vsLabel.textAlignment = .center
        
        let stack = UIStackView(arrangedSubviews: [labelA, vsLabel, labelB])
        stack.axis = .horizontal
        stack.distribution = .fillProportionally
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        
        vsLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func configure(titleA: String, titleB: String) {
        labelA.text = titleA
        labelB.text = titleB
    }
}

// MARK: - Comparison Data Cell

/// Shows a metric with values for both articles side by side.
private class ComparisonCell: UITableViewCell {
    static let reuseID = "ComparisonCell"
    
    private let metricLabel = UILabel()
    private let valueALabel = UILabel()
    private let valueBLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        
        metricLabel.font = .preferredFont(forTextStyle: .subheadline)
        metricLabel.textColor = .secondaryLabel
        
        valueALabel.font = .preferredFont(forTextStyle: .body)
        valueALabel.textAlignment = .center
        valueALabel.textColor = .systemBlue
        
        valueBLabel.font = .preferredFont(forTextStyle: .body)
        valueBLabel.textAlignment = .center
        valueBLabel.textColor = .systemOrange
        
        let valuesStack = UIStackView(arrangedSubviews: [valueALabel, valueBLabel])
        valuesStack.axis = .horizontal
        valuesStack.distribution = .fillEqually
        
        let mainStack = UIStackView(arrangedSubviews: [metricLabel, valuesStack])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        
        metricLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor, multiplier: 0.4).isActive = true
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func configure(label: String, valueA: String, valueB: String) {
        metricLabel.text = label
        valueALabel.text = valueA
        valueBLabel.text = valueB.isEmpty ? "—" : valueB
    }
}

// MARK: - Keyword Cell

/// Simple cell for displaying a keyword.
private class KeywordCell: UITableViewCell {
    static let reuseID = "KeywordCell"
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        textLabel?.font = .preferredFont(forTextStyle: .body)
    }
    
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Article Picker for Comparison

/// Helper to pick two articles for comparison from the reading history.
class ArticleComparisonPicker {
    
    /// Present a two-step picker to select articles for comparison.
    static func presentPicker(from viewController: UIViewController, articles: [Story]) {
        guard articles.count >= 2 else {
            let alert = UIAlertController(
                title: "Not Enough Articles",
                message: "You need at least 2 articles to compare. Read more articles first!",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
            return
        }
        
        // Step 1: Pick first article
        let alert1 = UIAlertController(title: "Compare Articles", message: "Select the first article", preferredStyle: .actionSheet)
        
        for (index, article) in articles.prefix(15).enumerated() {
            alert1.addAction(UIAlertAction(title: article.title, style: .default) { _ in
                // Step 2: Pick second article
                let remaining = articles.filter { $0.link != article.link }
                let alert2 = UIAlertController(title: "Compare With...", message: "Select the second article", preferredStyle: .actionSheet)
                
                for secondArticle in remaining.prefix(15) {
                    alert2.addAction(UIAlertAction(title: secondArticle.title, style: .default) { _ in
                        let comparisonVC = ArticleComparisonViewController(articleA: article, articleB: secondArticle)
                        let nav = UINavigationController(rootViewController: comparisonVC)
                        viewController.present(nav, animated: true)
                    })
                }
                
                alert2.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                viewController.present(alert2, animated: true)
            })
        }
        
        alert1.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        viewController.present(alert1, animated: true)
    }
}
