//
//  WordCloudViewController.swift
//  FeedReader
//
//  Displays an interactive word cloud visualization of article
//  content. Words are sized by frequency and colored by tier.
//  Tap a word to see its count and which articles contain it.
//

import UIKit

/// View controller that renders a word cloud from the user's articles.
///
/// Uses `WordCloudGenerator` to compute word frequencies and displays
/// them in a scrollable, tag-cloud-style layout. Supports filtering
/// by feed and exporting the cloud data.
class WordCloudViewController: UIViewController {

    // MARK: - Properties

    /// The stories to analyze.
    var stories: [Story] = []

    /// Generated word cloud entries.
    private var entries: [WordCloudEntry] = []

    /// The word cloud generator.
    private let generator = WordCloudGenerator()

    /// Scroll view containing the word labels.
    private let scrollView = UIScrollView()

    /// Container view for word labels.
    private let containerView = UIView()

    /// Title label.
    private let titleLabel = UILabel()

    /// Info label showing word count summary.
    private let infoLabel = UILabel()

    /// Export button.
    private let exportButton = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Word Cloud"
        view.backgroundColor = .white

        setupUI()
        generateCloud()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Title
        titleLabel.text = "📊 Word Cloud"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Info label
        infoLabel.font = UIFont.systemFont(ofSize: 14)
        infoLabel.textColor = .gray
        infoLabel.textAlignment = .center
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)

        // Export button
        exportButton.setTitle("Export CSV", for: .normal)
        exportButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exportButton)

        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(containerView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            infoLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: exportButton.leadingAnchor, constant: -8),

            exportButton.centerYAnchor.constraint(equalTo: infoLabel.centerYAnchor),
            exportButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            containerView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            containerView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    // MARK: - Cloud Generation

    private func generateCloud() {
        entries = generator.generate(from: stories)

        // Shuffle for visual variety (not strictly sorted by size)
        let shuffled = entries.shuffled()

        infoLabel.text = "\(entries.count) words from \(stories.count) articles"

        // Layout words in a flow/tag-cloud style
        layoutWords(shuffled)
    }

    private func layoutWords(_ words: [WordCloudEntry]) {
        // Remove existing word labels
        containerView.subviews.forEach { $0.removeFromSuperview() }

        let padding: CGFloat = 8
        let maxWidth = view.bounds.width - 32
        var currentX: CGFloat = padding
        var currentY: CGFloat = padding
        var rowHeight: CGFloat = 0

        for entry in words {
            let label = WordLabel(entry: entry)
            label.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(wordTapped(_:)))
            label.addGestureRecognizer(tap)

            let size = label.intrinsicContentSize
            let labelWidth = size.width + 16
            let labelHeight = size.height + 8

            // Wrap to next row if needed
            if currentX + labelWidth > maxWidth {
                currentX = padding
                currentY += rowHeight + padding
                rowHeight = 0
            }

            label.frame = CGRect(x: currentX, y: currentY, width: labelWidth, height: labelHeight)
            label.layer.cornerRadius = labelHeight / 2
            label.clipsToBounds = true
            containerView.addSubview(label)

            currentX += labelWidth + padding
            rowHeight = max(rowHeight, labelHeight)
        }

        // Set container height
        let totalHeight = currentY + rowHeight + padding
        containerView.heightAnchor.constraint(equalToConstant: totalHeight).isActive = true
    }

    // MARK: - Actions

    @objc private func wordTapped(_ gesture: UITapGestureRecognizer) {
        guard let label = gesture.view as? WordLabel else { return }
        let entry = label.entry

        let alert = UIAlertController(
            title: entry.word,
            message: "Appears \(entry.count) time\(entry.count == 1 ? "" : "s")\nWeight: \(String(format: "%.1f%%", entry.weight * 100))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func exportTapped() {
        let csv = generator.exportAsCSV(entries)
        let activityVC = UIActivityViewController(activityItems: [csv], applicationActivities: nil)
        present(activityVC, animated: true)
    }
}

// MARK: - WordLabel

/// Custom label that stores its associated WordCloudEntry.
private class WordLabel: UILabel {
    let entry: WordCloudEntry

    init(entry: WordCloudEntry) {
        self.entry = entry
        super.init(frame: .zero)
        text = "  \(entry.word)  "
        font = UIFont.systemFont(ofSize: entry.fontSize, weight: entry.weight > 0.7 ? .bold : .regular)
        textColor = entry.color
        backgroundColor = entry.color.withAlphaComponent(0.1)
        textAlignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
