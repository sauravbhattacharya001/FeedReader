<p align="center">
  <img src="FeedReader/Assets.xcassets/AppIcon.appiconset/rss180.png" alt="FeedReader Logo" width="120" height="120">
</p>

<h1 align="center">FeedReader</h1>

<p align="center">
  <strong>A native iOS RSS feed reader with offline caching and image support</strong>
</p>

<p align="center">
  <!-- CI / Quality -->
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/ci.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/codeql.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/pages.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/pages.yml/badge.svg" alt="Pages"></a>
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/docker.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/docker.yml/badge.svg" alt="Docker"></a>
  <img src="https://img.shields.io/badge/tests-1941-brightgreen?logo=swift" alt="Tests">
  <img src="https://img.shields.io/badge/coverage-enabled-brightgreen?logo=swift" alt="Code Coverage">
  <br>
  <!-- Platform / Language -->
  <img src="https://img.shields.io/badge/platform-iOS-blue?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/swift-3.0-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-8+-blue?logo=xcode" alt="Xcode">
  <br>
  <!-- Repo metadata -->
  <a href="https://github.com/sauravbhattacharya001/FeedReader/releases/latest"><img src="https://img.shields.io/github/v/release/sauravbhattacharya001/FeedReader?include_prereleases&sort=semver" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/sauravbhattacharya001/FeedReader" alt="License"></a>
  <img src="https://img.shields.io/github/languages/code-size/sauravbhattacharya001/FeedReader" alt="Code Size">
  <img src="https://img.shields.io/github/last-commit/sauravbhattacharya001/FeedReader" alt="Last Commit">
  <img src="https://img.shields.io/github/commit-activity/m/sauravbhattacharya001/FeedReader" alt="Commit Activity">
  <br>
  <!-- Community -->
  <img src="https://img.shields.io/github/issues/sauravbhattacharya001/FeedReader" alt="Open Issues">
  <img src="https://img.shields.io/github/issues-pr/sauravbhattacharya001/FeedReader" alt="Open PRs">
  <img src="https://img.shields.io/github/stars/sauravbhattacharya001/FeedReader?style=social" alt="Stars">
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
- 🔖 **Bookmarks** — Save stories for later reading with persistent storage, swipe-to-bookmark, and a dedicated bookmarks screen
- 📡 **Multi-Feed Support** — Add, remove, and toggle multiple RSS feed sources. 10 built-in presets (BBC, NPR, TechCrunch, Ars Technica, Hacker News, The Verge, etc.) plus custom URL support
- 🔍 **Search & Filter** — Real-time search across story titles and descriptions
- 📤 **Share** — Share stories via the system share sheet
- 👁️ **Read/Unread Tracking** — Stories are automatically marked as read when tapped, with blue dot indicators for unread stories, unread count in the title bar, segmented filter (All/Unread/Read), mark all read, and swipe-left to toggle read status
- 📊 **Reading Statistics** — Analytics dashboard showing reading habits: total stories read, daily/weekly/monthly counts, daily average, reading streaks (current + longest) with motivational messages, hourly activity bar chart, per-feed breakdown with progress bars, bookmark count, and tracking history
- 📝 **Article Notes** — Add, edit, and delete personal notes on any article. Notes persist across sessions and support timestamped annotations
- 🎯 **Content Filters** — Create keyword-based content filters to highlight or hide stories. Supports import/export as JSON for backup and sharing
- ❤️ **Feed Health Monitor** — Tracks feed reliability metrics: fetch success/failure history, response times, uptime percentage, and generates health reports with per-feed status
- 📶 **Offline Article Cache** — Dedicated offline cache for saving full articles. Browse cached articles without internet, manage cache size, and receive notifications when cache changes
- 📂 **OPML Import/Export** — Import and export feed subscriptions in standard OPML format for interoperability with other RSS readers
- 📜 **Reading History** — Rich reading history with timestamped entries, source tracking, session duration, and history summaries with date-range filtering
- 🧠 **Smart Feeds** — Create saved keyword-based filters that auto-match stories across all feeds. Supports AND/OR match modes and search across title, description, or both
- 🔒 **Security Hardening** — RSS parser security: XXE prevention, URL validation (blocks javascript:/data:/file: schemes), HTML sanitization, and protocol enforcement
- 📓 **Reading Journal** — Auto-generated daily reading journal combining articles read, highlights, and notes into rich entries. Features reflection prompts, mood tagging, journaling streaks, weekly/monthly digests, full-text search across entries, and Markdown/JSON export
- 📚 **Vocabulary Builder** — Automatically extracts uncommon words from articles you read, building a personal vocabulary list. Features mastery levels (New → Learning → Familiar → Mastered) with spaced review scheduling, context sentences from source articles, filtering by feed/mastery/date, search, and JSON/CSV export/import

## Architecture

```
FeedReader/
├── FeedReader/
│   ├── AppDelegate.swift                # App lifecycle
│   ├── Story.swift                      # Data model (NSCoding-conformant)
│   ├── Feed.swift                       # RSS feed source model (name, URL, enabled)
│   ├── ArticleNote.swift                # Article note data model
│   ├── ContentFilter.swift              # Content filter data model (keyword, action)
│   ├── FeedManager.swift                # Feed source management singleton (CRUD + persistence)
│   ├── FeedListViewController.swift     # Feed manager UI (add/remove/toggle/reorder feeds)
│   ├── FeedHealthManager.swift          # Feed reliability tracking (uptime, response times, reports)
│   ├── FeedPerformanceAnalyzer.swift    # Feed performance profiling (parse times, sizes, bottlenecks)
│   ├── FeedUpdateScheduler.swift        # Scheduled feed refresh management
│   ├── FeedBundleManager.swift          # Bundled feed collections (curated topic packs)
│   ├── FeedMergeManager.swift           # Multi-feed story merging and conflict resolution
│   ├── FeedCategoryManager.swift        # Feed categorization and grouping
│   ├── FeedDiscoveryManager.swift       # Auto-discover RSS feeds from website URLs
│   ├── FeedAutomationEngine.swift       # Rule-based feed automation (auto-bookmark, auto-tag, etc.)
│   ├── BookmarkManager.swift            # Bookmark persistence & management (singleton)
│   ├── ReadStatusManager.swift          # Read/unread status tracking (UserDefaults, singleton)
│   ├── ReadingStatsManager.swift        # Reading analytics engine (events, streaks, stats)
│   ├── ReadingHistoryManager.swift      # Rich reading history with timestamps and sessions
│   ├── ReadingSessionTracker.swift      # Per-session reading time tracking
│   ├── ReadingStreakTracker.swift        # Reading streak calculation and persistence
│   ├── ReadingGoalsManager.swift        # Configurable reading goals and progress tracking
│   ├── ReadingAchievementsManager.swift # Gamification achievements for reading milestones
│   ├── ReadingQueueManager.swift        # Read-later queue with priority ordering
│   ├── ReadingJournalManager.swift      # Auto-generated daily reading journal with Markdown export
│   ├── ReadingStatsViewController.swift # Reading stats dashboard UI
│   ├── ArticleNotesManager.swift        # Article note CRUD and persistence
│   ├── ArticleHighlight.swift           # Article highlight data model
│   ├── ArticleHighlightsManager.swift   # Text highlighting and annotation
│   ├── ArticleTagManager.swift          # Article tagging and organization
│   ├── ArticleSummarizer.swift          # Auto-generate article summaries
│   ├── ArticleSimilarityManager.swift   # Find similar articles across feeds
│   ├── ArticleSentimentAnalyzer.swift   # Sentiment analysis for article content
│   ├── ArticleReadabilityAnalyzer.swift # Readability scoring (Flesch-Kincaid, etc.)
│   ├── ArticleTrendDetector.swift       # Detect trending topics across feeds
│   ├── ArticleVersionTracker.swift      # Track article content changes over time
│   ├── ArticleCitationGenerator.swift   # Generate citations in various formats
│   ├── ArticleDeduplicator.swift        # Cross-feed duplicate article detection
│   ├── ArticleRecommendationEngine.swift # Personalized article recommendations
│   ├── ContentFilterManager.swift       # Content filter management with JSON import/export
│   ├── SmartFeedManager.swift           # Keyword-based auto-matching smart feeds
│   ├── KeywordAlert.swift               # Keyword alert data model
│   ├── KeywordAlertManager.swift        # Alert notifications for keyword matches
│   ├── DigestGenerator.swift            # Generate periodic digest summaries
│   ├── TextAnalyzer.swift               # Text analysis utilities (word count, reading time)
│   ├── URLValidator.swift               # URL validation and sanitization
│   ├── ShareManager.swift               # Sharing utilities (system share sheet)
│   ├── OPMLManager.swift                # OPML import/export for feed subscriptions
│   ├── OfflineCacheManager.swift        # Full-article offline caching with size management
│   ├── OfflineArticlesViewController.swift  # Offline cached articles browsing UI
│   ├── ImageCache.swift                 # NSCache-based in-memory image cache
│   ├── RSSFeedParser.swift              # Concurrent multi-feed RSS parser with deduplication
│   ├── BookmarksViewController.swift    # Saved stories screen with swipe-to-delete
│   ├── StoryTableViewController.swift   # Main feed list + XML parsing
│   ├── StoryTableViewCell.swift         # Custom table view cell
│   ├── StoryViewController.swift        # Story detail view + bookmark/share
│   ├── NoInternetFoundViewController.swift  # Offline fallback UI
│   ├── Reachability.swift               # Network connectivity checker
│   ├── Assets.xcassets/                 # App icons and images
│   └── Base.lproj/
│       ├── Main.storyboard              # Main UI layout
│       └── LaunchScreen.storyboard      # Launch screen
├── FeedReader.xcodeproj/                # Xcode project
├── Sources/FeedReaderCore/              # Swift Package for reusable RSS functionality
│   ├── RSSParser.swift                  # Standalone RSS parser
│   ├── RSSStory.swift                   # Story model with URL validation & HTML sanitization
│   ├── FeedItem.swift                   # Feed source model with 10 built-in presets
│   └── NetworkReachability.swift        # Network connectivity check
├── Tests/FeedReaderCoreTests/           # Swift Package tests
└── FeedReaderTests/                     # 1941 test cases across 48 test suites
```

## How It Works

1. **Launch** — App checks network connectivity via `Reachability`
2. **Online** — Fetches RSS feed asynchronously from BBC News, parses XML with `XMLParser`
3. **Offline** — Loads previously cached stories from disk via `NSKeyedUnarchiver`
4. **No Data** — Shows a friendly "no internet" screen with retry button
5. **Browsing** — Stories displayed in a `UITableView` with title, description, and thumbnail
6. **Detail** — Tapping a story shows full description with a link to the original article

## Swift Package

FeedReader's core RSS parsing and feed management functionality is available as a Swift Package (`FeedReaderCore`). Use it in your own iOS apps to add RSS reading capabilities without the UI layer.

### Installation via Swift Package Manager

Add FeedReader to your project's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/sauravbhattacharya001/FeedReader.git", from: "2.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies → Enter the repository URL.**

### Package API

```swift
import FeedReaderCore

// Parse an RSS feed
let parser = RSSParser()
let stories = parser.parseData(xmlData)  // [RSSStory]

// Check story properties
for story in stories {
    print(story.title)      // Story title
    print(story.body)       // HTML-stripped description
    print(story.link)       // Story URL
    print(story.imagePath)  // Optional thumbnail URL
}

// Use built-in feed presets
let feeds = FeedItem.presets  // BBC, NPR, TechCrunch, etc.

// Check network reachability
if NetworkReachability.isConnected() {
    // Fetch feeds
}

// Validate URLs safely
RSSStory.isSafeURL("https://example.com")  // true
RSSStory.isSafeURL("javascript:alert(1)")  // false
```

### Package Components

| Type | Description |
|---|---|
| `RSSParser` | XML-based RSS feed parser with concurrent multi-feed support and deduplication |
| `RSSStory` | Parsed story model with URL validation and HTML sanitization |
| `FeedItem` | Feed source model with 10 built-in presets |
| `NetworkReachability` | Network connectivity check via SystemConfiguration |

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
| Swipe right on a story | Adds/removes bookmark with orange indicator |
| Tap bookmark icon in nav bar | Opens bookmarks screen with saved stories |
| Tap ★ in story detail | Toggles bookmark with haptic feedback and toast |
| Swipe to delete in bookmarks | Removes individual bookmark |
| Clear All in bookmarks | Removes all bookmarks after confirmation |
| Tap 📡 antenna icon in nav bar | Opens feed manager with your feeds and available presets |
| Tap a feed in "Your Feeds" | Toggles feed on/off (green checkmark = active) |
| Swipe to delete a feed | Removes feed from your list |
| Tap a feed in "Available Feeds" | Adds preset feed to your list |
| Tap + button in feed manager | Opens dialog to add custom RSS feed URL |
| Tap Edit in feed manager | Enables drag-to-reorder for feed priority |
| Enable multiple feeds | Stories from all active feeds are merged (duplicates removed) |
| Tap a story in the list | Story is marked as read (blue dot disappears, text dims slightly) |
| Swipe left on a story | Toggle read/unread status with envelope icon |
| Tap ✓ checkmark icon in nav bar | Confirms and marks all stories as read |
| Select "Unread" filter segment | Shows only unread stories |
| Select "Read" filter segment | Shows only previously read stories |
| Select "All" filter segment | Shows all stories regardless of read status |
| Nav title shows unread count | Displays "(X unread)" when unread stories exist |
| Tap 📊 chart icon in nav bar | Opens reading statistics dashboard |
| Reading stats — overview | Shows total/today/week/month counts, daily average, bookmarks |
| Reading stats — streak | Shows current streak, longest streak, motivational message |
| Reading stats — hourly chart | Bar chart showing reading activity by hour (0-23) |
| Reading stats — feed breakdown | Per-feed progress bars sorted by stories read |
| Reading stats — clear all | Confirmation dialog, permanently deletes all history |
| Reading stats — empty state | Friendly prompt when no reading data exists |
| Add note on article | Note saved with timestamp, persists across sessions |
| Edit/delete article note | Note updated or removed from persistent storage |
| Create content filter | Keyword filter highlights or hides matching stories |
| Import/export filters (JSON) | Filters round-trip through JSON import/export |
| Feed health dashboard | Shows per-feed uptime %, response times, failure history |
| Feed health report | Generates aggregate health summary across all feeds |
| Save article offline | Full article cached for reading without internet |
| Browse offline articles | Cached articles accessible from dedicated screen |
| Clear offline cache | All cached articles removed after confirmation |
| Import OPML file | Feed subscriptions imported from standard OPML format |
| Export OPML file | Current feeds exported as valid OPML for other readers |
| Create smart feed | Keyword filter auto-matches stories across all feeds |
| Smart feed match modes | AND mode requires all keywords; OR matches any keyword |
| Smart feed search scopes | Search title only, description only, or both |

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

## Customizing Feed Sources

### In-App (Recommended)

Tap the 📡 antenna icon in the navigation bar to open the Feed Manager, where you can:

- **Toggle** feeds on/off by tapping them
- **Add presets** from 10 built-in feeds (BBC, NPR, TechCrunch, Ars Technica, Hacker News, The Verge, Reuters)
- **Add custom feeds** by tapping + and entering any RSS/Atom feed URL
- **Remove** feeds by swiping left
- **Reorder** feeds by tapping Edit and dragging

### Programmatically

To change the default first-launch feed, edit the presets in `Feed.swift`:

```swift
// In Feed.swift, modify the presets array:
static let presets: [Feed] = [
    Feed(name: "BBC World News", url: "https://feeds.bbci.co.uk/news/world/rss.xml", isEnabled: true),
    Feed(name: "Your Custom Feed", url: "https://yoursite.com/rss.xml", isEnabled: false),
    // ...
]
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

This project is licensed under the [MIT License](LICENSE).

---

<p align="center">
  Built with ❤️ by <a href="https://github.com/sauravbhattacharya001">Saurav Bhattacharya</a>
</p>
