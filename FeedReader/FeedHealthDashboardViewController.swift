//
//  FeedHealthDashboardViewController.swift
//  FeedReader
//
//  Interactive dashboard that visualizes per-feed health metrics —
//  status indicators, success rates, response times, staleness
//  warnings, and actionable recommendations. Uses FeedHealthManager
//  data to help users identify and fix problematic feeds.
//

import UIKit

class FeedHealthDashboardViewController: UIViewController {
    
    // MARK: - Types
    
    /// Sort criteria for the feed health table.
    enum SortBy: Int, CaseIterable {
        case status = 0
        case name
        case successRate
        case responseTime
        case lastUpdate
        
        var label: String {
            switch self {
            case .status: return "Status"
            case .name: return "Name"
            case .successRate: return "Success Rate"
            case .responseTime: return "Response Time"
            case .lastUpdate: return "Last Update"
            }
        }
    }
    
    /// Snapshot of a single feed's health for display.
    private struct FeedHealthRow {
        let feedURL: String
        let displayName: String
        let status: FeedHealthStatus
        let successRate: Double
        let avgResponseMs: Int
        let lastFetchDate: Date?
        let lastStoryDate: Date?
        let totalFetches: Int
        let recentErrors: [String]
    }
    
    // MARK: - Properties
    
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let refreshControl = UIRefreshControl()
    
    private var feedRows: [FeedHealthRow] = []
    private var currentSort: SortBy = .status
    private var sortAscending = true
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feed Health"
        view.backgroundColor = .systemGroupedBackground
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down"),
            style: .plain,
            target: self,
            action: #selector(showSortMenu)
        )
        
        setupScrollView()
        loadData()
        buildDashboard()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(healthDataChanged),
            name: .feedHealthDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Data
    
    private func loadData() {
        let manager = FeedHealthManager.shared
        let allURLs = manager.allTrackedFeedURLs()
        
        feedRows = allURLs.map { url in
            let report = manager.healthReport(for: url)
            let displayName = prettifyFeedURL(url)
            return FeedHealthRow(
                feedURL: url,
                displayName: displayName,
                status: report?.status ?? .unknown,
                successRate: report?.successRate ?? 0,
                avgResponseMs: report?.averageResponseTimeMs ?? 0,
                lastFetchDate: report?.lastFetchDate,
                lastStoryDate: report?.lastStoryDate,
                totalFetches: report?.totalFetches ?? 0,
                recentErrors: report?.recentErrors ?? []
            )
        }
        
        sortFeedRows()
    }
    
    private func sortFeedRows() {
        feedRows.sort { a, b in
            let result: Bool
            switch currentSort {
            case .status:
                result = statusOrder(a.status) < statusOrder(b.status)
            case .name:
                result = a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .successRate:
                result = a.successRate < b.successRate
            case .responseTime:
                result = a.avgResponseMs < b.avgResponseMs
            case .lastUpdate:
                let aDate = a.lastStoryDate ?? .distantPast
                let bDate = b.lastStoryDate ?? .distantPast
                result = aDate < bDate
            }
            return sortAscending ? result : !result
        }
    }
    
    private func statusOrder(_ status: FeedHealthStatus) -> Int {
        switch status {
        case .unhealthy: return 0
        case .degraded: return 1
        case .stale: return 2
        case .unknown: return 3
        case .healthy: return 4
        }
    }
    
    // MARK: - Layout
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        scrollView.refreshControl = refreshControl
        
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scrollView.addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    // MARK: - Build Dashboard
    
    private func buildDashboard() {
        // Clear existing content
        for subview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        
        buildSummaryCards()
        buildStatusBreakdown()
        buildFeedTable()
        buildRecommendations()
    }
    
    // MARK: - Summary Cards
    
    private func buildSummaryCards() {
        let totalFeeds = feedRows.count
        let healthyCount = feedRows.filter { $0.status == .healthy }.count
        let problemCount = feedRows.filter { $0.status == .unhealthy || $0.status == .degraded }.count
        let staleCount = feedRows.filter { $0.status == .stale }.count
        let avgSuccess = totalFeeds > 0
            ? feedRows.reduce(0.0) { $0 + $1.successRate } / Double(totalFeeds)
            : 0
        
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        
        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.distribution = .fillEqually
        topRow.addArrangedSubview(makeSummaryCard(
            title: "Total Feeds",
            value: "\(totalFeeds)",
            icon: "antenna.radiowaves.left.and.right",
            color: .systemBlue
        ))
        topRow.addArrangedSubview(makeSummaryCard(
            title: "Healthy",
            value: "\(healthyCount)",
            icon: "checkmark.circle.fill",
            color: .systemGreen
        ))
        
        let bottomRow = UIStackView()
        bottomRow.axis = .horizontal
        bottomRow.spacing = 12
        bottomRow.distribution = .fillEqually
        bottomRow.addArrangedSubview(makeSummaryCard(
            title: "Problems",
            value: "\(problemCount)",
            icon: "exclamationmark.triangle.fill",
            color: problemCount > 0 ? .systemRed : .systemGray
        ))
        bottomRow.addArrangedSubview(makeSummaryCard(
            title: "Avg Success",
            value: String(format: "%.0f%%", avgSuccess * 100),
            icon: "chart.bar.fill",
            color: avgSuccess >= 0.9 ? .systemGreen : avgSuccess >= 0.5 ? .systemOrange : .systemRed
        ))
        
        grid.addArrangedSubview(topRow)
        grid.addArrangedSubview(bottomRow)
        contentStack.addArrangedSubview(grid)
    }
    
    private func makeSummaryCard(title: String, value: String, icon: String, color: UIColor) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = color
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 28, weight: .bold)
        valueLabel.textColor = color
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        
        let stack = UIStackView(arrangedSubviews: [iconView, valueLabel, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        
        return card
    }
    
    // MARK: - Status Breakdown
    
    private func buildStatusBreakdown() {
        let card = makeCard(title: "Status Breakdown")
        let stack = card.viewWithTag(100) as! UIStackView
        
        let statuses: [(FeedHealthStatus, UIColor)] = [
            (.healthy, .systemGreen),
            (.degraded, .systemOrange),
            (.unhealthy, .systemRed),
            (.stale, .systemYellow),
            (.unknown, .systemGray)
        ]
        
        let total = max(feedRows.count, 1)
        
        // Horizontal bar chart
        let barContainer = UIView()
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barContainer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        barContainer.layer.cornerRadius = 12
        barContainer.clipsToBounds = true
        barContainer.backgroundColor = .systemGray5
        
        var previousAnchor = barContainer.leadingAnchor
        for (status, color) in statuses {
            let count = feedRows.filter { $0.status == status }.count
            guard count > 0 else { continue }
            
            let segment = UIView()
            segment.backgroundColor = color
            segment.translatesAutoresizingMaskIntoConstraints = false
            barContainer.addSubview(segment)
            
            NSLayoutConstraint.activate([
                segment.topAnchor.constraint(equalTo: barContainer.topAnchor),
                segment.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
                segment.leadingAnchor.constraint(equalTo: previousAnchor),
                segment.widthAnchor.constraint(equalTo: barContainer.widthAnchor, multiplier: CGFloat(count) / CGFloat(total))
            ])
            previousAnchor = segment.trailingAnchor
        }
        
        stack.addArrangedSubview(barContainer)
        
        // Legend
        let legendStack = UIStackView()
        legendStack.axis = .horizontal
        legendStack.spacing = 16
        legendStack.distribution = .fillEqually
        
        for (status, color) in statuses {
            let count = feedRows.filter { $0.status == status }.count
            let dot = UIView()
            dot.backgroundColor = color
            dot.layer.cornerRadius = 5
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
            
            let label = UILabel()
            label.text = "\(status.label) (\(count))"
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabel
            
            let item = UIStackView(arrangedSubviews: [dot, label])
            item.axis = .horizontal
            item.spacing = 4
            item.alignment = .center
            legendStack.addArrangedSubview(item)
        }
        
        stack.addArrangedSubview(legendStack)
        contentStack.addArrangedSubview(card)
    }
    
    // MARK: - Feed Table
    
    private func buildFeedTable() {
        let card = makeCard(title: "All Feeds")
        let stack = card.viewWithTag(100) as! UIStackView
        
        if feedRows.isEmpty {
            let empty = UILabel()
            empty.text = "No feeds tracked yet. Add some feeds and check back!"
            empty.font = .systemFont(ofSize: 14)
            empty.textColor = .tertiaryLabel
            empty.textAlignment = .center
            empty.numberOfLines = 0
            stack.addArrangedSubview(empty)
        } else {
            for (index, row) in feedRows.enumerated() {
                if index > 0 {
                    let separator = UIView()
                    separator.backgroundColor = .separator
                    separator.translatesAutoresizingMaskIntoConstraints = false
                    separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                    stack.addArrangedSubview(separator)
                }
                stack.addArrangedSubview(makeFeedRow(row))
            }
        }
        
        contentStack.addArrangedSubview(card)
    }
    
    private func makeFeedRow(_ row: FeedHealthRow) -> UIView {
        let container = UIView()
        
        // Status icon
        let statusIcon = UIImageView(image: UIImage(systemName: iconName(for: row.status)))
        statusIcon.tintColor = color(for: row.status)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.contentMode = .scaleAspectFit
        
        // Feed name
        let nameLabel = UILabel()
        nameLabel.text = row.displayName
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        
        // Metrics row
        let metricsLabel = UILabel()
        let successStr = String(format: "%.0f%%", row.successRate * 100)
        let responseStr = row.avgResponseMs > 0 ? "\(row.avgResponseMs)ms" : "—"
        let staleStr = formatStaleness(row.lastStoryDate)
        metricsLabel.text = "✓ \(successStr)  ⏱ \(responseStr)  📅 \(staleStr)"
        metricsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        metricsLabel.textColor = .secondaryLabel
        
        // Error indicator
        let errorLabel = UILabel()
        if !row.recentErrors.isEmpty {
            errorLabel.text = "⚠️ \(row.recentErrors.count) recent error(s)"
            errorLabel.font = .systemFont(ofSize: 11)
            errorLabel.textColor = .systemOrange
        }
        
        let textStack = UIStackView(arrangedSubviews: [nameLabel, metricsLabel])
        if !row.recentErrors.isEmpty {
            textStack.addArrangedSubview(errorLabel)
        }
        textStack.axis = .vertical
        textStack.spacing = 2
        
        let hStack = UIStackView(arrangedSubviews: [statusIcon, textStack])
        hStack.axis = .horizontal
        hStack.spacing = 12
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(hStack)
        NSLayoutConstraint.activate([
            statusIcon.widthAnchor.constraint(equalToConstant: 24),
            statusIcon.heightAnchor.constraint(equalToConstant: 24),
            hStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            hStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        return container
    }
    
    // MARK: - Recommendations
    
    private func buildRecommendations() {
        let issues = generateRecommendations()
        guard !issues.isEmpty else { return }
        
        let card = makeCard(title: "Recommendations")
        let stack = card.viewWithTag(100) as! UIStackView
        
        for issue in issues {
            let label = UILabel()
            label.text = issue
            label.font = .systemFont(ofSize: 13)
            label.textColor = .label
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        
        contentStack.addArrangedSubview(card)
    }
    
    private func generateRecommendations() -> [String] {
        var recs: [String] = []
        
        let unhealthy = feedRows.filter { $0.status == .unhealthy }
        if !unhealthy.isEmpty {
            let names = unhealthy.prefix(3).map { $0.displayName }.joined(separator: ", ")
            recs.append("🔴 \(unhealthy.count) feed(s) are unhealthy (\(names)). Consider removing or checking the URLs.")
        }
        
        let stale = feedRows.filter { $0.status == .stale }
        if !stale.isEmpty {
            let names = stale.prefix(3).map { $0.displayName }.joined(separator: ", ")
            recs.append("🟡 \(stale.count) feed(s) haven't published recently (\(names)). They may be inactive.")
        }
        
        let slow = feedRows.filter { $0.avgResponseMs > 3000 }
        if !slow.isEmpty {
            let names = slow.prefix(3).map { $0.displayName }.joined(separator: ", ")
            recs.append("🐢 \(slow.count) feed(s) are slow (>3s response): \(names).")
        }
        
        let lowSuccess = feedRows.filter { $0.successRate < 0.7 && $0.successRate > 0 && $0.totalFetches >= 3 }
        if !lowSuccess.isEmpty {
            recs.append("⚠️ \(lowSuccess.count) feed(s) have <70% success rate. Check your network or feed URLs.")
        }
        
        if feedRows.allSatisfy({ $0.status == .healthy }) && !feedRows.isEmpty {
            recs.append("✅ All feeds are healthy! Everything looks good.")
        }
        
        return recs
    }
    
    // MARK: - Helpers
    
    private func makeCard(title: String) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.tag = 100
        
        let outer = UIStackView(arrangedSubviews: [titleLabel, stack])
        outer.axis = .vertical
        outer.spacing = 12
        outer.translatesAutoresizingMaskIntoConstraints = false
        
        card.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            outer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            outer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            outer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        
        return card
    }
    
    private func iconName(for status: FeedHealthStatus) -> String {
        switch status {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.circle.fill"
        case .unhealthy: return "xmark.circle.fill"
        case .stale: return "clock.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    private func color(for status: FeedHealthStatus) -> UIColor {
        switch status {
        case .healthy: return .systemGreen
        case .degraded: return .systemOrange
        case .unhealthy: return .systemRed
        case .stale: return .systemYellow
        case .unknown: return .systemGray
        }
    }
    
    private func prettifyFeedURL(_ url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        var host = parsed.host ?? url
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        // Capitalize first letter
        return host.prefix(1).uppercased() + host.dropFirst()
    }
    
    private func formatStaleness(_ date: Date?) -> String {
        guard let date = date else { return "Never" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "< 1h ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        return "\(Int(interval / 604800))w ago"
    }
    
    // MARK: - Actions
    
    @objc private func showSortMenu() {
        let alert = UIAlertController(title: "Sort By", message: nil, preferredStyle: .actionSheet)
        
        for sort in SortBy.allCases {
            let isActive = sort == currentSort
            let arrow = isActive ? (sortAscending ? " ↑" : " ↓") : ""
            alert.addAction(UIAlertAction(title: sort.label + arrow, style: .default) { [weak self] _ in
                guard let self = self else { return }
                if self.currentSort == sort {
                    self.sortAscending.toggle()
                } else {
                    self.currentSort = sort
                    self.sortAscending = true
                }
                self.sortFeedRows()
                self.buildDashboard()
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func handleRefresh() {
        loadData()
        buildDashboard()
        refreshControl.endRefreshing()
    }
    
    @objc private func healthDataChanged() {
        loadData()
        buildDashboard()
    }
}
