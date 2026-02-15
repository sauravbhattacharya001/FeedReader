//
//  BookmarksViewController.swift
//  FeedReader
//
//  Displays bookmarked stories in a table view with swipe-to-delete
//  and empty state messaging. Tapping a bookmark navigates to the
//  story detail view.
//

import UIKit

class BookmarksViewController: UITableViewController {
    
    // MARK: - Properties
    
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No bookmarks yet.\nSwipe right on a story or tap ★ to save it."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = UIFont.systemFont(ofSize: 16)
        return label
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Bookmarks"
        
        // Register cell
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BookmarkCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        
        // Navigation bar buttons
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear All",
            style: .plain,
            target: self,
            action: #selector(clearAllBookmarks)
        )
        
        // Listen for bookmark changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksChanged),
            name: .bookmarksDidChange,
            object: nil
        )
        
        updateEmptyState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Actions
    
    @objc private func clearAllBookmarks() {
        guard BookmarkManager.shared.count > 0 else { return }
        
        let alert = UIAlertController(
            title: "Clear Bookmarks",
            message: "Remove all \(BookmarkManager.shared.count) bookmarked stories?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { _ in
            BookmarkManager.shared.clearAll()
            self.tableView.reloadData()
            self.updateEmptyState()
        })
        present(alert, animated: true)
    }
    
    @objc private func bookmarksChanged() {
        tableView.reloadData()
        updateEmptyState()
    }
    
    // MARK: - Empty State
    
    private func updateEmptyState() {
        if BookmarkManager.shared.count == 0 {
            tableView.backgroundView = emptyLabel
            navigationItem.rightBarButtonItem?.isEnabled = false
        } else {
            tableView.backgroundView = nil
            navigationItem.rightBarButtonItem?.isEnabled = true
        }
    }
    
    // MARK: - Table View Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return BookmarkManager.shared.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkCell", for: indexPath)
        let story = BookmarkManager.shared.bookmarks[indexPath.row]
        
        // Configure cell with story info
        var content = cell.defaultContentConfiguration()
        content.text = story.title
        content.secondaryText = story.body.count > 120
            ? String(story.body.prefix(120)) + "..."
            : story.body
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: "bookmark.fill")
        content.imageProperties.tintColor = .systemOrange
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    // MARK: - Table View Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let story = BookmarkManager.shared.bookmarks[indexPath.row]
        
        // Create and push story detail view controller
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let detailVC = storyboard.instantiateViewController(withIdentifier: "StoryViewController") as? StoryViewController {
            detailVC.story = story
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            BookmarkManager.shared.removeBookmark(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            updateEmptyState()
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRow indexPath: IndexPath) -> String? {
        return "Remove"
    }
}
