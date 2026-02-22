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

class FeedListViewController: UITableViewController, UIDocumentPickerDelegate {
    
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
        
        let opmlButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down.square"),
            style: .plain,
            target: self,
            action: #selector(showOPMLMenu)
        )
        opmlButton.accessibilityLabel = "OPML Import/Export"
        
        navigationItem.leftBarButtonItems = [addButton, opmlButton]
        
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
    
    // MARK: - OPML Import/Export
    
    /// Show action sheet with OPML import/export options.
    @objc private func showOPMLMenu() {
        let alert = UIAlertController(
            title: "OPML Import/Export",
            message: "Import feeds from other RSS readers, or export your feeds to share.",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Import from File", style: .default) { [weak self] _ in
            self?.importOPML()
        })
        
        alert.addAction(UIAlertAction(title: "Import from URL", style: .default) { [weak self] _ in
            self?.importOPMLFromURL()
        })
        
        alert.addAction(UIAlertAction(title: "Import from Clipboard", style: .default) { [weak self] _ in
            self?.importOPMLFromClipboard()
        })
        
        let exportTitle = "Export All Feeds (\(FeedManager.shared.count))"
        alert.addAction(UIAlertAction(title: exportTitle, style: .default) { [weak self] _ in
            self?.exportOPML(enabledOnly: false)
        })
        
        if FeedManager.shared.enabledFeeds.count != FeedManager.shared.count {
            let enabledTitle = "Export Enabled Only (\(FeedManager.shared.enabledFeeds.count))"
            alert.addAction(UIAlertAction(title: enabledTitle, style: .default) { [weak self] _ in
                self?.exportOPML(enabledOnly: true)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Copy OPML to Clipboard", style: .default) { [weak self] _ in
            self?.copyOPMLToClipboard()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // iPad support — action sheets need a source for popover
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItems?[1]
        }
        
        present(alert, animated: true)
    }
    
    /// Import OPML via document picker (Files app).
    private func importOPML() {
        let types = ["public.xml", "org.opml.opml", "public.text"]
        let picker = UIDocumentPickerViewController(
            documentTypes: types,
            in: .import
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    /// Import OPML from a URL.
    private func importOPMLFromURL() {
        let alert = UIAlertController(
            title: "Import from URL",
            message: "Enter the URL of an OPML file.",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/feeds.opml"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Import", style: .default) { [weak self] _ in
            guard let urlString = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "https" || scheme == "http") else {
                self?.showError("Please enter a valid https:// or http:// URL.")
                return
            }
            
            self?.downloadAndImportOPML(url)
        })
        
        present(alert, animated: true)
    }
    
    /// Download an OPML file and import it.
    private func downloadAndImportOPML(_ url: URL) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showError("Download failed: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self?.showError("No data received from the URL.")
                    return
                }
                
                let outlines = OPMLManager.shared.parseOPMLData(data)
                if outlines.isEmpty {
                    self?.showError("No valid RSS feeds found in the OPML file.")
                    return
                }
                
                self?.confirmImport(outlines)
            }
        }
        task.resume()
    }
    
    /// Import OPML from clipboard content.
    private func importOPMLFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string,
              !clipboardString.isEmpty else {
            showError("Clipboard is empty. Copy OPML content first.")
            return
        }
        
        let outlines = OPMLManager.shared.parseOPML(clipboardString)
        if outlines.isEmpty {
            showError("No valid RSS feeds found in clipboard content.")
            return
        }
        
        confirmImport(outlines)
    }
    
    /// Show confirmation dialog before importing feeds.
    private func confirmImport(_ outlines: [OPMLOutline]) {
        let existingCount = outlines.filter { FeedManager.shared.feedExists(url: $0.xmlUrl) }.count
        let newCount = outlines.count - existingCount
        
        var message = "Found \(outlines.count) feed\(outlines.count == 1 ? "" : "s")."
        if newCount > 0 {
            message += "\n\(newCount) new feed\(newCount == 1 ? "" : "s") will be added."
        }
        if existingCount > 0 {
            message += "\n\(existingCount) duplicate\(existingCount == 1 ? "" : "s") will be skipped."
        }
        
        if newCount == 0 {
            showError("All feeds in this OPML file are already in your list.")
            return
        }
        
        let alert = UIAlertController(
            title: "Import Feeds",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Import \(newCount)", style: .default) { [weak self] _ in
            let result = OPMLManager.shared.importOutlines(outlines)
            self?.tableView.reloadData()
            self?.showToast(result.summary)
        })
        
        present(alert, animated: true)
    }
    
    /// Export feeds as OPML via share sheet.
    private func exportOPML(enabledOnly: Bool) {
        do {
            let fileURL = try OPMLManager.shared.exportToTemporaryFile(includeDisabled: !enabledOnly)
            
            let activityVC = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            
            // iPad support
            if let popover = activityVC.popoverPresentationController {
                popover.barButtonItem = navigationItem.leftBarButtonItems?[1]
            }
            
            present(activityVC, animated: true)
        } catch {
            showError("Failed to export: \(error.localizedDescription)")
        }
    }
    
    /// Copy OPML content to clipboard.
    private func copyOPMLToClipboard() {
        let opml = OPMLManager.shared.exportToString()
        UIPasteboard.general.string = opml
        showToast("OPML copied to clipboard")
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
    
    // MARK: - UIDocumentPickerDelegate
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        // Ensure we can access the file (security-scoped resource)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let outlines = try OPMLManager.shared.parseOPMLFile(url)
            if outlines.isEmpty {
                showError("No valid RSS feeds found in this file.")
                return
            }
            confirmImport(outlines)
        } catch {
            showError("Failed to read file: \(error.localizedDescription)")
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Nothing to do
    }
}
