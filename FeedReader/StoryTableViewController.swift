//
//  StoryTableViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class StoryTableViewController: UITableViewController, NSXMLParserDelegate {
    
    // MARK: - Properties
    
    var stories = [Story]()
    var parser = NSXMLParser()
    
    var elements = NSMutableDictionary()
    var element = NSString()
    
    var storyTitle = NSMutableString()
    var storyDescription = NSMutableString()
    var link = NSMutableString()
    var imagePath = NSMutableString()

    // MARK: - ViewController methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(animated: Bool) {
        loadData()
    }
    
    func loadData() {
        if Reachability.isConnectedToNetwork() == true {
            // Parse the data from RSS Feed.
            beginParsing("http://feeds.reuters.com/reuters/MostRead?format=xml")
            
        } else if let savedStories = loadStories() {
            // Load data from saved state.
            stories = savedStories
        } else {
            // Show no internet connection image.
            if let resultController = storyboard!.instantiateViewControllerWithIdentifier("NoInternetFound") as? NoInternetFoundViewController {
                presentViewController(resultController, animated: true, completion: nil)
            }
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        saveStories()
    }
    
    // MARK: - RSS Feed Parser
    
    func beginParsing(url: String)
    {
        stories = []
        parser = NSXMLParser(contentsOfURL:(NSURL(string: url))!)!
        parser.delegate = self
        parser.parse()
        self.tableView.reloadData()
    }
    
    func parser(parser: NSXMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String])
    {
        element = elementName
        if (elementName as NSString).isEqualToString("item")
        {
            elements = NSMutableDictionary()
            elements = [:]
            
            storyTitle = NSMutableString()
            storyDescription = NSMutableString()
            link = NSMutableString()
            imagePath = NSMutableString()
        }
    }
    
    func parser(parser: NSXMLParser, foundCharacters string: String)
    {
        if element.isEqualToString("title") {
            storyTitle.appendString(string)
        } else if element.isEqualToString("description") {
            storyDescription.appendString(string)
        } else if element.isEqualToString("guid"){
            link.appendString(string)
        } else if element.isEqualToString("image") {
            imagePath.appendString(string)
        }
    }
    
    func parser(parser: NSXMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?)
    {
        if (elementName as NSString).isEqualToString("guid") {            
            let aStory = Story(title: storyTitle as String, photo: UIImage(named: "sample")!, description: storyDescription.componentsSeparatedByString("<div")[0], link: link.componentsSeparatedByString("\n")[0])
            stories.append(aStory!)
        }
    }

    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return stories.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        // Table view cells are reused and should be dequeued using a cell identifier.
        let cellIndentifier = "StoryTableViewCell"
        let cell = tableView.dequeueReusableCellWithIdentifier(cellIndentifier, forIndexPath: indexPath) as! StoryTableViewCell
        
        cell.titleLabel.text = stories[indexPath.row].title
        cell.descriptionLabel.text = stories[indexPath.row].body
        
        let tmp = ""
        if !(tmp.isEmpty) {
            let url = NSURL(string: tmp as String)!
            let data = NSData(contentsOfURL: url)!
            cell.photoImage.image = UIImage(data: data)
        } else {
            cell.photoImage.image = UIImage(named: "sample")
        }
        
        return cell
    }
    
    // MARK: - Navigation

    // Prepare segue for showing one story detail view.
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "ShowDetail" {
            let storyDetailViewController = segue.destinationViewController as! StoryViewController
            
            // Get the cell that generated this segue.
            if let selectedStoryCell = sender as? StoryTableViewCell {
                let indexPath = tableView.indexPathForCell(selectedStoryCell)!
                let selectedStory = stories[indexPath.row]
                storyDetailViewController.story = selectedStory as Story
            }
        }
    }
    
    // MARK: - NSCoding
    
    func saveStories() {
        let isSuccessfulSave = NSKeyedArchiver.archiveRootObject(stories, toFile: Story.ArchiveURL.path!)
        
        if !isSuccessfulSave {
            print("Failed to save stories...")
        }
    }
    
    func loadStories() -> [Story]? {
        print(Story.ArchiveURL.path!)
        return NSKeyedUnarchiver.unarchiveObjectWithFile(Story.ArchiveURL.path!) as? [Story]
    }
}
