//
//  DataPersistenceTests.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/15/16.
//  Copyright © 2016 Apple Inc. All rights reserved.
//

import XCTest
import UIKit
@testable import FeedReader

class DataPersistenceTests: XCTestCase {
    
    var viewController : StoryTableViewController!
    
    override func setUp() {
        super.setUp()
        
        // Using this view controller to test data persistence after wrapping and unwrapping Story objects.s
        let storyboard = UIStoryboard(name: "Main", bundle: NSBundle.mainBundle())
        viewController = storyboard.instantiateViewControllerWithIdentifier("StoryTable") as! StoryTableViewController
        UIApplication.sharedApplication().keyWindow!.rootViewController = viewController
        
        let _ = viewController.view
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // Test to confirm that a Story object is wrapped and unwrapped correctly
    func testDataPersistenceOnOneStory() {
        
        var savedStories = [Story]()
        let aStory  = Story(title: "A Title", photo: nil, description: "A Description", link: "http://www.instaread.co")
        
        viewController.stories.append(aStory!)
        viewController.saveStories()
        
        savedStories = [Story]()
        savedStories = viewController.loadStories()!
        
        XCTAssertEqual(aStory?.title, savedStories[savedStories.count-1].title)
        XCTAssertEqual(aStory?.photo, savedStories[savedStories.count-1].photo)
        XCTAssertEqual(aStory?.body, savedStories[savedStories.count-1].body)
        XCTAssertEqual(aStory?.link, savedStories[savedStories.count-1].link)
    }

    // Test to confirm that multiple Story objects are wrapped and unwrapped correctly
    func testDataPersistenceOnMultipleStories() {
        
        var savedStories = [Story]()
        let aStory  = Story(title: "A Title", photo: nil, description: "A Description", link: "http://www.instaread.co")
        let aStory2  = Story(title: "A Title 2", photo: nil, description: "A Description 2", link: "https://angel.co/instaread")
        let aStory3  = Story(title: "A Title 3", photo: nil, description: "A Description 3", link: "https://angel.co/instaread/jobs")
        
        viewController.stories.append(aStory!)
        viewController.stories.append(aStory2!)
        viewController.stories.append(aStory3!)
        viewController.saveStories()
        
        savedStories = [Story]()
        savedStories = viewController.loadStories()!
        
        XCTAssertEqual(aStory?.title, savedStories[savedStories.count-3].title)
        XCTAssertEqual(aStory?.photo, savedStories[savedStories.count-3].photo)
        XCTAssertEqual(aStory?.body, savedStories[savedStories.count-3].body)
        XCTAssertEqual(aStory?.link, savedStories[savedStories.count-3].link)
        
        XCTAssertEqual(aStory2?.title, savedStories[savedStories.count-2].title)
        XCTAssertEqual(aStory2?.photo, savedStories[savedStories.count-2].photo)
        XCTAssertEqual(aStory2?.body, savedStories[savedStories.count-2].body)
        XCTAssertEqual(aStory2?.link, savedStories[savedStories.count-2].link)
        
        XCTAssertEqual(aStory3?.title, savedStories[savedStories.count-1].title)
        XCTAssertEqual(aStory3?.photo, savedStories[savedStories.count-1].photo)
        XCTAssertEqual(aStory3?.body, savedStories[savedStories.count-1].body)
        XCTAssertEqual(aStory3?.link, savedStories[savedStories.count-1].link)
    }
    
}
