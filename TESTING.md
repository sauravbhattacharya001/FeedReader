# Testing Guide

FeedReader has a comprehensive test suite with **118 test files** covering all managers, models, and core functionality.

## Test Structure

```
FeedReaderTests/          # Main XCTest suite (Xcode project)
├── *Tests.swift          # 118 test files covering FeedReader/ sources
├── *.xml / *.plist       # Test fixture data (RSS feeds, story plists)
Tests/
└── FeedReaderCoreTests/  # Swift Package Manager tests for FeedReaderCore library
```

## Running Tests

### Xcode (full app tests)
```bash
# Run the complete test suite
xcodebuild test \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath TestResults

# Run a single test file
xcodebuild test \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:FeedReaderTests/RSSParserSecurityTests
```

### Swift Package Manager (core library)
```bash
swift test
```

## Test Categories

### Core Models & Parsing (8 tests)
| Test File | What It Covers |
|-----------|---------------|
| `StoryTests.swift` | Story model serialization, equality, URL validation |
| `StoryModelTests.swift` | Story model edge cases and computed properties |
| `FeedTests.swift` | Feed model validation |
| `XMLParserTests.swift` | RSS/XML feed parsing |
| `RSSParserContentEncodedTests.swift` | content:encoded handling in RSS feeds |
| `RSSParserSecurityTests.swift` | Malformed/malicious feed handling |
| `XXETests.swift` | XML External Entity injection prevention |
| `ViewControllerTests.swift` | View controller lifecycle and state management |

### Feed Management (13 tests)
| Test File | What It Covers |
|-----------|---------------|
| `FeedManagerTests.swift` | Feed CRUD, subscription management |
| `FeedDiscoveryTests.swift` | Auto-discovery of feeds from URLs |
| `FeedCategoryTests.swift` | Category assignment and filtering |
| `FeedBundleManagerTests.swift` | Feed bundle import/export |
| `FeedUpdateSchedulerTests.swift` | Background refresh scheduling |
| `FeedHealthTests.swift` | Feed staleness and error detection |
| `FeedMergeManagerTests.swift` | Merging duplicate feed sources |
| `FeedMigrationAssistantTests.swift` | Data migration between versions |
| `FeedBackupManagerTests.swift` | Feed data backup and restore |
| `FeedSnoozeManagerTests.swift` | Temporarily muting/snoozing feeds |
| `FeedRatingManagerTests.swift` | User feed quality ratings |
| `FeedNotificationManagerTests.swift` | Feed update notification delivery |
| `FeedAnnotationManagerTests.swift` | Feed-level annotations and notes |

### Feed Intelligence & Analytics (8 tests)
| Test File | What It Covers |
|-----------|---------------|
| `FeedAutomationEngineTests.swift` | Automated feed processing rules |
| `FeedComparisonManagerTests.swift` | Comparing feeds side-by-side |
| `FeedComparisonOverlapTests.swift` | Detecting content overlap between feeds |
| `FeedCostTrackerTests.swift` | Tracking feed consumption cost/value |
| `FeedDiffTrackerTests.swift` | Tracking changes between feed updates |
| `FeedEngagementScoreboardTests.swift` | Feed engagement scoring and ranking |
| `FeedPerformanceAnalyzerTests.swift` | Feed load/parse performance metrics |
| `FeedPriorityRankerTests.swift` | Priority-based feed sorting |

### Feed Curation & Discovery (5 tests)
| Test File | What It Covers |
|-----------|---------------|
| `FeedSourceHealthMonitorTests.swift` | Source uptime and reliability monitoring |
| `FeedSubscriptionAnalyzerTests.swift` | Subscription health and usage analysis |
| `FeedWeatherReportTests.swift` | Feed health "weather report" dashboard |
| `SmartFeedMixerTests.swift` | Intelligent feed blending algorithms |
| `OPMLTests.swift` | OPML import/export for feed lists |

### Content Analysis (12 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ArticleReadabilityTests.swift` | Flesch-Kincaid and readability scoring |
| `ArticleReadabilityAnalyzerTests.swift` | Advanced readability metrics |
| `ArticleSentimentTests.swift` | Sentiment analysis of articles |
| `ArticleSimilarityTests.swift` | Duplicate/similar article detection |
| `ArticleTrendTests.swift` | Trending topic detection |
| `ArticleDeduplicatorTests.swift` | Exact and fuzzy deduplication |
| `ArticleFactCheckerTests.swift` | Claim verification and fact-checking |
| `ArticleLanguageDetectorTests.swift` | Article language identification |
| `ArticleLinkExtractorTests.swift` | Extracting and categorizing links |
| `ArticleRelationshipMapperTests.swift` | Mapping relationships between articles |
| `SentimentTrendsTests.swift` | Sentiment trend tracking over time |
| `TextAnalyzerTests.swift` | Text statistics and analysis |

### Article Management & Organization (11 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ArticleClipboardTests.swift` | Article clipboard operations |
| `ArticleCollectionManagerTests.swift` | Organizing articles into collections |
| `ArticleComparisonEngineTests.swift` | Comparing article content side-by-side |
| `ArticleCrossReferenceTests.swift` | Cross-referencing between articles |
| `ArticleEditTrackerTests.swift` | Tracking article edits/revisions |
| `ArticleExpiryManagerTests.swift` | Article expiration and cleanup |
| `ArticleFreshnessTrackerTests.swift` | Article freshness scoring |
| `ArticleGeoTaggerTests.swift` | Geographic tagging of articles |
| `ArticleTagTests.swift` | User-defined article tagging |
| `ArticleThreadManagerTests.swift` | Threading related articles together |
| `ArticleVersionTrackerTests.swift` | Article version history |

### Article Engagement & Interaction (5 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ArticleReactionManagerTests.swift` | Article reactions (like, save, share) |
| `ArticleReadLaterReminderTests.swift` | Read-later reminder scheduling |
| `ArticleRecommendationEngineTests.swift` | Personalized article recommendations |
| `RecommendationEngineTests.swift` | Core recommendation algorithm |
| `SmartFeedTests.swift` | Smart feed filtering and rules |

### Content Generation & Summarization (8 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ArticleSummarizerTests.swift` | Article auto-summarization |
| `ArticleSummaryGeneratorTests.swift` | Summary generation with different styles |
| `ArticleOutlineGeneratorTests.swift` | Generating article outlines/TOCs |
| `ArticleWordCloudGeneratorTests.swift` | Word cloud data generation |
| `ArticleCitationTests.swift` | Citation generation (APA, MLA, etc.) |
| `ArticleFlashcardGeneratorTests.swift` | Flashcard generation from articles |
| `ArticleQuizGeneratorTests.swift` | Quiz generation from article content |
| `DigestGeneratorTests.swift` | Multi-article digest compilation |

### Learning & Study Tools (3 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ArticleSpacedReviewTests.swift` | Spaced repetition review scheduling |
| `VocabularyBuilderTests.swift` | Vocabulary extraction and learning |
| `ArticleQuoteJournalTests.swift` | Saving and organizing article quotes |

### User Features (10 tests)
| Test File | What It Covers |
|-----------|---------------|
| `BookmarkTests.swift` | Bookmark save/delete/list |
| `ArticleHighlightsTests.swift` | Text highlighting and retrieval |
| `ArticleNotesTests.swift` | Article annotations |
| `AnnotationShareManagerTests.swift` | Sharing annotations and highlights |
| `ContentFilterTests.swift` | Content filtering rules |
| `ContentFilterRegexCacheTests.swift` | Regex cache for content filters |
| `KeywordAlertTests.swift` | Keyword-based notifications |
| `SearchFilterTests.swift` | Search and filter functionality |
| `ShareManagerTests.swift` | Share sheet and export |
| `OfflineCacheTests.swift` | Offline article storage |

### Reading Analytics (20 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ReadingStatsTests.swift` | Reading statistics aggregation |
| `ReadingStreakTests.swift` | Reading streak tracking |
| `ReadingGoalsTests.swift` | Daily/weekly goal management |
| `ReadingGoalsTrackerTests.swift` | Goal progress tracking and persistence |
| `ReadingSpeedTrackerTests.swift` | Words-per-minute tracking |
| `ReadingSessionTrackerTests.swift` | Session duration tracking |
| `ReadingHistoryTests.swift` | Reading history persistence |
| `ReadingInsightsGeneratorTests.swift` | Weekly/monthly insight reports |
| `ReadingYearInReviewTests.swift` | Annual reading summary |
| `ReadingAchievementsManagerTests.swift` | Achievement unlocks and badges |
| `ReadingActivityHeatmapTests.swift` | Activity heatmap data generation |
| `ReadingBingoCardTests.swift` | Reading bingo challenge cards |
| `ReadingChallengeTests.swift` | Reading challenge tracking |
| `ReadingDataExporterTests.swift` | Exporting reading data (CSV, JSON) |
| `ReadingFocusTimerTests.swift` | Focus timer / Pomodoro tracking |
| `ReadingHabitsProfilerTests.swift` | Reading habit pattern analysis |
| `ReadingJournalTests.swift` | Reading journal entries |
| `ReadingMoodTrackerTests.swift` | Mood tracking during reading sessions |
| `ReadingPacePredictorTests.swift` | Predicting reading completion time |
| `ReadingTimeBudgetTests.swift` | Reading time budget allocation |

### Reading Gamification & Engagement (4 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ReadingPlaylistTests.swift` | Curated reading playlists |
| `ReadingReportCardTests.swift` | Periodic reading report cards |
| `ReadingRitualTests.swift` | Reading ritual/habit tracking |
| `ReadStatusTests.swift` | Article read/unread status management |

### Publishing & Content Planning (2 tests)
| Test File | What It Covers |
|-----------|---------------|
| `PersonalFeedPublisherTests.swift` | Publishing personal curated feeds |
| `ContentCalendarTests.swift` | Content scheduling and calendar |

### Queue & Position Management (2 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ReadingPositionManagerTests.swift` | Saving/restoring scroll position |
| `ReadingQueueManagerTests.swift` | Reading queue ordering and management |

### Caching & Storage (3 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ImageCacheTests.swift` | Image caching and eviction |
| `UserDefaultsCodableStoreTests.swift` | Generic UserDefaults Codable storage |
| `VersionedCodableStoreTests.swift` | Versioned data migration storage |

### Content Metrics (2 tests)
| Test File | What It Covers |
|-----------|---------------|
| `ArticleWordCountTrackerTests.swift` | Per-article word count tracking |
| `TopicClassifierTests.swift` | Topic categorization |

### Security (4 tests)
| Test File | What It Covers |
|-----------|---------------|
| `XXETests.swift` | XML External Entity injection prevention |
| `RSSParserSecurityTests.swift` | Malformed/malicious feed handling |
| `URLValidatorTests.swift` | URL scheme validation (reject file://, javascript://) |
| `FeedPrivacyGuardTests.swift` | Privacy-sensitive data handling |

## Test Fixture Files

| File | Purpose |
|------|---------|
| `storiesTest.xml` | Sample RSS feed for parsing tests |
| `storiesTest.plist` | Serialized story data for model tests |
| `multiStoriesTest.xml` | Multi-item RSS feed |
| `malformedStoriesTest.xml` | Intentionally malformed RSS for error handling |
| `linkGuidTest.xml` | RSS feed with link-based GUIDs |

## Writing New Tests

1. **Create test file** in `FeedReaderTests/` matching the naming pattern: `{ClassName}Tests.swift`
2. **Import XCTest** and the module under test
3. **Use setUp/tearDown** for manager singletons that need a clean state:
   ```swift
   import XCTest
   @testable import FeedReader

   final class MyFeatureTests: XCTestCase {
       var manager: MyManager!

       override func setUp() {
           super.setUp()
           manager = MyManager()
       }

       override func tearDown() {
           manager = nil
           super.tearDown()
       }

       func testBasicBehavior() {
           // Arrange
           let input = ...

           // Act
           let result = manager.process(input)

           // Assert
           XCTAssertEqual(result.count, 3)
       }
   }
   ```
4. **Test naming**: Use `test` prefix + descriptive name (`testEmptyFeedReturnsNoStories`)
5. **For async operations**: Use `XCTestExpectation` with `waitForExpectations(timeout:)`

## Code Coverage

Coverage is configured via `.codecov.yml`. To generate a local coverage report:

```bash
xcodebuild test \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -enableCodeCoverage YES
```

The coverage report will be in the derived data directory under `Logs/Test/`.

## Test Coverage Summary

| Area | Tests | Key Coverage |
|------|-------|-------------|
| Core Models & Parsing | 8 | RSS/XML parsing, model serialization, XXE prevention |
| Feed Management | 13 | CRUD, discovery, scheduling, backup, migration |
| Feed Intelligence | 8 | Automation, performance, engagement, cost tracking |
| Feed Curation | 5 | Health monitoring, subscription analysis, smart mixing |
| Content Analysis | 12 | Readability, sentiment, deduplication, fact-checking |
| Article Organization | 11 | Collections, threading, versioning, geo-tagging |
| Article Engagement | 5 | Recommendations, reactions, smart feeds |
| Content Generation | 8 | Summarization, citations, flashcards, quizzes |
| Learning & Study | 3 | Spaced review, vocabulary, quote journaling |
| User Features | 10 | Bookmarks, highlights, search, offline, sharing |
| Reading Analytics | 20 | Stats, streaks, goals, habits, mood, insights |
| Reading Gamification | 4 | Playlists, report cards, rituals, read status |
| Publishing | 2 | Personal feed publishing, content calendar |
| Queue & Position | 2 | Position persistence, queue management |
| Caching & Storage | 3 | Image cache, Codable stores, versioned migration |
| Content Metrics | 2 | Word count tracking, topic classification |
| Security | 4 | XXE, parser security, URL validation, privacy |
| **Total** | **118** | |
