//
//  ModelTests.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/15/16.
//  Copyright © 2016 Apple Inc. All rights reserved.
//

import XCTest
@testable import FeedReader

class StoryTests: XCTestCase {
    
    // Test to confirm that a Story object is initialized with correct data.
    func testStoryInitCorrect() {
        // Success case.
        let potentialItem = Story(title: "A Title", photo: nil, description: "A Description", link: "http://www.instaread.co")
        XCTAssertNotNil(potentialItem)
    }
    
    // Test to confirm that a Story object is not initialized with incorrect data.
    func testStoryInitIncorrect() {
        // Failure cases.
        let noName = Story(title: "", photo: nil, description: "A Description", link: "http://www.instaread.co")
        XCTAssertNil(noName, "Empty name is invalid")
        
        let noDescription = Story(title: "A Title", photo: nil, description: "", link: "http://www.instaread.co")
        XCTAssertNil(noDescription)
        
        let noLink = Story(title:"A Title", photo: nil, description: "A Description", link: "")
        XCTAssertNil(noLink)
        
        let invalidLink = Story(title:"A Title", photo: nil, description: "A Description", link: "abcd")
        XCTAssertNil(invalidLink)
    }
}
