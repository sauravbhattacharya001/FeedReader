//
//  SearchFilterTests.swift
//  FeedReaderTests
//
//  Tests for the search/filter functionality in StoryTableViewController.
//

import XCTest
import UIKit
@testable import FeedReader

class SearchFilterTests: XCTestCase {
    
    var viewController: StoryTableViewController!
    
    override func setUp() {
        super.setUp()
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        viewController = storyboard.instantiateViewController(withIdentifier: "StoryTable") as! StoryTableViewController
        UIApplication.shared.keyWindow?.rootViewController = viewController
        let _ = viewController.view
        
        // Populate with test stories
        viewController.stories = [
            Story(title: "Apple launches new iPhone", photo: nil, description: "Tech giant reveals latest smartphone", link: "http://example.com/1")!,
            Story(title: "Climate change summit begins", photo: nil, description: "World leaders gather to discuss environment", link: "http://example.com/2")!,
            Story(title: "Stock market reaches record high", photo: nil, description: "Wall Street celebrates gains in tech sector", link: "http://example.com/3")!,
            Story(title: "New AI breakthrough announced", photo: nil, description: "Researchers develop novel machine learning approach", link: "http://example.com/4")!,
            Story(title: "Sports: Championship results", photo: nil, description: "Final scores from the weekend games", link: "http://example.com/5")!,
        ]
    }
    
    override func tearDown() {
        viewController = nil
        super.tearDown()
    }
    
    // MARK: - Search Controller Setup
    
    func testSearchControllerIsConfigured() {
        XCTAssertNotNil(viewController.navigationItem.searchController,
                        "Search controller should be set on navigation item")
    }
    
    func testSearchBarPlaceholder() {
        let searchBar = viewController.navigationItem.searchController?.searchBar
        XCTAssertEqual(searchBar?.placeholder, "Search stories...",
                       "Search bar should have the correct placeholder text")
    }
    
    // MARK: - Refresh Control Setup
    
    func testRefreshControlIsConfigured() {
        XCTAssertNotNil(viewController.refreshControl,
                        "Refresh control should be set for pull-to-refresh")
    }
    
    func testRefreshControlTitle() {
        let title = viewController.refreshControl?.attributedTitle?.string
        XCTAssertEqual(title, "Pull to refresh feed",
                       "Refresh control should display the correct title")
    }
    
    // MARK: - Table View Row Count
    
    func testRowCountWithoutSearch() {
        // When no search is active, all stories should be displayed
        let rowCount = viewController.tableView(viewController.tableView, numberOfRowsInSection: 0)
        XCTAssertEqual(rowCount, 5, "Should show all 5 stories when not searching")
    }
    
    // MARK: - Navigation Title
    
    func testNavigationTitleUpdated() {
        // The storyboard title should be "FeedReader" not "Reuters"
        XCTAssertEqual(viewController.navigationItem.title, "FeedReader",
                       "Navigation title should be FeedReader")
    }
}
