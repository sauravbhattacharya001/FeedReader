//
//  StoryViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class StoryViewController: UIViewController {
    
    // MARK: - Properties
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var photoImage: UIImageView!
    @IBOutlet weak var linkButton: UIButton!
    
    var linkTarget: String = ""
    
    // This value is passed by `StoryTableViewController` in `prepareForSegue(_:sender:)`
    var story: Story?
    
    /// Bookmark bar button for toggling bookmark state.
    private var bookmarkButton: UIBarButtonItem!
    
    // MARK: - ViewController methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let story = story {
            titleLabel.text   = story.title
            photoImage.image = story.photo
            descriptionLabel.text = story.body
            linkTarget = story.link
        }
        
        // Create bookmark and share buttons for the navigation bar
        bookmarkButton = UIBarButtonItem(
            image: bookmarkIcon(),
            style: .plain,
            target: self,
            action: #selector(toggleBookmark)
        )
        bookmarkButton.tintColor = .systemOrange
        
        let shareButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareStory)
        )
        
        navigationItem.rightBarButtonItems = [shareButton, bookmarkButton]
    }
    
    // MARK: - Bookmark
    
    /// Returns the appropriate bookmark icon based on current state.
    private func bookmarkIcon() -> UIImage? {
        guard let story = story else {
            return UIImage(systemName: "bookmark")
        }
        let name = BookmarkManager.shared.isBookmarked(story) ? "bookmark.fill" : "bookmark"
        return UIImage(systemName: name)
    }
    
    /// Updates the bookmark button icon to reflect current state.
    private func updateBookmarkIcon() {
        bookmarkButton.image = bookmarkIcon()
    }
    
    /// Toggle bookmark state for the current story.
    @objc private func toggleBookmark() {
        guard let story = story else { return }
        
        let isNowBookmarked = BookmarkManager.shared.toggleBookmark(story)
        updateBookmarkIcon()
        
        // Brief haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Show a brief toast-style notification
        let message = isNowBookmarked ? "Bookmarked ★" : "Removed from bookmarks"
        showToast(message)
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
    
    // MARK: - Share
    
    /// Share the current story via the system share sheet.
    @objc private func shareStory() {
        guard let story = story else { return }
        
        var shareItems: [Any] = []
        shareItems.append(story.title)
        
        // Include a brief description if it's not too long
        let shortBody = story.body.count > 200
            ? String(story.body.prefix(200)) + "..."
            : story.body
        shareItems.append(shortBody)
        
        if let url = URL(string: story.link) {
            shareItems.append(url)
        }
        
        let activityVC = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
        
        // iPad requires a popover source
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(activityVC, animated: true, completion: nil)
    }
    
    // Called when open link is clicked.
    @IBAction func clickedLink(_ sender: AnyObject) {
        guard let url = URL(string: linkTarget) else {
            print("Invalid URL: \(linkTarget)")
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
