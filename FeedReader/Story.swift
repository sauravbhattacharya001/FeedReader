//
//  Story.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class Story: NSObject, NSCoding {
    
    // MARK: - Properties
    
    var title: String
    var photo: UIImage?
    var body: String
    var link: String
    
    // MARK: - Archiving Paths
    
    static var DocumentsDirectory = NSFileManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
    static var ArchiveURL = DocumentsDirectory.URLByAppendingPathComponent("stories")

    
    // MARK: - Types
    
    struct PropertyKey {
        static let titleKey = "title"
        static let photoKey = "photo"
        static let descriptionKey = "description"
        static let linkKey = "link"
    }
    
    // MARK: - Initialization
    
    init?(title: String, photo: UIImage?, description: String, link: String) {
        
        // Initialize stored properties.
        self.title = title
        self.photo = photo
        self.body = description
        self.link = link
        
        super.init()
        
        // Initialization should fail if there is no name or if the rating is negative.
        if title.isEmpty || body.isEmpty || !isValidLink(link){
            return nil
        }
    }
    
    func isValidLink(urlString: String?) -> Bool {
        //Check for nil
        if let urlString = urlString {
            // create NSURL instance
            if let url = NSURL(string: urlString) {
                // check if your application can open the NSURL instance
                return UIApplication.sharedApplication().canOpenURL(url)
            }
        }
        return false
    }
    
    // MARK: - NSCoding
    
    func encodeWithCoder(aCoder: NSCoder) {
        
        aCoder.encodeObject(title, forKey: PropertyKey.titleKey)
        aCoder.encodeObject(photo, forKey: PropertyKey.photoKey)
        aCoder.encodeObject(body, forKey: PropertyKey.descriptionKey)
        aCoder.encodeObject(link, forKey: PropertyKey.linkKey)
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        
        let title = aDecoder.decodeObjectForKey(PropertyKey.titleKey) as! String
        
        // Because photo is an optional property of Meal, use conditional cast.
        let photo = aDecoder.decodeObjectForKey(PropertyKey.photoKey) as? UIImage
        
        let description = aDecoder.decodeObjectForKey(PropertyKey.descriptionKey) as! String
        
        let link = aDecoder.decodeObjectForKey(PropertyKey.linkKey) as! String
        
        // Must call designated initializer.
        self.init(title: title, photo: photo, description: description, link: link)
    }
}




