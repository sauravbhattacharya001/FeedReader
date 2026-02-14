<p align="center">
  <img src="FeedReader/Assets.xcassets/AppIcon.appiconset/rss180.png" alt="FeedReader Logo" width="120" height="120">
</p>

<h1 align="center">FeedReader</h1>

<p align="center">
  <strong>A native iOS RSS feed reader with offline caching and image support</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS-blue?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/swift-3.0-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-8+-blue?logo=xcode" alt="Xcode">
  <img src="https://img.shields.io/github/languages/code-size/sauravbhattacharya001/FeedReader" alt="Code Size">
  <img src="https://img.shields.io/github/last-commit/sauravbhattacharya001/FeedReader" alt="Last Commit">
</p>

---

## Overview

FeedReader is a native iOS application that fetches and displays RSS news feeds with a clean table-view interface. It supports offline reading through persistent caching, handles network connectivity changes gracefully, and loads story thumbnails asynchronously with an in-memory cache for smooth scrolling.

Currently configured to read **BBC World News** RSS feeds, but can be pointed at any standard RSS/XML feed.

## Features

- 📰 **RSS Feed Parsing** — Native `XMLParser`-based RSS feed reader
- 💾 **Offline Caching** — Stories are persisted via `NSCoding` so they're available without internet
- 🌐 **Network Detection** — Uses `SCNetworkReachability` to detect connectivity and show appropriate UI
- 🖼️ **Async Image Loading** — Story thumbnails load asynchronously with `NSCache`-backed in-memory caching
- 📱 **Detail View** — Tap any story to see full description with link to original article
- 🔗 **External Links** — Open full articles in Safari from the detail view
- ♻️ **Smart Refresh** — Avoids redundant network fetches on back-navigation

## Architecture

```
FeedReader/
├── FeedReader/
│   ├── AppDelegate.swift                # App lifecycle
│   ├── Story.swift                      # Data model (NSCoding-conformant)
│   ├── StoryTableViewController.swift   # Main feed list + XML parsing
│   ├── StoryTableViewCell.swift         # Custom table view cell
│   ├── StoryViewController.swift        # Story detail view
│   ├── NoInternetFoundViewController.swift  # Offline fallback UI
│   ├── Reachability.swift               # Network connectivity checker
│   ├── Assets.xcassets/                 # App icons and images
│   └── Base.lproj/
│       ├── Main.storyboard              # Main UI layout
│       └── LaunchScreen.storyboard      # Launch screen
├── FeedReader.xcodeproj/                # Xcode project
└── FeedReaderTests/
    ├── StoryTests.swift                 # Model unit tests
    ├── ViewControllerTests.swift        # View controller tests
    ├── storiesTest.xml                  # Test fixture XML
    └── storiesTest.plist                # Test fixture plist
```

## How It Works

1. **Launch** — App checks network connectivity via `Reachability`
2. **Online** — Fetches RSS feed asynchronously from BBC News, parses XML with `XMLParser`
3. **Offline** — Loads previously cached stories from disk via `NSKeyedUnarchiver`
4. **No Data** — Shows a friendly "no internet" screen with retry button
5. **Browsing** — Stories displayed in a `UITableView` with title, description, and thumbnail
6. **Detail** — Tapping a story shows full description with a link to the original article

## Getting Started

### Prerequisites

- **Xcode 8+** (Swift 3)
- **iOS 10+** deployment target
- macOS with Xcode installed

### Installation

```bash
# Clone the repository
git clone https://github.com/sauravbhattacharya001/FeedReader.git

# Open in Xcode
cd FeedReader
open FeedReader.xcodeproj
```

### Running the App

1. Open `FeedReader.xcodeproj` in Xcode
2. Select an iPhone simulator (iPhone 5S or later)
3. Press `⌘R` to build and run

### Running Tests

1. Open `FeedReader.xcodeproj` in Xcode
2. Press `⌘U` to run all tests, or:
3. Open the **Test Navigator** (⌘6) and run individual test suites

## Test Cases

| Scenario | Expected Behavior |
|---|---|
| Launch with internet | Fetches and displays latest BBC World News feed |
| Launch without internet (first run) | Shows "No Internet" screen with retry button |
| Launch without internet (cached data) | Displays previously cached stories |
| Lose connection while using app | Continues using cached data |
| Tap a story | Shows detail view with title, description, and link |
| Tap "Open Link" in detail view | Opens full article in Safari |
| Retry button (connection restored) | Dismisses offline screen, loads feed |

## Tech Stack

| Component | Technology |
|---|---|
| **Language** | Swift 3 |
| **UI Framework** | UIKit (Storyboard-based) |
| **RSS Parsing** | Foundation `XMLParser` |
| **Networking** | `URLSession` (async) |
| **Persistence** | `NSCoding` + `NSKeyedArchiver` |
| **Image Caching** | `NSCache` |
| **Network Detection** | `SystemConfiguration` / `SCNetworkReachability` |

## Customizing the Feed Source

To point FeedReader at a different RSS feed, edit the URL in `StoryTableViewController.swift`:

```swift
// In loadData(), change the feed URL:
beginParsing("https://feeds.bbci.co.uk/news/world/rss.xml")
// Replace with any RSS 2.0 feed URL, e.g.:
// beginParsing("https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml")
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

This project is available for use under the terms specified by the repository owner. See the repository for details.

---

<p align="center">
  Built with ❤️ by <a href="https://github.com/sauravbhattacharya001">Saurav Bhattacharya</a>
</p>
