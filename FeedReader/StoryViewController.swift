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
    }
    
    // MARK: - Actions
    
    // Called when open link is clicked.
    @IBAction func clickedLink(sender: AnyObject) {
        UIApplication.sharedApplication().openURL(NSURL(string: linkTarget)!)
    }
}

