//
//  VocabularyProfileViewController.swift
//  FeedReader
//
//  Displays the vocabulary frequency profile for an article, showing
//  frequency band distribution, CEFR level, richness score, and
//  lists of rare and academic words found.
//

import UIKit

/// View controller that displays vocabulary frequency analysis results.
class VocabularyProfileViewController: UIViewController {

    // MARK: - Properties

    /// The article text to analyze.
    var articleText: String = ""
    /// The article identifier (URL or title).
    var articleId: String = ""

    private var profile: VocabularyProfile?

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let headerLabel = UILabel()
    private let cefrBadge = UILabel()
    private let richnessLabel = UILabel()
    private let statsLabel = UILabel()
    private let bandChartView = UIView()
    private let academicHeader = UILabel()
    private let academicWordsLabel = UILabel()
    private let rareHeader = UILabel()
    private let rareWordsLabel = UILabel()
    private let exposureHeader = UILabel()
    private let exposureLabel = UILabel()
    private let exportButton = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vocabulary Profile"
        view.backgroundColor = .systemBackground
        setupUI()
        analyzeArticle()
    }

    // MARK: - Setup

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentStack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        // Header
        headerLabel.text = "📚 Vocabulary Analysis"
        headerLabel.font = .systemFont(ofSize: 24, weight: .bold)
        contentStack.addArrangedSubview(headerLabel)

        // CEFR Badge
        cefrBadge.font = .systemFont(ofSize: 18, weight: .semibold)
        cefrBadge.textAlignment = .center
        cefrBadge.layer.cornerRadius = 8
        cefrBadge.clipsToBounds = true
        cefrBadge.heightAnchor.constraint(equalToConstant: 44).isActive = true
        contentStack.addArrangedSubview(cefrBadge)

        // Richness Score
        richnessLabel.font = .systemFont(ofSize: 16, weight: .medium)
        richnessLabel.textAlignment = .center
        contentStack.addArrangedSubview(richnessLabel)

        // Stats
        statsLabel.font = .systemFont(ofSize: 14)
        statsLabel.numberOfLines = 0
        statsLabel.textColor = .secondaryLabel
        contentStack.addArrangedSubview(statsLabel)

        // Band Chart placeholder
        bandChartView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        contentStack.addArrangedSubview(bandChartView)

        // Academic Words
        academicHeader.text = "🎓 Academic Words"
        academicHeader.font = .systemFont(ofSize: 18, weight: .semibold)
        contentStack.addArrangedSubview(academicHeader)

        academicWordsLabel.font = .systemFont(ofSize: 14)
        academicWordsLabel.numberOfLines = 0
        academicWordsLabel.textColor = .label
        contentStack.addArrangedSubview(academicWordsLabel)

        // Rare Words
        rareHeader.text = "💎 Rare Words"
        rareHeader.font = .systemFont(ofSize: 18, weight: .semibold)
        contentStack.addArrangedSubview(rareHeader)

        rareWordsLabel.font = .systemFont(ofSize: 14)
        rareWordsLabel.numberOfLines = 0
        rareWordsLabel.textColor = .label
        contentStack.addArrangedSubview(rareWordsLabel)

        // Exposure
        exposureHeader.text = "📊 Vocabulary Exposure"
        exposureHeader.font = .systemFont(ofSize: 18, weight: .semibold)
        contentStack.addArrangedSubview(exposureHeader)

        exposureLabel.font = .systemFont(ofSize: 14)
        exposureLabel.numberOfLines = 0
        exposureLabel.textColor = .secondaryLabel
        contentStack.addArrangedSubview(exposureLabel)

        // Export Button
        exportButton.setTitle("Export Profile (JSON)", for: .normal)
        exportButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(exportButton)
    }

    // MARK: - Analysis

    private func analyzeArticle() {
        let profiler = VocabularyFrequencyProfiler.shared
        let result = profiler.analyze(text: articleText, articleId: articleId)
        self.profile = result

        // Record exposure
        profiler.recordExposure(from: result)

        updateUI(with: result)
    }

    private func updateUI(with profile: VocabularyProfile) {
        // CEFR Badge
        cefrBadge.text = "CEFR Level: \(profile.cefrLevel.rawValue) — \(profile.cefrLevel.description)"
        cefrBadge.backgroundColor = colorForCEFR(profile.cefrLevel)
        cefrBadge.textColor = .white

        // Richness
        richnessLabel.text = "Vocabulary Richness: \(String(format: "%.1f", profile.richnessScore))/100"

        // Stats
        statsLabel.text = """
        Total words: \(profile.totalTokens)
        Unique words: \(profile.uniqueTypes)
        Lexical diversity (TTR): \(String(format: "%.3f", profile.typeTokenRatio))
        """

        // Band chart (simple bar chart using UIViews)
        buildBandChart(from: profile)

        // Academic words
        if profile.academicWords.isEmpty {
            academicWordsLabel.text = "No academic vocabulary detected."
        } else {
            academicWordsLabel.text = profile.academicWords.joined(separator: ", ")
        }

        // Rare words
        if profile.rareWords.isEmpty {
            rareWordsLabel.text = "No rare vocabulary detected."
        } else {
            rareWordsLabel.text = profile.rareWords.joined(separator: ", ")
        }

        // Exposure stats
        let exposure = VocabularyFrequencyProfiler.shared.getExposure()
        exposureLabel.text = """
        Articles profiled: \(exposure.articlesProfiled)
        Unique advanced words encountered: \(exposure.totalUniqueWords)
        """
    }

    private func buildBandChart(from profile: VocabularyProfile) {
        // Clear existing
        bandChartView.subviews.forEach { $0.removeFromSuperview() }

        let bands = FrequencyBand.allCases
        let barHeight: CGFloat = 24
        let spacing: CGFloat = 4

        for (i, band) in bands.enumerated() {
            let pct = profile.bandPercentages[band.rawValue] ?? 0
            let count = profile.bandDistribution[band.rawValue] ?? 0

            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            bandChartView.addSubview(container)

            let yOffset = CGFloat(i) * (barHeight + spacing)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: bandChartView.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: bandChartView.trailingAnchor),
                container.topAnchor.constraint(equalTo: bandChartView.topAnchor, constant: yOffset),
                container.heightAnchor.constraint(equalToConstant: barHeight)
            ])

            let label = UILabel()
            label.text = "\(band.rawValue): \(count) (\(String(format: "%.1f%%", pct)))"
            label.font = .systemFont(ofSize: 12)
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)

            let bar = UIView()
            bar.backgroundColor = colorForBand(band)
            bar.layer.cornerRadius = 3
            bar.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(bar)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: 160),
                bar.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
                bar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                bar.heightAnchor.constraint(equalToConstant: 16),
                bar.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: CGFloat(min(pct, 100) / 100.0), constant: -168)
            ])
        }
    }

    private func colorForCEFR(_ level: CEFRLevel) -> UIColor {
        switch level {
        case .a1: return .systemGreen
        case .a2: return .systemTeal
        case .b1: return .systemBlue
        case .b2: return .systemIndigo
        case .c1: return .systemOrange
        case .c2: return .systemRed
        }
    }

    private func colorForBand(_ band: FrequencyBand) -> UIColor {
        switch band {
        case .top500:   return .systemGreen
        case .top1000:  return .systemTeal
        case .top2000:  return .systemBlue
        case .top3000:  return .systemIndigo
        case .top5000:  return .systemPurple
        case .top10000: return .systemOrange
        case .rare:     return .systemRed
        }
    }

    // MARK: - Actions

    @objc private func exportTapped() {
        guard let profile = profile,
              let data = VocabularyFrequencyProfiler.shared.exportProfileJSON(profile),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        let activityVC = UIActivityViewController(
            activityItems: [jsonString],
            applicationActivities: nil
        )
        present(activityVC, animated: true)
    }
}
