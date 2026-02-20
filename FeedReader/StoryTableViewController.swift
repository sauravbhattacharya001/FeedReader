//
//  StoryTableViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class StoryTableViewController: UITableViewController, RSSFeedParserDelegate, UISearchResultsUpdating, UITableViewDataSourcePrefetching {
    
    // MARK: - Properties
    
    var stories = [Story]()
    
    /// Filtered stories shown when the search bar is active.
    private var filteredStories = [Story]()
    
    var activityIndicator = UIActivityIndicatorView()
    
    /// Search controller for filtering stories by title or description.
    private let searchController = UISearchController(searchResultsController: nil)
    
    /// RSS feed parser — handles XML parsing and multi-feed aggregation.
    private let feedParser = RSSFeedParser()

    /// Tracks whether the feed has been loaded at least once so that
    /// back-navigation from story detail does not trigger a redundant
    /// network fetch, avoiding UI flicker and scroll-position loss. (fixes #8)
    private var hasLoadedData = false
    
    /// Debounce timer for search filtering.
    private var searchDebounceTimer: Timer?
    
    /// Current read status filter.
    private var readFilter: ReadStatusManager.ReadFilter = .all
    
    /// Segmented control for filtering by read/unread.
    private let readFilterControl: UISegmentedControl = {
        let items = ReadStatusManager.ReadFilter.allCases.map { $0.title }
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        return control
    }()
    
    /// Returns true when the search bar is active and has text.
    private var isFiltering: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }
    
    /// Returns the appropriate stories array based on search and read filter state.
    private var displayedStories: [Story] {
        var result = isFiltering ? filteredStories : stories
        // Apply read status filter
        if readFilter != .all {
            result = ReadStatusManager.shared.filterStories(result, readStatus: readFilter)
        }
        return result
    }

    // MARK: - ViewController methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        feedParser.delegate = self
        
        // Set up loading indicator
        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.center = view.center
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        // Set up pull-to-refresh
        refreshControl = UIRefreshControl()
        refreshControl?.attributedTitle = NSAttributedString(string: "Pull to refresh feed")
        refreshControl?.addTarget(self, action: #selector(refreshFeed), for: .valueChanged)
        
        // Set up search controller
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search stories..."
        navigationItem.searchController = searchController
        definesPresentationContext = true
        
        // Enable image prefetching for smoother scrolling.
        tableView.prefetchDataSource = self
        
        // Set up read filter segmented control in the table header
        readFilterControl.addTarget(self, action: #selector(readFilterChanged(_:)), for: .valueChanged)
        
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 44))
        readFilterControl.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(readFilterControl)
        NSLayoutConstraint.activate([
            readFilterControl.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            readFilterControl.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            readFilterControl.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
        tableView.tableHeaderView = headerView
        
        // Add bookmarks button and mark-all-read button to navigation bar (right side)
        let bookmarksButton = UIBarButtonItem(
            image: UIImage(systemName: "bookmark"),
            style: .plain,
            target: self,
            action: #selector(showBookmarks)
        )
        bookmarksButton.tintColor = .systemOrange
        
        let markAllReadButton = UIBarButtonItem(
            image: UIImage(systemName: "checkmark.circle"),
            style: .plain,
            target: self,
            action: #selector(markAllRead)
        )
        markAllReadButton.tintColor = .systemGreen
        
        navigationItem.rightBarButtonItems = [bookmarksButton, markAllReadButton]
        
        // Add feeds manager button to navigation bar (left side)
        let feedsButton = UIBarButtonItem(
            image: UIImage(systemName: "antenna.radiowaves.left.and.right"),
            style: .plain,
            target: self,
            action: #selector(showFeedManager)
        )
        feedsButton.tintColor = .systemBlue
        navigationItem.leftBarButtonItem = feedsButton
        
        // Listen for feed changes to reload data
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(feedsChanged),
            name: .feedsDidChange,
            object: nil
        )
        
        // Listen for read status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readStatusChanged),
            name: .readStatusDidChange,
            object: nil
        )
        
        // Update title with feed count
        updateTitle()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        searchDebounceTimer?.invalidate()
    }
    
    /// Update the navigation title to show active feed count and unread count.
    private func updateTitle() {
        let unreadCount = ReadStatusManager.shared.unreadCount(in: stories)
        if unreadCount > 0 {
            navigationItem.title = "FeedReader (\(unreadCount) unread)"
        } else {
            let enabledCount = FeedManager.shared.enabledFeeds.count
            let totalCount = FeedManager.shared.count
            if totalCount <= 1 {
                navigationItem.title = "FeedReader"
            } else {
                navigationItem.title = "FeedReader (\(enabledCount)/\(totalCount) feeds)"
            }
        }
        
        // Update segment titles with counts
        updateFilterCounts()
    }
    
    /// Update the segment control titles with story counts.
    private func updateFilterCounts() {
        let baseStories = isFiltering ? filteredStories : stories
        let allCount = baseStories.count
        let unreadCount = ReadStatusManager.shared.unreadCount(in: baseStories)
        let readCount = allCount - unreadCount
        
        readFilterControl.setTitle("All (\(allCount))", forSegmentAt: 0)
        readFilterControl.setTitle("Unread (\(unreadCount))", forSegmentAt: 1)
        readFilterControl.setTitle("Read (\(readCount))", forSegmentAt: 2)
    }
    
    /// Called when feed configuration changes — reload all data.
    @objc private func feedsChanged() {
        hasLoadedData = false
        updateTitle()
        loadData()
        hasLoadedData = true
    }
    
    /// Called when read status changes — refresh display.
    @objc private func readStatusChanged() {
        updateTitle()
        tableView.reloadData()
    }
    
    /// Present the bookmarks view controller.
    @objc private func showBookmarks() {
        let bookmarksVC = BookmarksViewController()
        navigationController?.pushViewController(bookmarksVC, animated: true)
    }
    
    /// Present the feed manager view controller.
    @objc private func showFeedManager() {
        let feedListVC = FeedListViewController()
        navigationController?.pushViewController(feedListVC, animated: true)
    }
    
    /// Pull-to-refresh handler — reloads the RSS feed.
    @objc private func refreshFeed() {
        loadData()
    }
    
    /// Handle read filter segment control changes.
    @objc private func readFilterChanged(_ sender: UISegmentedControl) {
        readFilter = ReadStatusManager.ReadFilter(rawValue: sender.selectedSegmentIndex) ?? .all
        tableView.reloadData()
    }
    
    /// Mark all current stories as read.
    @objc private func markAllRead() {
        let unreadCount = ReadStatusManager.shared.unreadCount(in: stories)
        guard unreadCount > 0 else {
            showToast("All stories are already read")
            return
        }
        
        let alert = UIAlertController(
            title: "Mark All Read",
            message: "Mark all \(unreadCount) unread stories as read?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Mark All Read", style: .default) { [weak self] _ in
            guard let self = self else { return }
            ReadStatusManager.shared.markAllAsRead(self.stories)
            self.showToast("Marked \(unreadCount) stories as read ✓")
        })
        present(alert, animated: true)
    }
    
    // MARK: - UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.filterStories(for: searchText)
        }
    }
    
    /// Filters stories by matching the search text against title and description.
    private func filterStories(for searchText: String) {
        let lowercasedSearch = searchText.lowercased()
        filteredStories = stories.filter { story in
            story.title.lowercased().contains(lowercasedSearch) ||
            story.body.lowercased().contains(lowercasedSearch)
        }
        updateTitle()
        tableView.reloadData()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        ImageCache.shared.clearCache()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !hasLoadedData {
            loadData()
            hasLoadedData = true
        }
        // Refresh read status indicators when returning from detail
        updateTitle()
        tableView.reloadData()
    }
    
    func loadData() {
        if Reachability.isConnectedToNetwork() == true {
            let enabledFeeds = FeedManager.shared.enabledFeeds
            if enabledFeeds.isEmpty {
                stories = []
                updateTitle()
                tableView.reloadData()
                return
            }
            
            activityIndicator.startAnimating()
            feedParser.loadFeeds(enabledFeeds.map { $0.url })
            
        } else if let savedStories = loadStories() {
            stories = savedStories
            updateTitle()
            tableView.reloadData()
        } else {
            if let resultController = storyboard!.instantiateViewController(withIdentifier: "NoInternetFound") as? NoInternetFoundViewController {
                present(resultController, animated: true, completion: nil)
            }
        }
    }
    
    // MARK: - RSSFeedParserDelegate
    
    func parserDidFinishLoading(stories: [Story]) {
        self.stories = stories
        activityIndicator.stopAnimating()
        refreshControl?.endRefreshing()
        updateTitle()
        tableView.reloadData()
    }
    
    func parserDidFailWithError(_ error: Error?) {
        print("Feed parsing error: \(error?.localizedDescription ?? "unknown")")
        activityIndicator.stopAnimating()
        refreshControl?.endRefreshing()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveStories()
    }
    
    // MARK: - Test Support
    
    /// Parse stories from a local file path (for unit testing).
    func beginParsingTest(_ path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("Failed to load test data from path: \(path)")
            return
        }
        stories = feedParser.parseData(data)
        tableView.reloadData()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedStories.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIndentifier = "StoryTableViewCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIndentifier, for: indexPath) as! StoryTableViewCell
        
        let story = displayedStories[indexPath.row]
        cell.titleLabel.text = story.title
        cell.descriptionLabel.text = story.body
        
        // Configure read/unread status
        let isRead = ReadStatusManager.shared.isRead(story)
        cell.configureReadStatus(isRead: isRead)
        
        // Load thumbnail via shared ImageCache
        cell.photoImage.image = UIImage(named: "sample") // placeholder
        if let imagePathString = story.imagePath {
            let currentIndexPath = indexPath
            ImageCache.shared.loadImage(from: imagePathString) { [weak self] image in
                guard let image = image else { return }
                // Only update if the cell is still showing the same row
                if let visibleCell = self?.tableView.cellForRow(at: currentIndexPath) as? StoryTableViewCell {
                    visibleCell.photoImage.image = image
                }
            }
        }
        
        return cell
    }
    
    // MARK: - Table View Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let story = displayedStories[indexPath.row]
        // Mark story as read when tapped
        ReadStatusManager.shared.markAsRead(story)
    }
    
    // MARK: - Swipe Actions
    
    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let story = displayedStories[indexPath.row]
        let isBookmarked = BookmarkManager.shared.isBookmarked(story)
        
        let bookmarkAction = UIContextualAction(style: .normal, title: nil) { _, _, completionHandler in
            BookmarkManager.shared.toggleBookmark(story)
            completionHandler(true)
        }
        
        bookmarkAction.image = UIImage(systemName: isBookmarked ? "bookmark.slash" : "bookmark.fill")
        bookmarkAction.backgroundColor = isBookmarked ? .systemGray : .systemOrange
        
        return UISwipeActionsConfiguration(actions: [bookmarkAction])
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let story = displayedStories[indexPath.row]
        let isRead = ReadStatusManager.shared.isRead(story)
        
        let readAction = UIContextualAction(style: .normal, title: nil) { _, _, completionHandler in
            ReadStatusManager.shared.toggleReadStatus(story)
            completionHandler(true)
        }
        
        readAction.image = UIImage(systemName: isRead ? "envelope.badge" : "envelope.open")
        readAction.backgroundColor = isRead ? .systemBlue : .systemGray
        
        return UISwipeActionsConfiguration(actions: [readAction])
    }
    
    // MARK: - Prefetching
    
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap { indexPath -> String? in
            guard indexPath.row < displayedStories.count else { return nil }
            return displayedStories[indexPath.row].imagePath
        }
        ImageCache.shared.prefetch(urls: urls)
    }
    
    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowDetail" {
            let storyDetailViewController = segue.destination as! StoryViewController
            
            if let selectedStoryCell = sender as? StoryTableViewCell {
                let indexPath = tableView.indexPath(for: selectedStoryCell)!
                let selectedStory = displayedStories[indexPath.row]
                storyDetailViewController.story = selectedStory as Story
                
                // Mark as read when navigating to detail
                ReadStatusManager.shared.markAsRead(selectedStory)
            }
        }
    }
    
    // MARK: - Persistence
    
    func saveStories() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: stories, requiringSecureCoding: true)
            try data.write(to: Story.ArchiveURL)
        } catch {
            print("Failed to save stories: \(error)")
        }
    }
    
    func loadStories() -> [Story]? {
        guard let data = try? Data(contentsOf: Story.ArchiveURL) else {
            return nil
        }
        return (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, Story.self], from: data)) as? [Story]
    }
    
    // MARK: - Helpers
    
    /// Display a brief toast message at the bottom of the screen.
    private func showToast(_ message: String) {
        let toastLabel = UILabel()
        toastLabel.text = message
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastLabel.layer.cornerRadius = 16
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        
        let textSize = toastLabel.intrinsicContentSize
        let width = textSize.width + 40
        let height: CGFloat = 36
        toastLabel.frame = CGRect(
            x: (view.frame.width - width) / 2,
            y: view.frame.height - 120,
            width: width,
            height: height
        )
        
        view.addSubview(toastLabel)
        
        UIView.animate(withDuration: 0.3, animations: {
            toastLabel.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.2, options: [], animations: {
                toastLabel.alpha = 0
            }) { _ in
                toastLabel.removeFromSuperview()
            }
        }
    }
}
