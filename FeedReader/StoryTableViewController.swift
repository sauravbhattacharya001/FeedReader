//
//  StoryTableViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class StoryTableViewController: UITableViewController, XMLParserDelegate, UISearchResultsUpdating {
    
    // MARK: - Properties
    
    var stories = [Story]()
    
    /// Filtered stories shown when the search bar is active.
    private var filteredStories = [Story]()
    
    var parser = XMLParser()
    
    var element = NSString()
    
    var storyTitle = NSMutableString()
    var storyDescription = NSMutableString()
    var link = NSMutableString()
    var imagePath = NSMutableString()
    
    var activityIndicator = UIActivityIndicatorView()
    
    /// Search controller for filtering stories by title or description.
    private let searchController = UISearchController(searchResultsController: nil)
    
    /// In-memory image cache to avoid redundant network requests when
    /// cells are reused during scrolling. NSCache automatically evicts
    /// entries under memory pressure. (fixes #7)
    private let imageCache = NSCache<NSString, UIImage>()

    /// Tracks whether we are inside an <item> element so we only capture
    /// per-item data (title, description, guid) and ignore channel-level
    /// elements with the same names.
    private var insideItem = false
    
    /// Tracks whether the feed has been loaded at least once so that
    /// back-navigation from story detail does not trigger a redundant
    /// network fetch, avoiding UI flicker and scroll-position loss. (fixes #8)
    private var hasLoadedData = false
    
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
        
        // Add bookmarks button to navigation bar
        let bookmarksButton = UIBarButtonItem(
            image: UIImage(systemName: "bookmark"),
            style: .plain,
            target: self,
            action: #selector(showBookmarks)
        )
        bookmarksButton.tintColor = .systemOrange
        navigationItem.rightBarButtonItem = bookmarksButton
    }
    
    /// Present the bookmarks view controller.
    @objc private func showBookmarks() {
        let bookmarksVC = BookmarksViewController()
        navigationController?.pushViewController(bookmarksVC, animated: true)
    }
    
    /// Pull-to-refresh handler — reloads the RSS feed.
    @objc private func refreshFeed() {
        // Force a fresh load — beginParsing will call endRefreshing
        // on completion instead of using a hardcoded delay. (fixes race
        // condition where the 1-second timer fired before the async
        // fetch completed, leaving stale data visible.)
        loadData()
    }
    
    // MARK: - UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        filterStories(for: searchText)
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
        imageCache.removeAllObjects()
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
            // Parse the data from RSS Feed asynchronously to avoid blocking the UI.
            // Reuters discontinued public RSS feeds (~2020); use BBC News as default (fixes #6)
            beginParsing("https://feeds.bbci.co.uk/news/world/rss.xml")
            
        } else if let savedStories = loadStories() {
            // Load data from saved state.
            stories = savedStories
            self.tableView.reloadData()
        } else {
            // Show no internet connection image.
            if let resultController = storyboard!.instantiateViewController(withIdentifier: "NoInternetFound") as? NoInternetFoundViewController {
                present(resultController, animated: true, completion: nil)
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveStories()
    }
    
    // MARK: - RSS Feed Parser
    
    func beginParsing(_ url: String)
    {
        stories = []
        guard let feedURL = URL(string: url) else {
            print("Failed to create URL from string: \(url)")
            return
        }
        
        // Show loading indicator while fetching data
        activityIndicator.startAnimating()
        
        // Fetch RSS data asynchronously to avoid blocking the main thread (fixes #4)
        let task = URLSession.shared.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            guard let data = data, error == nil else {
                print("Failed to fetch RSS feed: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.refreshControl?.endRefreshing()
                }
                return
            }
            
            // Validate HTTP response status before parsing (fixes #6)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("RSS feed returned HTTP \(httpResponse.statusCode)")
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.refreshControl?.endRefreshing()
                }
                return
            }
            
            // Parse XML on the URLSession callback thread — safe because
            // the delegate methods only touch instance vars that are not
            // accessed from any other thread during parsing.
            self.parser = XMLParser(data: data)
            self.parser.delegate = self
            self.parser.parse()
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                self.refreshControl?.endRefreshing()
                self.tableView.reloadData()
            }
        }
        task.resume()
    }
    
    func beginParsingTest(_ url: String)
    {
        stories = []
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: url)) else {
            print("Failed to load test data from path: \(url)")
            return
        }
        parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        self.tableView.reloadData()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String])
    {
        element = elementName as NSString
        if (elementName as NSString).isEqual(to: "item")
        {
            insideItem = true
            storyTitle = NSMutableString()
            storyDescription = NSMutableString()
            link = NSMutableString()
            imagePath = NSMutableString()
        }
        
        // BBC RSS feeds use <media:thumbnail url="..."/> for per-item images.
        // The colon-prefixed element arrives as "media:thumbnail" in the
        // non-namespace-aware parser. Extract the URL from the attribute.
        if insideItem && (elementName == "media:thumbnail" || elementName == "enclosure") {
            if let urlAttr = attributeDict["url"], !urlAttr.isEmpty {
                // Only set if we haven't already found a thumbnail for this item
                if imagePath.length == 0 {
                    imagePath.setString(urlAttr)
                }
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String)
    {
        // Only capture text content when inside an <item> element to avoid
        // mixing channel-level title/description with per-item data.
        guard insideItem else { return }
        
        if element.isEqual(to: "title") {
            storyTitle.append(string)
        } else if element.isEqual(to: "description") {
            storyDescription.append(string)
        } else if element.isEqual(to: "guid"){
            link.append(string)
        }
        // Note: per-item image URLs are extracted from <media:thumbnail>
        // attributes in didStartElement, not from character data.
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?)
    {
        if (elementName as NSString).isEqual(to: "item") {
            // End of item — create the Story object
            let trimmedImagePath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if let aStory = Story(title: storyTitle as String, photo: UIImage(named: "sample")!, description: storyDescription as String, link: link.components(separatedBy: "\n")[0], imagePath: trimmedImagePath.isEmpty ? nil : trimmedImagePath) {
                stories.append(aStory)
            }
            insideItem = false
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedStories.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        // Table view cells are reused and should be dequeued using a cell identifier.
        let cellIndentifier = "StoryTableViewCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIndentifier, for: indexPath) as! StoryTableViewCell
        
        cell.titleLabel.text = displayedStories[indexPath.row].title
        cell.descriptionLabel.text = displayedStories[indexPath.row].body
        
        // Load thumbnail with in-memory cache to avoid redundant network
        // requests when cells are reused during scrolling. (fixes #7)
        // Only load images from safe URL schemes (https/http) to prevent
        // file:// or other scheme-based attacks from malicious RSS feeds.
        cell.photoImage.image = UIImage(named: "sample") // placeholder while loading
        if let imagePathString = displayedStories[indexPath.row].imagePath,
           Story.isSafeURL(imagePathString),
           let url = URL(string: imagePathString) {
            let cacheKey = imagePathString as NSString
            if let cachedImage = imageCache.object(forKey: cacheKey) {
                cell.photoImage.image = cachedImage
            } else {
                let currentIndexPath = indexPath
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    self?.imageCache.setObject(image, forKey: cacheKey)
                    DispatchQueue.main.async {
                        // Only update if the cell is still showing the same row
                        // (guards against cell reuse during fast scrolling)
                        if let visibleCell = self?.tableView.cellForRow(at: currentIndexPath) as? StoryTableViewCell {
                            visibleCell.photoImage.image = image
                        }
                    }
                }.resume()
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
    
    // MARK: - Navigation

    // Prepare segue for showing one story detail view.
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowDetail" {
            let storyDetailViewController = segue.destination as! StoryViewController
            
            // Get the cell that generated this segue.
            if let selectedStoryCell = sender as? StoryTableViewCell {
                let indexPath = tableView.indexPath(for: selectedStoryCell)!
                let selectedStory = displayedStories[indexPath.row]
                storyDetailViewController.story = selectedStory as Story
            }
        }
    }
    
    // MARK: - NSCoding
    
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
