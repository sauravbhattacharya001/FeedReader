//
//  FeedListViewController.swift
//  FeedReader
//
//  Displays the user's configured RSS feeds with options to:
//  - Toggle feeds on/off
//  - Add feeds from presets or custom URL
//  - Remove feeds with swipe-to-delete
//  - Reorder feeds via edit mode
//

import UIKit

class FeedListViewController: UITableViewController {
    
    // MARK: - Properties
    
    private enum Section: Int, CaseIterable {
        case activeFeeds = 0
        case addFeeds = 1
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Manage Feeds"
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FeedCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AddCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        
        // Navigation bar buttons
        navigationItem.rightBarButtonItem = editButtonItem
        
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addCustomFeed)
        )
        navigationItem.leftBarButtonItem = addButton
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(feedsChanged),
            name: .feedsDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func feedsChanged() {
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    /// Show dialog to add a custom RSS feed by URL.
    @objc private func addCustomFeed() {
        let alert = UIAlertController(
            title: "Add Custom Feed",
            message: "Enter the RSS feed name and URL.",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Feed Name"
            textField.autocapitalizationType = .words
        }
        
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/rss.xml"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, !url.isEmpty else {
                self?.showError("Please enter both a name and URL.")
                return
            }
            
            if FeedManager.shared.feedExists(url: url) {
                self?.showError("This feed URL is already in your list.")
                return
            }
            
            if FeedManager.shared.addCustomFeed(name: name, url: url) != nil {
                self?.tableView.reloadData()
                self?.showToast("Added \"\(name)\"")
            } else {
                self?.showError("Invalid URL. Please enter a valid https:// or http:// RSS feed URL.")
            }
        })
        
        present(alert, animated: true)
    }
    
    /// Add a preset feed to the user's list.
    private func addPresetFeed(_ preset: Feed) {
        if FeedManager.shared.feedExists(url: preset.url) {
            showError("\"\(preset.name)\" is already in your feeds.")
            return
        }
        
        let feed = Feed(name: preset.name, url: preset.url, isEnabled: true)
        FeedManager.shared.addFeed(feed)
        tableView.reloadData()
        showToast("Added \"\(preset.name)\"")
    }
    
    // MARK: - Table View Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .activeFeeds: return "Your Feeds (\(FeedManager.shared.enabledFeeds.count) active)"
        case .addFeeds: return "Available Feeds"
        default: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .activeFeeds:
            if FeedManager.shared.count == 0 {
                return "No feeds configured. Add a feed to get started."
            }
            return "Toggle feeds on/off. Swipe to remove. Tap Edit to reorder."
        case .addFeeds:
            return "Tap a feed to add it to your list. Use + to add a custom RSS URL."
        default: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .activeFeeds: return FeedManager.shared.count
        case .addFeeds: return availablePresets().count
        default: return 0
        }
    }
    
    /// Returns preset feeds not already in the user's list.
    private func availablePresets() -> [Feed] {
        return Feed.presets.filter { preset in
            !FeedManager.shared.feedExists(url: preset.url)
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .activeFeeds:
            let cell = tableView.dequeueReusableCell(withIdentifier: "FeedCell", for: indexPath)
            let feed = FeedManager.shared.feeds[indexPath.row]
            
            var content = cell.defaultContentConfiguration()
            content.text = feed.name
            content.secondaryText = feed.url
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
            content.secondaryTextProperties.numberOfLines = 1
            
            // Show enabled/disabled state with icon
            let iconName = feed.isEnabled ? "checkmark.circle.fill" : "circle"
            let iconColor: UIColor = feed.isEnabled ? .systemGreen : .systemGray
            content.image = UIImage(systemName: iconName)
            content.imageProperties.tintColor = iconColor
            
            cell.contentConfiguration = content
            cell.accessoryType = .none
            
            return cell
            
        case .addFeeds:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddCell", for: indexPath)
            let presets = availablePresets()
            let preset = presets[indexPath.row]
            
            var content = cell.defaultContentConfiguration()
            content.text = preset.name
            content.secondaryText = preset.url
            content.secondaryTextProperties.color = .tertiaryLabel
            content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
            content.secondaryTextProperties.numberOfLines = 1
            content.image = UIImage(systemName: "plus.circle")
            content.imageProperties.tintColor = .systemBlue
            
            cell.contentConfiguration = content
            cell.accessoryType = .none
            
            return cell
            
        default:
            return UITableViewCell()
        }
    }
    
    // MARK: - Table View Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch Section(rawValue: indexPath.section) {
        case .activeFeeds:
            // Toggle feed enabled/disabled
            FeedManager.shared.toggleFeed(at: indexPath.row)
            tableView.reloadData()
            
        case .addFeeds:
            // Add preset feed
            let presets = availablePresets()
            addPresetFeed(presets[indexPath.row])
            
        default:
            break
        }
    }
    
    // MARK: - Editing
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return Section(rawValue: indexPath.section) == .activeFeeds
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && Section(rawValue: indexPath.section) == .activeFeeds {
            let feed = FeedManager.shared.feeds[indexPath.row]
            FeedManager.shared.removeFeed(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            // Reload to update available presets section
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                tableView.reloadData()
            }
            
            showToast("Removed \"\(feed.name)\"")
        }
    }
    
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return Section(rawValue: indexPath.section) == .activeFeeds
    }
    
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        FeedManager.shared.moveFeed(from: sourceIndexPath.row, to: destinationIndexPath.row)
    }
    
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        // Only allow reordering within active feeds section
        if proposedDestinationIndexPath.section != Section.activeFeeds.rawValue {
            return sourceIndexPath
        }
        return proposedDestinationIndexPath
    }
    
    override func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRow indexPath: IndexPath) -> String? {
        return "Remove"
    }
    
    // MARK: - Helpers
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
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
