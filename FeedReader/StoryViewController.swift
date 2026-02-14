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
    
    // MARK: - ViewController methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        if let story = story {
            titleLabel.text   = story.title
            photoImage.image = story.photo
            descriptionLabel.text = story.body
            linkTarget = story.link
        }
        
        // Add share button to navigation bar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareStory)
        )
    }
    
    // MARK: - Actions
    
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
            popover.barButtonItem = navigationItem.rightBarButtonItem
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

