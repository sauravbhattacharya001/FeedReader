//
//  StoryTableViewCell.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class StoryTableViewCell: UITableViewCell {
    
    // MARK: - Properties
    
    // One story cell in the table view.    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var photoImage: UIImageView!
    
    /// Blue dot indicator for unread stories.
    private let unreadDot: UIView = {
        let dot = UIView()
        dot.backgroundColor = .systemBlue
        dot.layer.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        return dot
    }()
    
    /// Whether the unread dot has been added to the view hierarchy.
    private var unreadDotAdded = false
    
    // MARK: - Configuration
    
    /// Configure the cell's read/unread visual state.
    /// - Parameter isRead: Whether the story has been read.
    func configureReadStatus(isRead: Bool) {
        // Add unread dot if not yet added
        if !unreadDotAdded {
            contentView.addSubview(unreadDot)
            NSLayoutConstraint.activate([
                unreadDot.widthAnchor.constraint(equalToConstant: 10),
                unreadDot.heightAnchor.constraint(equalToConstant: 10),
                unreadDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
                unreadDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
            unreadDotAdded = true
        }
        
        // Show/hide the unread dot
        unreadDot.isHidden = isRead
        
        // Dim read stories slightly
        titleLabel?.alpha = isRead ? 0.6 : 1.0
        descriptionLabel?.alpha = isRead ? 0.5 : 0.8
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        unreadDot.isHidden = true
        titleLabel?.alpha = 1.0
        descriptionLabel?.alpha = 0.8
    }
}
