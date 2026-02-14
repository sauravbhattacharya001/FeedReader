//
//  StoryTableViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class StoryTableViewController: UITableViewController, XMLParserDelegate {
    
    // MARK: - Properties
    
    var stories = [Story]()
    var parser = XMLParser()
    
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
    
    override func viewWillAppear(_ animated: Bool) {
        loadData()
    }
    
    func loadData() {
        if Reachability.isConnectedToNetwork() == true {
            // Parse the data from RSS Feed.
            beginParsing("https://feeds.reuters.com/reuters/MostRead?format=xml")
            
        } else if let savedStories = loadStories() {
            // Load data from saved state.
            stories = savedStories
        } else {
            // Show no internet connection image.
            if let resultController = storyboard!.instantiateViewController(withIdentifier: "NoInternetFound") as? NoInternetFoundViewController {
                present(resultController, animated: true, completion: nil)
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        saveStories()
    }
    
    // MARK: - RSS Feed Parser
    
    func beginParsing(_ url: String)
    {
        stories = []
        guard let feedURL = URL(string: url),
              let xmlParser = XMLParser(contentsOf: feedURL) else {
            print("Failed to create XML parser for URL: \(url)")
            return
        }
        parser = xmlParser
        parser.delegate = self
        parser.parse()
        self.tableView.reloadData()
    }
    
    func beginParsingTest(_ url: String)
    {
        stories = []
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: url)) else {
            print("Failed to load test data from path: \(url)")
            return
        }
        parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        self.tableView.reloadData()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String])
    {
        element = elementName as NSString
        if (elementName as NSString).isEqual(to: "item")
        {
            elements = NSMutableDictionary()
            elements = [:]
            
            storyTitle = NSMutableString()
            storyDescription = NSMutableString()
            link = NSMutableString()
            imagePath = NSMutableString()
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String)
    {
        if element.isEqual(to: "title") {
            storyTitle.append(string)
        } else if element.isEqual(to: "description") {
            storyDescription.append(string)
        } else if element.isEqual(to: "guid"){
            link.append(string)
        } else if element.isEqual(to: "image") {
            imagePath.append(string)
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?)
    {
        if (elementName as NSString).isEqual(to: "guid") {            
            let aStory = Story(title: storyTitle as String, photo: UIImage(named: "sample")!, description: storyDescription.components(separatedBy: "<div")[0], link: link.components(separatedBy: "\n")[0])
            stories.append(aStory!)
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return stories.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        // Table view cells are reused and should be dequeued using a cell identifier.
        let cellIndentifier = "StoryTableViewCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIndentifier, for: indexPath) as! StoryTableViewCell
        
        cell.titleLabel.text = stories[(indexPath as NSIndexPath).row].title
        cell.descriptionLabel.text = stories[(indexPath as NSIndexPath).row].body
        
        // Use the story's imagePath if available, otherwise fall back to placeholder
        let imagePathString = stories[(indexPath as NSIndexPath).row].photo != nil ? "" : ""
        if !imagePathString.isEmpty,
           let url = URL(string: imagePathString),
           let data = try? Data(contentsOf: url) {
            cell.photoImage.image = UIImage(data: data)
        } else {
            cell.photoImage.image = UIImage(named: "sample")
        }
        
        return cell
    }
    
    // MARK: - Navigation

    // Prepare segue for showing one story detail view.
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowDetail" {
            let storyDetailViewController = segue.destination as! StoryViewController
            
            // Get the cell that generated this segue.
            if let selectedStoryCell = sender as? StoryTableViewCell {
                let indexPath = tableView.indexPath(for: selectedStoryCell)!
                let selectedStory = stories[(indexPath as NSIndexPath).row]
                storyDetailViewController.story = selectedStory as Story
            }
        }
    }
    
    // MARK: - NSCoding
    
    func saveStories() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: stories, requiringSecureCoding: false)
            try data.write(to: Story.ArchiveURL)
        } catch {
            print("Failed to save stories: \(error)")
        }
    }
    
    func loadStories() -> [Story]? {
        print(Story.ArchiveURL.path)
        guard let data = try? Data(contentsOf: Story.ArchiveURL) else {
            return nil
        }
        return (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, Story.self], from: data)) as? [Story]
    }
}
