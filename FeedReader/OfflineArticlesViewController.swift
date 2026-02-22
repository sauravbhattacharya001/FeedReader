//
//  OfflineArticlesViewController.swift
//  FeedReader
//
//  Displays cached articles available for offline reading.
//  Shows a summary header with cache stats, search, sort options,
//  swipe-to-delete, and a Clear All action.
//

import UIKit

class OfflineArticlesViewController: UITableViewController {

    // MARK: - Properties

    private var articles: [CachedArticle] = []
    private var filteredArticles: [CachedArticle] = []
    private let searchController = UISearchController(searchResultsController: nil)

    private var isFiltering: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

    private var displayedArticles: [CachedArticle] {
        return isFiltering ? filteredArticles : articles
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Offline Articles"

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OfflineCell")

        // Search
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search cached articles"
        navigationItem.searchController = searchController
        definesPresentationContext = true

        // Nav bar buttons
        let clearButton = UIBarButtonItem(
            title: "Clear All",
            style: .plain,
            target: self,
            action: #selector(clearAllTapped)
        )
        clearButton.tintColor = .systemRed
        navigationItem.rightBarButtonItem = clearButton

        // Listen for cache changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cacheDidChange),
            name: .offlineCacheDidChange,
            object: nil
        )

        loadArticles()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Data

    private func loadArticles() {
        articles = OfflineCacheManager.shared.sortedByDate
        tableView.reloadData()
        updateEmptyState()
    }

    @objc private func cacheDidChange() {
        loadArticles()
    }

    private func updateEmptyState() {
        if articles.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No articles saved for offline reading.\n\nSwipe left on any story and tap\n\"Save Offline\" to cache it here."
            emptyLabel.textAlignment = .center
            emptyLabel.numberOfLines = 0
            emptyLabel.textColor = .secondaryLabel
            emptyLabel.font = UIFont.systemFont(ofSize: 16)
            tableView.backgroundView = emptyLabel
        } else {
            tableView.backgroundView = nil
        }
    }

    // MARK: - Actions

    @objc private func clearAllTapped() {
        guard !articles.isEmpty else { return }

        let alert = UIAlertController(
            title: "Clear Offline Cache",
            message: "Remove all \(articles.count) cached articles? This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { _ in
            OfflineCacheManager.shared.clearAll()
        })
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // summary header + articles
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return articles.isEmpty ? 0 : 1
        }
        return displayedArticles.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return nil }
        if articles.isEmpty { return nil }
        return "\(displayedArticles.count) article\(displayedArticles.count == 1 ? "" : "s")"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            // Summary cell
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "SummaryCell")
            let summary = OfflineCacheManager.shared.summary
            cell.textLabel?.text = "📦 Cache: \(summary.formattedSize)"
            cell.detailTextLabel?.text = "\(summary.articleCount)/\(OfflineCacheManager.maxArticles) articles"
            cell.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
            cell.backgroundColor = .secondarySystemBackground
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "OfflineCell", for: indexPath)
        let article = displayedArticles[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = article.story.title
        content.textProperties.numberOfLines = 2

        // Subtitle: feed name + save date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        var subtitle = dateFormatter.string(from: article.savedDate)
        if let feedName = article.story.sourceFeedName {
            subtitle = feedName + " · " + subtitle
        }
        content.secondaryText = subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)

        // Cache icon
        content.image = UIImage(systemName: "arrow.down.circle.fill")
        content.imageProperties.tintColor = .systemGreen

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }

        let article = displayedArticles[indexPath.row]

        // Navigate to story detail
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let storyVC = storyboard.instantiateViewController(withIdentifier: "StoryViewController") as? StoryViewController {
            storyVC.story = article.story
            navigationController?.pushViewController(storyVC, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.section == 1 else { return }
        let article = displayedArticles[indexPath.row]
        OfflineCacheManager.shared.removeFromCache(article.story)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRow indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            let article = self.displayedArticles[indexPath.row]
            OfflineCacheManager.shared.removeFromCache(article.story)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")

        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - UISearchResultsUpdating

extension OfflineArticlesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        filteredArticles = OfflineCacheManager.shared.search(query: query)
        tableView.reloadData()
    }
}
