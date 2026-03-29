//
//  StoryViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit
import AVFoundation

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
    
    /// Offline cache bar button for save/remove.
    private var offlineButton: UIBarButtonItem!
    
    /// Text-to-speech bar button for reading articles aloud.
    private var ttsButton: UIBarButtonItem!
    
    /// Timestamp when the user opened this article (for reading time tracking).
    private var viewStartTime: Date?
    
    // MARK: - ViewController methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let story = story {
            titleLabel.text   = story.title
            photoImage.image = story.photo
            descriptionLabel.text = story.body
            linkTarget = story.link
            
            // Show paywall warning if detected
            let paywallResult = ArticlePaywallDetector.shared.analyze(story: story)
            if paywallResult.likelihood != .none {
                let warning = "\(paywallResult.likelihood.emoji) \(paywallResult.likelihood.rawValue)\n\n\(story.body)"
                descriptionLabel.text = warning
            }
        }
        
        // Create bookmark, offline, and share buttons for the navigation bar
        bookmarkButton = UIBarButtonItem(
            image: bookmarkIcon(),
            style: .plain,
            target: self,
            action: #selector(toggleBookmark)
        )
        bookmarkButton.tintColor = .systemOrange
        
        offlineButton = UIBarButtonItem(
            image: offlineIcon(),
            style: .plain,
            target: self,
            action: #selector(toggleOfflineCache)
        )
        offlineButton.tintColor = .systemGreen
        
        ttsButton = UIBarButtonItem(
            image: UIImage(systemName: "speaker.wave.2"),
            style: .plain,
            target: self,
            action: #selector(toggleTTS)
        )
        ttsButton.tintColor = .systemBlue
        
        let shareButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareStory)
        )
        
        navigationItem.rightBarButtonItems = [shareButton, bookmarkButton, offlineButton, ttsButton]
        
        // Listen for TTS state changes
        ArticleTextToSpeech.shared.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewStartTime = Date()
        
        // Record the visit in reading history so that ReadingStatsManager,
        // DigestGenerator, and the history UI actually receive data.
        // Previously this call was missing, leaving all history-dependent
        // features non-functional (bug fix).
        if let story = story {
            ReadingHistoryManager.shared.recordVisit(
                link: story.link,
                title: story.title,
                feedName: story.sourceFeedName ?? "Unknown"
            )
            // Also mark the article as read for the read/unread filter
            ReadStatusManager.shared.markAsRead(link: story.link)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop TTS when leaving the article
        if ArticleTextToSpeech.shared.currentArticleLink == story?.link {
            ArticleTextToSpeech.shared.stop()
        }
        
        // Update time spent reading this article
        if let story = story, let startTime = viewStartTime {
            let timeSpent = Date().timeIntervalSince(startTime)
            ReadingHistoryManager.shared.updateTimeSpent(
                link: story.link,
                additionalSeconds: timeSpent
            )
        }
        viewStartTime = nil
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
    
    // MARK: - Offline Cache
    
    /// Returns the appropriate offline icon based on cache state.
    private func offlineIcon() -> UIImage? {
        guard let story = story else {
            return UIImage(systemName: "arrow.down.circle")
        }
        let name = OfflineCacheManager.shared.isCached(story)
            ? "arrow.down.circle.fill"
            : "arrow.down.circle"
        return UIImage(systemName: name)
    }
    
    /// Updates the offline button icon to reflect current state.
    private func updateOfflineIcon() {
        offlineButton.image = offlineIcon()
    }
    
    /// Toggle offline cache state for the current story.
    @objc private func toggleOfflineCache() {
        guard let story = story else { return }
        
        let isNowCached = OfflineCacheManager.shared.toggleCache(story)
        updateOfflineIcon()
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        let message = isNowCached ? "Saved for offline reading ↓" : "Removed from offline cache"
        showToast(message)
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
        
        if Story.isSafeURL(story.link), let url = URL(string: story.link) {
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
        // Validate URL scheme before opening to prevent javascript: or custom
        // scheme injection from malicious RSS feed data.
        guard Story.isSafeURL(linkTarget),
              let url = URL(string: linkTarget) else {
            print("Blocked unsafe URL: \(linkTarget)")
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    // MARK: - Text-to-Speech
    
    /// Toggle TTS: start reading if idle, pause/resume if active.
    @objc private func toggleTTS() {
        let tts = ArticleTextToSpeech.shared
        
        if tts.isActive {
            // If reading this article, toggle pause/resume. If reading
            // a different article, stop that and start this one.
            if tts.currentArticleLink == story?.link {
                tts.togglePlayPause()
            } else if let story = story {
                tts.speak(story: story)
            }
        } else if let story = story {
            tts.speak(story: story)
            showToast("🔊 Reading aloud…")
        }
        
        updateTTSIcon()
    }
    
    /// Long-press on TTS button to stop.
    @objc private func stopTTS() {
        ArticleTextToSpeech.shared.stop()
        updateTTSIcon()
        showToast("Stopped reading")
    }
    
    /// Update the TTS button icon based on current state.
    private func updateTTSIcon() {
        let iconName: String
        switch ArticleTextToSpeech.shared.state {
        case .playing: iconName = "pause.circle.fill"
        case .paused:  iconName = "play.circle.fill"
        case .idle:    iconName = "speaker.wave.2"
        }
        ttsButton.image = UIImage(systemName: iconName)
    }
}

// MARK: - ArticleTextToSpeechDelegate

extension StoryViewController: ArticleTextToSpeechDelegate {
    func ttsDidChangeState(_ state: TTSState) {
        DispatchQueue.main.async { [weak self] in
            self?.updateTTSIcon()
        }
    }
    
    func ttsDidProgress(characterRange: NSRange, inFullText: String) {
        // Future: highlight the currently spoken text in descriptionLabel
    }
    
    func ttsDidFinish() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTTSIcon()
            self?.showToast("Finished reading")
        }
    }
    
    func ttsDidFail(error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.updateTTSIcon()
            self?.showToast("TTS error: \(error)")
        }
    }
}
