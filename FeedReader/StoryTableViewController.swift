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
    
    /// Returns true when the search bar is active and has text.
    private var isFiltering: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }
    
    /// Returns the appropriate stories array based on search state.
    private var displayedStories: [Story] {
        return isFiltering ? filteredStories : stories
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
        
        // Add bookmarks button to navigation bar
        let bookmarksButton = UIBarButtonItem(
            image: UIImage(systemName: "bookmark"),
            style: .plain,
            target: self,
            action: #selector(showBookmarks)
        )
        bookmarksButton.tintColor = .systemOrange
        navigationItem.rightBarButtonItem = bookmarksButton
        
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
        
        // Update title with feed count
        updateTitle()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        searchDebounceTimer?.invalidate()
    }
    
    /// Update the navigation title to show active feed count.
    private func updateTitle() {
        let enabledCount = FeedManager.shared.enabledFeeds.count
        let totalCount = FeedManager.shared.count
        if totalCount <= 1 {
            navigationItem.title = "FeedReader"
        } else {
            navigationItem.title = "FeedReader (\(enabledCount)/\(totalCount) feeds)"
        }
    }
    
    /// Called when feed configuration changes — reload all data.
    @objc private func feedsChanged() {
        hasLoadedData = false
        updateTitle()
        loadData()
        hasLoadedData = true
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
    }
    
    func loadData() {
        if Reachability.isConnectedToNetwork() == true {
            let enabledFeeds = FeedManager.shared.enabledFeeds
            if enabledFeeds.isEmpty {
                stories = []
                tableView.reloadData()
                return
            }
            
            activityIndicator.startAnimating()
            feedParser.loadFeeds(enabledFeeds.map { $0.url })
            
        } else if let savedStories = loadStories() {
            stories = savedStories
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
}
