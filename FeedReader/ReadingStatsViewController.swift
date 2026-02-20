//
//  ReadingStatsViewController.swift
//  FeedReader
//
//  Displays reading analytics: total stories read, daily averages,
//  reading streaks, hourly activity pattern, per-feed breakdown,
//  and bookmark stats. All built programmatically with UIKit.
//

import UIKit

class ReadingStatsViewController: UIViewController {
    
    // MARK: - Properties
    
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reading Stats"
        view.backgroundColor = .systemGroupedBackground
        
        setupScrollView()
        buildDashboard()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statsChanged),
            name: .readingStatsDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func statsChanged() {
        // Rebuild the dashboard when stats change
        for subview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        buildDashboard()
    }
    
    // MARK: - Layout
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])
    }
    
    // MARK: - Dashboard
    
    private func buildDashboard() {
        let stats = ReadingStatsManager.shared.computeStats()
        
        // Overview Cards
        contentStack.addArrangedSubview(makeSectionHeader("📊 Overview"))
        contentStack.addArrangedSubview(makeOverviewGrid(stats))
        
        // Reading Streak
        contentStack.addArrangedSubview(makeSectionHeader("🔥 Reading Streak"))
        contentStack.addArrangedSubview(makeStreakCard(stats))
        
        // Activity Pattern
        if stats.totalStoriesRead > 0 {
            contentStack.addArrangedSubview(makeSectionHeader("⏰ Reading Hours"))
            contentStack.addArrangedSubview(makeHourlyChart(stats))
        }
        
        // Feed Breakdown
        if !stats.feedBreakdown.isEmpty {
            contentStack.addArrangedSubview(makeSectionHeader("📡 Feed Breakdown"))
            contentStack.addArrangedSubview(makeFeedBreakdown(stats))
        }
        
        // Empty State
        if stats.totalStoriesRead == 0 {
            contentStack.addArrangedSubview(makeEmptyState())
        }
        
        // Clear Stats Button
        if stats.totalStoriesRead > 0 {
            contentStack.addArrangedSubview(makeClearButton())
        }
    }
    
    // MARK: - Section Header
    
    private func makeSectionHeader(_ title: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        return label
    }
    
    // MARK: - Overview Grid
    
    private func makeOverviewGrid(_ stats: ReadingStatsManager.ReadingStats) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 12
        
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 0
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        
        // Row 1: Total | Today
        let row1 = makeStatRow([
            ("Total Read", "\(stats.totalStoriesRead)", "📚"),
            ("Today", "\(stats.readToday)", "📰")
        ])
        grid.addArrangedSubview(row1)
        grid.addArrangedSubview(makeSeparator())
        
        // Row 2: This Week | This Month
        let row2 = makeStatRow([
            ("This Week", "\(stats.readThisWeek)", "📅"),
            ("This Month", "\(stats.readThisMonth)", "🗓️")
        ])
        grid.addArrangedSubview(row2)
        grid.addArrangedSubview(makeSeparator())
        
        // Row 3: Daily Avg | Bookmarks
        let avgStr = String(format: "%.1f", stats.dailyAverage)
        let row3 = makeStatRow([
            ("Daily Avg", avgStr, "📈"),
            ("Bookmarks", "\(stats.totalBookmarks)", "🔖")
        ])
        grid.addArrangedSubview(row3)
        
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        return container
    }
    
    private func makeStatRow(_ items: [(title: String, value: String, emoji: String)]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        
        for item in items {
            let cell = UIStackView()
            cell.axis = .vertical
            cell.alignment = .center
            cell.spacing = 4
            
            let emojiLabel = UILabel()
            emojiLabel.text = item.emoji
            emojiLabel.font = UIFont.systemFont(ofSize: 28)
            
            let valueLabel = UILabel()
            valueLabel.text = item.value
            valueLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
            valueLabel.textColor = .label
            
            let titleLabel = UILabel()
            titleLabel.text = item.title
            titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            titleLabel.textColor = .secondaryLabel
            
            cell.addArrangedSubview(emojiLabel)
            cell.addArrangedSubview(valueLabel)
            cell.addArrangedSubview(titleLabel)
            
            let wrapper = UIView()
            cell.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(cell)
            NSLayoutConstraint.activate([
                cell.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                cell.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
                cell.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12)
            ])
            
            row.addArrangedSubview(wrapper)
        }
        
        return row
    }
    
    private func makeSeparator() -> UIView {
        let sep = UIView()
        sep.backgroundColor = .separator
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return sep
    }
    
    // MARK: - Streak Card
    
    private func makeStreakCard(_ stats: ReadingStatsManager.ReadingStats) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        
        // Current streak
        let currentRow = UIStackView()
        currentRow.axis = .horizontal
        currentRow.spacing = 8
        currentRow.alignment = .center
        
        let fireEmoji = UILabel()
        fireEmoji.text = stats.currentStreak > 0 ? "🔥" : "❄️"
        fireEmoji.font = UIFont.systemFont(ofSize: 36)
        
        let streakStack = UIStackView()
        streakStack.axis = .vertical
        streakStack.spacing = 2
        
        let streakValue = UILabel()
        streakValue.text = "\(stats.currentStreak) day\(stats.currentStreak == 1 ? "" : "s")"
        streakValue.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        streakValue.textColor = stats.currentStreak > 0 ? .systemOrange : .secondaryLabel
        
        let streakLabel = UILabel()
        streakLabel.text = "Current Streak"
        streakLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        streakLabel.textColor = .secondaryLabel
        
        streakStack.addArrangedSubview(streakValue)
        streakStack.addArrangedSubview(streakLabel)
        
        currentRow.addArrangedSubview(fireEmoji)
        currentRow.addArrangedSubview(streakStack)
        currentRow.addArrangedSubview(UIView()) // spacer
        
        stack.addArrangedSubview(currentRow)
        
        // Longest streak & tracking period
        let detailRow = UIStackView()
        detailRow.axis = .horizontal
        detailRow.distribution = .fillEqually
        
        let longestBox = makeSmallStat(
            title: "Longest Streak",
            value: "\(stats.longestStreak) day\(stats.longestStreak == 1 ? "" : "s")",
            color: .systemBlue
        )
        detailRow.addArrangedSubview(longestBox)
        
        let trackingBox = makeSmallStat(
            title: "Tracking Since",
            value: stats.firstReadDate != nil ? formatDate(stats.firstReadDate!) : "—",
            color: .systemGreen
        )
        detailRow.addArrangedSubview(trackingBox)
        
        stack.addArrangedSubview(detailRow)
        
        // Motivational message
        let motivationLabel = UILabel()
        motivationLabel.text = streakMessage(stats.currentStreak)
        motivationLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        motivationLabel.textColor = .tertiaryLabel
        motivationLabel.textAlignment = .center
        motivationLabel.numberOfLines = 0
        stack.addArrangedSubview(motivationLabel)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        
        return card
    }
    
    private func makeSmallStat(title: String, value: String, color: UIColor) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        valueLabel.textColor = color
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(titleLabel)
        
        return stack
    }
    
    private func streakMessage(_ streak: Int) -> String {
        switch streak {
        case 0:
            return "Read a story today to start your streak! 💪"
        case 1:
            return "Great start! Keep it going tomorrow."
        case 2...4:
            return "Nice streak! You're building a habit. 📖"
        case 5...9:
            return "Impressive! You're a dedicated reader. 🌟"
        case 10...29:
            return "Amazing commitment! Keep it up! 🏆"
        default:
            return "Legendary reader! \(streak) days and counting! 👑"
        }
    }
    
    // MARK: - Hourly Chart
    
    private func makeHourlyChart(_ stats: ReadingStatsManager.ReadingStats) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        
        let chartView = HourlyBarChartView(distribution: stats.hourlyDistribution)
        chartView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(chartView)
        
        let infoLabel = UILabel()
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        if let activeHour = stats.mostActiveHour {
            infoLabel.text = "Most active: \(formatHour(activeHour))"
        } else {
            infoLabel.text = "No reading data yet"
        }
        infoLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        infoLabel.textColor = .secondaryLabel
        infoLabel.textAlignment = .center
        card.addSubview(infoLabel)
        
        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            chartView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            chartView.heightAnchor.constraint(equalToConstant: 120),
            
            infoLabel.topAnchor.constraint(equalTo: chartView.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            infoLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        
        return card
    }
    
    // MARK: - Feed Breakdown
    
    private func makeFeedBreakdown(_ stats: ReadingStatsManager.ReadingStats) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        
        let maxCount = stats.feedBreakdown.first?.count ?? 1
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink, .systemTeal, .systemIndigo, .systemYellow]
        
        for (index, feed) in stats.feedBreakdown.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            
            // Color dot
            let dot = UIView()
            dot.backgroundColor = colors[index % colors.count]
            dot.layer.cornerRadius = 5
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
            row.addArrangedSubview(dot)
            
            // Feed name
            let nameLabel = UILabel()
            nameLabel.text = feed.name
            nameLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            nameLabel.textColor = .label
            nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            row.addArrangedSubview(nameLabel)
            
            // Progress bar
            let barBackground = UIView()
            barBackground.backgroundColor = .systemFill
            barBackground.layer.cornerRadius = 4
            barBackground.heightAnchor.constraint(equalToConstant: 8).isActive = true
            
            let barFill = UIView()
            barFill.backgroundColor = colors[index % colors.count]
            barFill.layer.cornerRadius = 4
            barFill.translatesAutoresizingMaskIntoConstraints = false
            barBackground.addSubview(barFill)
            
            let ratio = CGFloat(feed.count) / CGFloat(max(maxCount, 1))
            NSLayoutConstraint.activate([
                barFill.leadingAnchor.constraint(equalTo: barBackground.leadingAnchor),
                barFill.topAnchor.constraint(equalTo: barBackground.topAnchor),
                barFill.bottomAnchor.constraint(equalTo: barBackground.bottomAnchor),
                barFill.widthAnchor.constraint(equalTo: barBackground.widthAnchor, multiplier: ratio)
            ])
            
            row.addArrangedSubview(barBackground)
            
            // Count label
            let countLabel = UILabel()
            countLabel.text = "\(feed.count)"
            countLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            countLabel.textColor = .secondaryLabel
            countLabel.textAlignment = .right
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
            countLabel.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(countLabel)
            
            stack.addArrangedSubview(row)
        }
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        
        return card
    }
    
    // MARK: - Empty State
    
    private func makeEmptyState() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        
        let emoji = UILabel()
        emoji.text = "📖"
        emoji.font = UIFont.systemFont(ofSize: 48)
        
        let title = UILabel()
        title.text = "No Reading Data Yet"
        title.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = .label
        
        let subtitle = UILabel()
        subtitle.text = "Start reading stories to see your\nreading statistics and habits here."
        subtitle.font = UIFont.systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        
        stack.addArrangedSubview(emoji)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -32)
        ])
        
        return card
    }
    
    // MARK: - Clear Button
    
    private func makeClearButton() -> UIView {
        let button = UIButton(type: .system)
        button.setTitle("Clear All Stats", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: #selector(clearStatsTapped), for: .touchUpInside)
        
        let wrapper = UIView()
        button.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            button.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8)
        ])
        
        return wrapper
    }
    
    @objc private func clearStatsTapped() {
        let alert = UIAlertController(
            title: "Clear Reading Stats",
            message: "This will permanently delete all reading history. This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            ReadingStatsManager.shared.clearAll()
            self?.statsChanged()
        })
        present(alert, animated: true)
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}

// MARK: - Hourly Bar Chart View

/// Lightweight bar chart that shows reading activity by hour (0-23).
/// Draws 24 vertical bars with labels for select hours.
class HourlyBarChartView: UIView {
    
    private let distribution: [Int: Int]
    
    init(distribution: [Int: Int]) {
        self.distribution = distribution
        super.init(frame: .zero)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        self.distribution = [:]
        super.init(coder: coder)
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        let maxVal = distribution.values.max() ?? 1
        let barWidth = (rect.width - 4) / 24
        let chartHeight = rect.height - 20 // leave room for labels
        let labelHours = [0, 6, 12, 18, 23]
        
        for hour in 0..<24 {
            let count = distribution[hour] ?? 0
            let barHeight = maxVal > 0 ? (CGFloat(count) / CGFloat(maxVal)) * chartHeight : 0
            
            let x = 2 + CGFloat(hour) * barWidth
            let y = chartHeight - barHeight
            let barRect = CGRect(x: x + 1, y: y, width: barWidth - 2, height: barHeight)
            
            // Color intensity based on value
            let intensity = maxVal > 0 ? CGFloat(count) / CGFloat(maxVal) : 0
            let color = UIColor.systemBlue.withAlphaComponent(max(0.15, intensity))
            context.setFillColor(color.cgColor)
            
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: 2)
            context.addPath(path.cgPath)
            context.fillPath()
            
            // Draw hour labels for select hours
            if labelHours.contains(hour) {
                let label: String
                if hour == 0 { label = "12a" }
                else if hour < 12 { label = "\(hour)a" }
                else if hour == 12 { label = "12p" }
                else { label = "\(hour-12)p" }
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.tertiaryLabel
                ]
                let labelSize = (label as NSString).size(withAttributes: attrs)
                let labelX = x + (barWidth - labelSize.width) / 2
                (label as NSString).draw(at: CGPoint(x: labelX, y: chartHeight + 4), withAttributes: attrs)
            }
        }
    }
}
