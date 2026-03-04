# Architecture

FeedReader is an iOS RSS/Atom feed reader built with UIKit, targeting iOS 13+. The codebase follows a manager-based architecture where self-contained singleton managers handle distinct feature domains, communicating via `NotificationCenter` and sharing the `Story` model.

## Module Map

```
┌─────────────────────────────────────────────────────────────┐
│                     View Controllers                         │
│  StoryTableVC ─ FeedListVC ─ BookmarksVC ─ ReadingStatsVC   │
│  StoryVC ─ OfflineArticlesVC ─ NoInternetFoundVC            │
└─────────────┬───────────────────────────────┬───────────────┘
              │ delegates/callbacks            │ data binding
┌─────────────▼───────────────────────────────▼───────────────┐
│                      Core Services                           │
│  FeedManager ─ RSSFeedParser ─ FeedUpdateScheduler           │
│  ReadStatusManager ─ BookmarkManager ─ ImageCache            │
└─────────────┬───────────────────────────────────────────────┘
              │
┌─────────────▼───────────────────────────────────────────────┐
│              Content Analysis & Intelligence                 │
│  ArticleReadabilityAnalyzer ─ ArticleSentimentAnalyzer       │
│  ArticleSimilarityManager ─ ArticleDeduplicator              │
│  ArticleTrendDetector ─ ArticleSummarizer ─ TextAnalyzer     │
│  ArticleRecommendationEngine ─ ArticleTagManager             │
│  FeedPerformanceAnalyzer ─ FeedHealthManager                 │
└──────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                   User Experience                            │
│  ReadingHistoryManager ─ ReadingStatsManager                 │
│  ReadingGoalsManager ─ ReadingStreakTracker                   │
│  ReadingQueueManager ─ KeywordAlertManager                   │
│  ArticleHighlightsManager ─ ArticleNotesManager              │
│  ArticleCollectionManager ─ ContentFilterManager             │
│  SmartFeedManager ─ ShareManager ─ DigestGenerator           │
└──────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                 Feed Management                              │
│  FeedDiscoveryManager ─ FeedCategoryManager                  │
│  FeedBundleManager ─ OPMLManager ─ OfflineCacheManager       │
└──────────────────────────────────────────────────────────────┘
```

## Data Model

### Story
The central model (`Story.swift`, 186 lines). Represents a single article:
- `title`, `body`, `link`, `imagePath`, `sourceFeedName`
- NSSecureCoding for archive persistence
- URL scheme validation (https/http only)

### Feed
Feed source configuration (`Feed.swift`, 100 lines):
- `name`, `url`, `isEnabled`
- NSSecureCoding persistence

## Core Services (7 modules, ~1,300 lines)

| Module | Lines | Purpose |
|--------|-------|---------|
| **FeedManager** | 181 | Feed CRUD, enable/disable, persistence (UserDefaults + NSKeyedArchiver). Singleton. |
| **RSSFeedParser** | 294 | XMLParser-based RSS/Atom parsing. Multi-feed aggregation, XXE protection, secure coding. |
| **FeedUpdateScheduler** | 369 | Background feed refresh with configurable intervals (15min–24h). Per-feed scheduling with priorities (high/normal/low). Battery/network-aware. |
| **ReadStatusManager** | 196 | Binary read/unread tracking per article link. Filter support (all/unread/read). NSKeyedArchiver persistence. |
| **BookmarkManager** | 130 | Flat bookmark list with NSSecureCoding. Add/remove/toggle/clear. |
| **ImageCache** | 267 | NSCache + disk cache with SHA256 key hashing. Async loading, 4-connection concurrency limit, CGImageSource downsampling for memory efficiency. |
| **Reachability** | 46 | Network reachability check via SCNetworkReachability. |

## Content Analysis (10 modules, ~3,900 lines)

| Module | Lines | Purpose |
|--------|-------|---------|
| **ArticleReadabilityAnalyzer** | 366 | Flesch-Kincaid, Gunning Fog, Coleman-Liau, SMOG, ARI readability scores. Sentence/word/syllable counting. Grade level labels. |
| **ArticleSentimentAnalyzer** | 523 | Keyword-based sentiment scoring with negation/intensifier/emoji handling. Per-sentence and aggregate analysis. Weighted multi-section scoring. |
| **ArticleSimilarityManager** | 386 | TF-IDF cosine similarity for "related articles" discovery. Configurable thresholds and result limits. |
| **ArticleDeduplicator** | 487 | Multi-signal deduplication (title 0.45, content 0.35, URL 0.20 weights). Finds same-story duplicates from different feeds. |
| **ArticleTrendDetector** | 384 | Topic extraction, velocity scoring, temporal analysis. Detects trending/emerging/sustained/declining topics. Z-score anomaly detection. |
| **ArticleSummarizer** | 287 | Extractive summarization via sentence scoring (position, length, keyword density). Configurable summary length. |
| **TextAnalyzer** | 117 | Word count, character count, keyword extraction, reading time estimation. |
| **ArticleRecommendationEngine** | 359 | Weighted scoring: reading history (0.3) + bookmarks (0.3) + keywords (0.2) + recency (0.2). Feed diversity bonus. |
| **ArticleTagManager** | 462 | Auto-tagging via keyword extraction + manual tags. Tag statistics, merge, search, trending tags. UserDefaults persistence. |
| **FeedPerformanceAnalyzer** | 812 | Per-feed report cards: publishing frequency, content quality (readability + substance + diversity), engagement, freshness. Composite scoring with configurable weights. |

## User Experience (13 modules, ~4,500 lines)

| Module | Lines | Purpose |
|--------|-------|---------|
| **ReadingHistoryManager** | 595 | Full browsable reading history with visit timestamps, counts, scroll progress, time spent. Binary search for date range queries. O(1) index lookups. |
| **ReadingStatsManager** | 272 | Aggregate reading analytics: articles/day, time/day, streaks, feed distribution. |
| **ReadingGoalsManager** | 251 | Daily/weekly article count and time goals. Progress tracking, streak calculation, period-based stats. |
| **ReadingStreakTracker** | 427 | Gamified reading streaks with current/longest/total tracking. Configurable minimum articles per day. Milestones and achievements. |
| **ReadingQueueManager** | 455 | Prioritized read-later queue. Manual reordering, auto-sort by priority/date. Max 200 items. |
| **KeywordAlertManager** | 208 | Push-style alerts when articles match keyword patterns. Supports regex, case sensitivity, feed scoping. |
| **ArticleHighlightsManager** | 241 | In-article text highlighting with color tags and notes. Per-article storage. |
| **ArticleNotesManager** | 177 | Standalone article notes (separate from highlights). Markdown support, search, export. |
| **ArticleCollectionManager** | 492 | Named article collections (playlists). Merge, pin, search, JSON export/import, O(1) reverse index. |
| **ContentFilterManager** | 375 | Mute articles by keyword with contains/exact-word/regex modes. Cached compiled regex patterns. Import/export. |
| **SmartFeedManager** | 287 | Saved keyword-based searches across all feeds. ANY/ALL match modes, title/body/both scopes. |
| **ShareManager** | 517 | Multi-format article sharing (plain text, Markdown, HTML, social, email). Single and digest modes. Share history tracking. |
| **DigestGenerator** | 580 | Personal newsletter generation from reading history. Configurable time windows, grouping by feed, 3 output formats. |

## Feed Management (5 modules, ~1,600 lines)

| Module | Lines | Purpose |
|--------|-------|---------|
| **FeedDiscoveryManager** | 424 | Auto-discovers RSS/Atom feeds from website URLs. HTML `<link>` tag parsing + common path probing. URL validation, redirect following. |
| **FeedCategoryManager** | 223 | Organize feeds into categories. Default categories, CRUD, feed-category assignment. |
| **FeedBundleManager** | 448 | Curated feed bundles by topic (Tech, Dev, Science, Design, AI, News). One-click subscribe, custom bundle CRUD, JSON import/export. |
| **OPMLManager** | 290 | OPML import/export for feed lists. Standard RSS reader interoperability. |
| **OfflineCacheManager** | 380 | Article content caching for offline reading. Per-article storage, cache size management, expiry. |
| **FeedHealthManager** | 590 | Feed reliability monitoring: success/failure tracking, error categorization, health scores, stale feed detection. |

## View Controllers (7 files, ~2,400 lines)

| Controller | Lines | Purpose |
|------------|-------|---------|
| **StoryTableViewController** | 577 | Main feed view. Search, read filter, pull-to-refresh, image prefetch, context menus. |
| **FeedListViewController** | 549 | Feed management UI. Add/edit/delete feeds, enable/disable, category assignment, discovery. |
| **ReadingStatsViewController** | 586 | Analytics dashboard with reading activity charts, feed distribution, streak display. |
| **StoryViewController** | 246 | Article detail view. WKWebView rendering, bookmarking, sharing, read tracking. |
| **OfflineArticlesViewController** | 222 | Cached article browser with cache stats and management. |
| **BookmarksViewController** | 159 | Bookmarked articles list with swipe-to-remove. |
| **NoInternetFoundViewController** | 20 | Offline error state. |

## Persistence Strategy

The app uses three persistence mechanisms:

1. **UserDefaults** — Collection metadata, filter configs, goals, streaks, stats, preferences (48 references across codebase)
2. **NSKeyedArchiver / NSSecureCoding** — Story objects, feeds, bookmarks (14 references)
3. **File system** — Share history JSON, offline article cache, image thumbnails

## Communication Pattern

Modules communicate via **NotificationCenter** (99 post calls across codebase). Key notifications:

| Notification | Posted by | Consumed by |
|-------------|-----------|-------------|
| `.feedsDidChange` | FeedManager | StoryTableVC, FeedListVC |
| `.readStatusDidChange` | ReadStatusManager | StoryTableVC |
| `.readingHistoryDidChange` | ReadingHistoryManager | ReadingStatsVC |
| `.collectionsDidChange` | ArticleCollectionManager | (UI) |
| `.contentFiltersDidChange` | ContentFilterManager | StoryTableVC |
| `.keywordAlertTriggered` | KeywordAlertManager | (UI) |

## Testing

**51 source files** (~16,000 lines) with **41 test files** (~16,000 lines of tests).

All managers use a testable architecture:
- Public `init()` (not private) for test isolation
- Pure-logic methods separated from I/O
- `clearAll()` methods for test cleanup

## Codebase Statistics

- **Total source**: ~16,000 lines across 51 Swift files
- **Total tests**: ~16,000 lines across 41 test files
- **Singletons**: 28 shared instances
- **Largest module**: FeedPerformanceAnalyzer (812 lines)
- **Largest test**: FeedHealthTests (1,055 lines)
