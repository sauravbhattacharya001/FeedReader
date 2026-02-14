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
    
    var activityIndicator = UIActivityIndicatorView()

    // MARK: - ViewController methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up loading indicator
        activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        activityIndicator.center = view.center
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }
    
    func loadData() {
        if Reachability.isConnectedToNetwork() == true {
            // Parse the data from RSS Feed asynchronously to avoid blocking the UI.
            beginParsing("https://feeds.reuters.com/reuters/MostRead?format=xml")
            
        } else if let savedStories = loadStories() {
            // Load data from saved state.
            stories = savedStories
            self.tableView.reloadData()
        } else {
            // Show no internet connection image.
            if let resultController = storyboard!.instantiateViewController(withIdentifier: "NoInternetFound") as? NoInternetFoundViewController {
                present(resultController, animated: true, completion: nil)
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveStories()
    }
    
    // MARK: - RSS Feed Parser
    
    func beginParsing(_ url: String)
    {
        stories = []
        guard let feedURL = URL(string: url) else {
            print("Failed to create URL from string: \(url)")
            return
        }
        
        // Show loading indicator while fetching data
        activityIndicator.startAnimating()
        
        // Fetch RSS data asynchronously to avoid blocking the main thread (fixes #4)
        let task = URLSession.shared.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            guard let data = data, error == nil else {
                print("Failed to fetch RSS feed: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                }
                return
            }
            
            // Parse XML on background thread
            self.parser = XMLParser(data: data)
            self.parser.delegate = self
            self.parser.parse()
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                self.tableView.reloadData()
            }
        }
        task.resume()
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
            let trimmedImagePath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if let aStory = Story(title: storyTitle as String, photo: UIImage(named: "sample")!, description: storyDescription.components(separatedBy: "<div")[0], link: link.components(separatedBy: "\n")[0], imagePath: trimmedImagePath.isEmpty ? nil : trimmedImagePath) {
                stories.append(aStory)
            }
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
        
        // Load thumbnail asynchronously to avoid blocking the main thread.
        // Synchronous Data(contentsOf:) on the main thread causes UI freezes
        // and choppy scrolling, especially on slow networks.
        cell.photoImage.image = UIImage(named: "sample") // placeholder while loading
        if let imagePathString = stories[(indexPath as NSIndexPath).row].imagePath,
           let url = URL(string: imagePathString) {
            let currentIndexPath = indexPath
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    // Only update if the cell is still showing the same row
                    // (guards against cell reuse during fast scrolling)
                    if let visibleCell = self?.tableView.cellForRow(at: currentIndexPath) as? StoryTableViewCell {
                        visibleCell.photoImage.image = image
                    }
                }
            }.resume()
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
