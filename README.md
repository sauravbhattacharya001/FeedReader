<p align="center">
  <img src="FeedReader/Assets.xcassets/AppIcon.appiconset/rss180.png" alt="FeedReader Logo" width="120" height="120">
</p>

<h1 align="center">FeedReader</h1>

<p align="center">
  <strong>A feature-rich native iOS RSS reader with offline caching, AI-powered analytics, and 160+ Swift modules</strong>
</p>

<p align="center">
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/ci.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/codeql.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/pages.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/pages.yml/badge.svg" alt="Pages"></a>
  <a href="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/docker.yml"><img src="https://github.com/sauravbhattacharya001/FeedReader/actions/workflows/docker.yml/badge.svg" alt="Docker"></a>
  <a href="https://codecov.io/gh/sauravbhattacharya001/FeedReader"><img src="https://codecov.io/gh/sauravbhattacharya001/FeedReader/graph/badge.svg" alt="Codecov"></a>
  <img src="https://img.shields.io/badge/tests-1941-brightgreen?logo=swift" alt="Tests">
  <br>
  <img src="https://img.shields.io/badge/platform-iOS-blue?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/swift-3.0+-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-8+-blue?logo=xcode" alt="Xcode">
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen?logo=swift&logoColor=white" alt="Swift Package Manager">
  <br>
  <a href="https://github.com/sauravbhattacharya001/FeedReader/releases/latest"><img src="https://img.shields.io/github/v/release/sauravbhattacharya001/FeedReader?include_prereleases&sort=semver" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/sauravbhattacharya001/FeedReader" alt="License"></a>
  <img src="https://img.shields.io/github/languages/code-size/sauravbhattacharya001/FeedReader" alt="Code Size">
  <img src="https://img.shields.io/github/last-commit/sauravbhattacharya001/FeedReader" alt="Last Commit">
  <img src="https://img.shields.io/github/contributors/sauravbhattacharya001/FeedReader" alt="Contributors">
  <a href="https://github.com/sauravbhattacharya001/FeedReader/network/dependabot"><img src="https://img.shields.io/badge/dependabot-enabled-025e8c?logo=dependabot" alt="Dependabot"></a>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
  - [Core Reading](#core-reading)
  - [Feed Management](#feed-management)
  - [Reading Intelligence](#reading-intelligence)
  - [Article Analysis](#article-analysis)
  - [Autonomous Engines](#autonomous-engines)
  - [Data & Export](#data--export)
  - [Security](#security)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Swift Package](#swift-package)
- [Getting Started](#getting-started)
- [Test Suite](#test-suite)
- [Tech Stack](#tech-stack)
- [Customizing Feeds](#customizing-feeds)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

FeedReader is a native iOS RSS reader built with UIKit and Foundation's `XMLParser`. What started as a clean table-view feed reader has grown into a 162-module platform with AI-powered content analysis, autonomous recommendation engines, and comprehensive reading analytics.

The app supports offline reading through persistent caching, handles connectivity changes gracefully, and loads thumbnails asynchronously with an in-memory cache. It ships with 10 built-in feed presets (BBC, NPR, TechCrunch, Ars Technica, Hacker News, The Verge, Reuters, and more) and supports any standard RSS/Atom feed URL.

**1,941 tests** across 48 suites verify everything from XML parsing edge cases to recommendation engine accuracy.

## Features

### Core Reading

| Feature | Description |
|---------|-------------|
| 📰 **RSS Feed Parsing** | Native `XMLParser`-based reader with concurrent multi-feed support and deduplication |
| 📶 **Offline Caching** | Stories persisted via `NSCoding`; full-article offline cache with size management |
| 🔍 **Search & Filter** | Real-time search across titles and descriptions; keyword content filters with highlight/hide |
| 📖 **Read/Unread Tracking** | Blue dot indicators, unread count in title bar, segmented filter (All/Unread/Read), swipe-left toggle |
| 🔖 **Bookmarks** | Swipe-to-bookmark, dedicated bookmarks screen, folder organization |
| 📤 **Share** | System share sheet integration for all articles |
| 🧠 **Smart Feeds** | Saved keyword filters with AND/OR match modes across title, description, or both |
| 📝 **Article Notes** | Timestamped annotations that persist across sessions |

### Feed Management

| Feature | Description |
|---------|-------------|
| 📡 **Multi-Feed Support** | Add, remove, toggle, and reorder feeds. 10 built-in presets plus custom URLs |
| 📂 **OPML Import/Export** | Standard OPML interoperability with other RSS readers |
| 📦 **Feed Bundles** | Curated topic packs for one-tap bulk subscription |
| 🏷️ **Feed Categories** | Organize feeds into custom groups |
| 🔍 **Feed Discovery** | Auto-discover RSS feeds from any website URL |
| ⚙️ **Feed Automation** | Rule-based engine for auto-bookmark, auto-tag, and other actions |
| 📊 **Feed Health Monitor** | Uptime %, response times, failure history, and health reports per feed |
| ⚡ **Performance Analyzer** | Parse times, payload sizes, and bottleneck detection |

### Reading Intelligence

| Feature | Description |
|---------|-------------|
| 📊 **Reading Statistics** | Total/daily/weekly/monthly counts, hourly activity chart, per-feed breakdown |
| 🔥 **Streak Tracking** | Current + longest reading streaks with motivational messages |
| 🎯 **Reading Goals** | Configurable daily/weekly targets with progress tracking |
| 🏆 **Achievements** | Gamification milestones for reading habits |
| 📓 **Reading Journal** | Auto-generated daily journal with reflection prompts, mood tagging, Markdown export |
| 📚 **Vocabulary Builder** | Extracts uncommon words with mastery levels (New → Learning → Familiar → Mastered), spaced review |
| ⏱️ **Reading Pace** | Speed tracking with per-article time estimates |
| 📅 **Activity Heatmap** | Visual reading activity over time |
| 🎲 **Reading Bingo** | Challenge cards for exploring diverse content |
| 📖 **Year in Review** | Annual reading summary and statistics |

### Article Analysis

| Feature | Description |
|---------|-------------|
| 😊 **Sentiment Analysis** | Per-article and cross-feed sentiment scoring |
| 📖 **Readability Scoring** | Flesch-Kincaid and other readability metrics |
| 📝 **Auto-Summarization** | Generate concise article summaries |
| 🏷️ **Topic Classification** | Automatic topic categorization across feeds |
| 🔗 **Cross-Reference Engine** | Find connections between articles across feeds |
| 📎 **Citation Generator** | Export citations in multiple academic formats |
| ✅ **Fact Checker** | Automated claim verification |
| 🌍 **Geo-Tagger** | Location extraction and mapping from article content |
| 🗣️ **Language Detection** | Identify article language |
| 🔄 **Version Tracking** | Detect content changes in articles over time |

### Autonomous Engines

These self-managing engines run continuously to provide intelligent, personalized experiences:

| Engine | Description |
|--------|-------------|
| 🎯 **Recommendation Engine** | Personalized article suggestions based on reading history |
| 🔮 **Predictive Alerts** | Anticipate topics of interest before they trend |
| 💡 **Curiosity Engine** | Surface surprising and serendipitous content |
| 🌊 **Serendipity Engine** | Introduce unexpected but relevant discoveries |
| 📡 **Signal Booster** | Amplify underappreciated high-quality content |
| 🗞️ **Narrative Tracker** | Follow developing stories across feeds and time |
| 🧩 **Knowledge Graph** | Build connections between topics, entities, and feeds |
| 📈 **Trend Detector** | Identify trending topics across all feeds |
| 💤 **Burnout Detector** | Detect information overload and suggest breaks |
| 🤖 **Autopilot** | Autonomous feed curation and priority management |
| 📬 **Inbox Zero** | Intelligent triage and prioritization |
| 📰 **Editorial Drift Compass** | Detect shifts in source editorial direction |
| 🛡️ **Source Credibility Scorer** | Trust profiling for RSS feed sources |
| 🔀 **Smart Feed Mixer** | Blend feeds for balanced, diverse reading |
| 📉 **Anomaly Detector** | Flag unusual feed behavior patterns |

### Data & Export

| Feature | Description |
|---------|-------------|
| 📤 **Reading Data Export** | Export reading history and statistics |
| 📋 **Digest Generator** | Periodic digest summaries of your feeds |
| 🗂️ **Article Collections** | Organize articles into custom collections |
| ⏰ **Read Later Reminders** | Scheduled reminders for saved articles |
| 🗃️ **Article Archive** | Long-term article storage with export |
| 💬 **Thread Composer** | Generate social media threads from articles |
| 🎴 **Flashcard Generator** | Create study flashcards from article content |
| ☁️ **Word Cloud** | Visual word frequency display with dedicated view controller |

### Security

- 🔒 **XXE Prevention** — XML parser hardened against external entity attacks
- 🛡️ **URL Validation** — Blocks `javascript:`, `data:`, `file:` schemes
- 🧹 **HTML Sanitization** — Strips potentially dangerous HTML from feed content
- 📋 **Privacy Guard** — Feed-level privacy controls and data minimization
- 📝 **Secure Coding** — `NSSecureCoding`-compliant persistent storage

## Quick Start

```bash
# Clone and open in Xcode
git clone https://github.com/sauravbhattacharya001/FeedReader.git
cd FeedReader
open FeedReader.xcodeproj

# Build and run (⌘R) on any iPhone simulator
# Run tests (⌘U) — 1,941 test cases across 48 suites
```

> **Using the Swift Package only?** Add `https://github.com/sauravbhattacharya001/FeedReader.git` as a package dependency (from `2.0.0`) and `import FeedReaderCore`.

## Architecture

FeedReader is organized into functional domains, each with dedicated managers, engines, and view controllers:

```
FeedReader/                              162 Swift modules
├── Core
│   ├── AppDelegate.swift                App lifecycle
│   ├── Story.swift                      Data model (NSCoding)
│   ├── Feed.swift                       Feed source model
│   ├── ImageCache.swift                 NSCache-based image caching
│   ├── Reachability.swift               Network connectivity
│   └── RSSFeedParser.swift              Multi-feed parser with deduplication
│
├── Feed Management (18 modules)
│   ├── FeedManager.swift                Feed CRUD + persistence
│   ├── FeedDiscoveryManager.swift       Auto-discover feeds from URLs
│   ├── FeedCategoryManager.swift        Feed grouping and categories
│   ├── FeedBundleManager.swift          Curated feed packs
│   ├── FeedMergeManager.swift           Multi-feed deduplication
│   ├── FeedAutomationEngine.swift       Rule-based feed automation
│   ├── FeedHealthManager.swift          Reliability and uptime tracking
│   ├── FeedPerformanceAnalyzer.swift    Parse/fetch profiling
│   └── ...                              Scheduler, backup, migration, etc.
│
├── Reading Intelligence (20 modules)
│   ├── ReadingStatsManager.swift        Analytics engine
│   ├── ReadingStreakTracker.swift        Streak calculation
│   ├── ReadingGoalsManager.swift        Configurable targets
│   ├── ReadingAchievementsManager.swift Gamification
│   ├── ReadingJournalManager.swift      Auto-generated journal
│   ├── VocabularyFrequencyProfiler.swift Word extraction + mastery
│   └── ...                              Pace, heatmap, bingo, year-in-review, etc.
│
├── Article Analysis (25 modules)
│   ├── ArticleSentimentAnalyzer.swift   Sentiment scoring
│   ├── ArticleReadabilityAnalyzer.swift Flesch-Kincaid metrics
│   ├── ArticleSummarizer.swift          Auto-summarization
│   ├── ArticleRecommendationEngine.swift Personalized suggestions
│   ├── ArticleTrendDetector.swift       Trending topic detection
│   ├── ArticleCrossReferenceEngine.swift Cross-article connections
│   └── ...                              Geo-tagging, fact-check, citations, etc.
│
├── Autonomous Engines (15 modules)
│   ├── FeedPredictiveAlerts.swift       Anticipate interesting content
│   ├── FeedCuriosityEngine.swift        Surface surprising content
│   ├── FeedSerendipityEngine.swift      Unexpected discoveries
│   ├── FeedKnowledgeGraph.swift         Entity-topic graph
│   ├── FeedNarrativeTracker.swift       Follow developing stories
│   ├── FeedAutopilot.swift              Autonomous curation
│   └── ...                              Burnout, signal boost, credibility, etc.
│
├── UI (8 view controllers)
│   ├── StoryTableViewController.swift   Main feed list
│   ├── StoryViewController.swift        Article detail
│   ├── BookmarksViewController.swift    Saved stories
│   ├── FeedListViewController.swift     Feed manager
│   ├── ReadingStatsViewController.swift Analytics dashboard
│   └── ...                              Offline, health, vocabulary, word cloud
│
├── Sources/FeedReaderCore/              Swift Package (reusable core)
│   ├── RSSParser.swift                  Standalone RSS parser
│   ├── RSSStory.swift                   Story model + URL validation
│   ├── FeedItem.swift                   Feed presets
│   └── NetworkReachability.swift        Connectivity check
│
└── Tests/                               1,941 tests across 48 suites
```

## Swift Package

FeedReader's core RSS parsing functionality is available as a Swift Package (`FeedReaderCore`).

### Installation

**Swift Package Manager:**

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sauravbhattacharya001/FeedReader.git", from: "2.0.0")
]
```

**Xcode:** File → Add Package Dependencies → paste the repository URL.

### Usage

```swift
import FeedReaderCore

// Parse an RSS feed
let parser = RSSParser()
let stories = parser.parseData(xmlData)

for story in stories {
    print(story.title)      // Story title
    print(story.body)       // HTML-stripped description
    print(story.link)       // Story URL
    print(story.imagePath)  // Optional thumbnail URL
}

// Built-in feed presets
let feeds = FeedItem.presets  // BBC, NPR, TechCrunch, Ars Technica, ...

// URL safety validation
RSSStory.isSafeURL("https://example.com")    // true
RSSStory.isSafeURL("javascript:alert(1)")    // false

// Network reachability
if NetworkReachability.isConnected() {
    // Fetch feeds
}
```

### Package API

| Type | Description |
|------|-------------|
| `RSSParser` | XML-based RSS parser with concurrent multi-feed support and deduplication |
| `RSSStory` | Parsed story model with URL validation and HTML sanitization |
| `FeedItem` | Feed source model with 10 built-in presets |
| `NetworkReachability` | Connectivity check via SystemConfiguration |

## Getting Started

### Prerequisites

- **Xcode 8+** (Swift 3)
- **iOS 10+** deployment target
- macOS with Xcode installed

### Installation

```bash
git clone https://github.com/sauravbhattacharya001/FeedReader.git
cd FeedReader
open FeedReader.xcodeproj
```

### Running

1. Select an iPhone simulator (iPhone 5S or later)
2. Press **⌘R** to build and run

### How It Works

1. **Launch** — Checks network connectivity via `Reachability`
2. **Online** — Fetches RSS feeds asynchronously, parses XML, deduplicates across sources
3. **Offline** — Loads cached stories from disk via `NSKeyedUnarchiver`
4. **No Data** — Shows a friendly "no internet" screen with retry button
5. **Browse** — Stories in a `UITableView` with title, description, and async thumbnail
6. **Detail** — Full description with link to original article in Safari

## Test Suite

**1,941 test cases** across 48 suites covering:

- RSS/XML parsing edge cases and malformed feeds
- Offline caching roundtrips and data integrity
- Feed management CRUD operations
- Reading statistics accuracy
- Recommendation engine relevance
- Content filter matching logic
- OPML import/export fidelity
- Security: XXE prevention, URL validation, HTML sanitization
- Smart feed keyword matching (AND/OR modes)
- Autonomous engine behavior

Run all tests: **⌘U** in Xcode, or use the Test Navigator (⌘6) for individual suites.

## Tech Stack

| Component | Technology |
|-----------|------------|
| **Language** | Swift 3+ |
| **UI** | UIKit (Storyboard-based) |
| **RSS Parsing** | Foundation `XMLParser` |
| **Networking** | `URLSession` (async) |
| **Persistence** | `NSCoding` + `NSKeyedArchiver`, `NSSecureCoding` |
| **Image Cache** | `NSCache` |
| **Network Detection** | `SystemConfiguration` / `SCNetworkReachability` |
| **Logging** | `os_log` via `FeedReaderLogger` |
| **CI/CD** | GitHub Actions (build, test, CodeQL, Pages, Docker) |

## Customizing Feeds

### In-App (Recommended)

Tap the 📡 antenna icon in the navigation bar to open the Feed Manager:

- **Toggle** feeds on/off by tapping
- **Add presets** from 10 built-in feeds
- **Add custom feeds** by tapping + and entering any RSS/Atom URL
- **Remove** feeds by swiping left
- **Reorder** by tapping Edit and dragging

### Programmatically

Edit the presets in `Feed.swift`:

```swift
static let presets: [Feed] = [
    Feed(name: "BBC World News", url: "https://feeds.bbci.co.uk/news/world/rss.xml", isEnabled: true),
    Feed(name: "Your Feed", url: "https://yoursite.com/rss.xml", isEnabled: false),
    // ...
]
```

## Documentation

Full docs at **[sauravbhattacharya001.github.io/FeedReader](https://sauravbhattacharya001.github.io/FeedReader/)**:

- [User Guide](https://sauravbhattacharya001.github.io/FeedReader/guide.html) — Getting started and daily usage
- [Architecture](https://sauravbhattacharya001.github.io/FeedReader/architecture.html) — Component design and data flow
- [API Reference](https://sauravbhattacharya001.github.io/FeedReader/api.html) — Swift Package API
- [Smart Features](https://sauravbhattacharya001.github.io/FeedReader/smart-features.html) — Smart feeds, recommendations, automation
- [Reading Analytics](https://sauravbhattacharya001.github.io/FeedReader/reading-analytics.html) — Stats, streaks, journal
- [Autonomous Intelligence](https://sauravbhattacharya001.github.io/FeedReader/autonomous-intelligence.html) — Self-managing engines

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

This project is licensed under the [MIT License](LICENSE).

---

<p align="center">
  Built with ❤️ by <a href="https://github.com/sauravbhattacharya001">Saurav Bhattacharya</a>
</p>
