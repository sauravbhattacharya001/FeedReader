//
//  PersonalFeedPublisher.swift
//  FeedReader
//
//  Generates a valid RSS 2.0 XML feed from the user's bookmarked articles.
//  Users can export their curated reading list as a subscribable RSS feed,
//  share it with friends, or import it into other RSS readers.
//

import Foundation

/// Generates RSS 2.0 XML from bookmarked or selected articles.
class PersonalFeedPublisher {
    
    // MARK: - Configuration
    
    struct FeedConfig {
        var title: String
        var description: String
        var link: String
        var language: String
        var authorName: String
        var maxItems: Int
        
        static var `default`: FeedConfig {
            return FeedConfig(
                title: "My Curated Feed",
                description: "Articles curated with FeedReader",
                link: "https://feedreader.app/curated",
                language: "en-us",
                authorName: "FeedReader User",
                maxItems: 50
            )
        }
    }
    
    // MARK: - Properties
    
    private let config: FeedConfig
    
    // MARK: - Initialization
    
    init(config: FeedConfig = .default) {
        self.config = config
    }
    
    // MARK: - Feed Generation
    
    /// Generate RSS 2.0 XML string from an array of stories.
    func generateRSS(from stories: [Story]) -> String {
        let items = Array(stories.prefix(config.maxItems))
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n"
        xml += "  <channel>\n"
        xml += "    <title>\(escapeXML(config.title))</title>\n"
        xml += "    <link>\(escapeXML(config.link))</link>\n"
        xml += "    <description>\(escapeXML(config.description))</description>\n"
        xml += "    <language>\(escapeXML(config.language))</language>\n"
        xml += "    <managingEditor>\(escapeXML(config.authorName))</managingEditor>\n"
        xml += "    <generator>FeedReader Personal Publisher</generator>\n"
        xml += "    <lastBuildDate>\(rfc822Date(Date()))</lastBuildDate>\n"
        
        for story in items {
            xml += generateItem(from: story)
        }
        
        xml += "  </channel>\n"
        xml += "</rss>\n"
        return xml
    }
    
    /// Generate an OPML outline list from stories (for import into other readers).
    func generateOPML(from stories: [Story]) -> String {
        let items = Array(stories.prefix(config.maxItems))
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<opml version=\"2.0\">\n"
        xml += "  <head>\n"
        xml += "    <title>\(escapeXML(config.title))</title>\n"
        xml += "    <dateCreated>\(rfc822Date(Date()))</dateCreated>\n"
        xml += "    <ownerName>\(escapeXML(config.authorName))</ownerName>\n"
        xml += "  </head>\n"
        xml += "  <body>\n"
        
        for story in items {
            xml += "    <outline text=\"\(escapeXMLAttribute(story.title))\" "
            xml += "type=\"link\" "
            xml += "url=\"\(escapeXMLAttribute(story.link))\" />\n"
        }
        
        xml += "  </body>\n"
        xml += "</opml>\n"
        return xml
    }
    
    /// Export feed to a file URL in the documents directory.
    func exportToFile(stories: [Story], filename: String = "my-curated-feed.xml", format: ExportFormat = .rss) -> URL? {
        let content: String
        let ext: String
        switch format {
        case .rss:
            content = generateRSS(from: stories)
            ext = "xml"
        case .opml:
            content = generateOPML(from: stories)
            ext = "opml"
        case .json:
            content = generateJSONFeed(from: stories)
            ext = "json"
        }
        
        let finalFilename = filename.hasSuffix(".\(ext)") ? filename : "\(filename).\(ext)"
        
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsDir.appendingPathComponent(finalFilename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
    
    /// Generate JSON Feed 1.1 format (https://jsonfeed.org).
    func generateJSONFeed(from stories: [Story]) -> String {
        let items = Array(stories.prefix(config.maxItems))
        var feed: [String: Any] = [
            "version": "https://jsonfeed.org/version/1.1",
            "title": config.title,
            "description": config.description,
            "home_page_url": config.link,
            "language": config.language
        ]
        
        var jsonItems: [[String: Any]] = []
        for story in items {
            var item: [String: Any] = [
                "id": story.link,
                "title": story.title,
                "url": story.link,
                "content_text": story.body
            ]
            if let source = story.sourceFeedName {
                item["tags"] = [source]
            }
            jsonItems.append(item)
        }
        feed["items"] = jsonItems
        
        guard let data = try? JSONSerialization.data(withJSONObject: feed, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }
    
    /// Generate a summary of what would be published.
    func preview(stories: [Story]) -> FeedPreview {
        let items = Array(stories.prefix(config.maxItems))
        let sources = Set(items.compactMap { $0.sourceFeedName })
        return FeedPreview(
            title: config.title,
            articleCount: items.count,
            sourceFeedCount: sources.count,
            sources: Array(sources).sorted(),
            estimatedSizeBytes: generateRSS(from: items).utf8.count
        )
    }
    
    // MARK: - Types
    
    enum ExportFormat {
        case rss
        case opml
        case json
    }
    
    struct FeedPreview {
        let title: String
        let articleCount: Int
        let sourceFeedCount: Int
        let sources: [String]
        let estimatedSizeBytes: Int
        
        var estimatedSizeKB: Double {
            return Double(estimatedSizeBytes) / 1024.0
        }
    }
    
    // MARK: - Private Helpers
    
    private func generateItem(from story: Story) -> String {
        var xml = "    <item>\n"
        xml += "      <title>\(escapeXML(story.title))</title>\n"
        xml += "      <link>\(escapeXML(story.link))</link>\n"
        xml += "      <guid isPermaLink=\"true\">\(escapeXML(story.link))</guid>\n"
        
        if !story.body.isEmpty {
            let snippet = String(story.body.prefix(500))
            xml += "      <description>\(escapeXML(snippet))</description>\n"
        }
        
        if let source = story.sourceFeedName {
            xml += "      <category>\(escapeXML(source))</category>\n"
        }
        
        xml += "    </item>\n"
        return xml
    }
    
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func escapeXMLAttribute(_ string: String) -> String {
        return escapeXML(string)
    }
    
    private func rfc822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
