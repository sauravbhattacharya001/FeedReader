# Testing Guide

FeedReader has a comprehensive test suite with 100+ test files covering all managers, models, and core functionality.

## Test Structure

```
FeedReaderTests/          # Main XCTest suite (Xcode project)
├── *Tests.swift          # 107 test files covering FeedReader/ sources
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

### Core Models & Parsing
| Test File | What It Covers |
|-----------|---------------|
| `StoryTests.swift`, `StoryModelTests.swift` | Story model serialization, equality, URL validation |
| `XMLParserTests.swift`, `RSSParserContentEncodedTests.swift` | RSS/XML feed parsing, content:encoded handling |
| `RSSParserSecurityTests.swift`, `XXETests.swift` | XML external entity attack prevention |
| `FeedTests.swift` | Feed model validation |

### Feed Management
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
| `OPMLTests.swift` | OPML import/export for feed lists |

### Content Analysis
| Test File | What It Covers |
|-----------|---------------|
| `ArticleReadabilityTests.swift` | Flesch-Kincaid and readability scoring |
| `ArticleSentimentTests.swift` | Sentiment analysis of articles |
| `ArticleSimilarityTests.swift` | Duplicate/similar article detection |
| `ArticleTrendTests.swift` | Trending topic detection |
| `ArticleDeduplicatorTests.swift` | Exact and fuzzy deduplication |
| `TopicClassifierTests.swift` | Topic categorization |
| `TextAnalyzerTests.swift` | Text statistics and analysis |

### Reading Analytics
| Test File | What It Covers |
|-----------|---------------|
| `ReadingStatsTests.swift` | Reading statistics aggregation |
| `ReadingStreakTests.swift` | Reading streak tracking |
| `ReadingGoalsTests.swift`, `ReadingGoalsTrackerTests.swift` | Daily/weekly goal management |
| `ReadingSpeedTrackerTests.swift` | Words-per-minute tracking |
| `ReadingSessionTrackerTests.swift` | Session duration tracking |
| `ReadingHistoryTests.swift` | Reading history persistence |
| `ReadingInsightsGeneratorTests.swift` | Weekly/monthly insight reports |
| `ReadingYearInReviewTests.swift` | Annual reading summary |

### User Features
| Test File | What It Covers |
|-----------|---------------|
| `BookmarkTests.swift` | Bookmark save/delete/list |
| `ArticleHighlightsTests.swift` | Text highlighting and retrieval |
| `ArticleNotesTests.swift` | Article annotations |
| `ContentFilterTests.swift`, `ContentFilterRegexCacheTests.swift` | Content filtering with regex |
| `KeywordAlertTests.swift` | Keyword-based notifications |
| `SearchFilterTests.swift` | Search and filter functionality |
| `ShareManagerTests.swift` | Share sheet and export |
| `OfflineCacheTests.swift` | Offline article storage |

### Security Tests
| Test File | What It Covers |
|-----------|---------------|
| `XXETests.swift` | XML External Entity injection prevention |
| `RSSParserSecurityTests.swift` | Malformed/malicious feed handling |
| `URLValidatorTests.swift` | URL scheme validation (reject file://, javascript://) |
| `FeedPrivacyGuardTests.swift` | Privacy-sensitive data handling |

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
