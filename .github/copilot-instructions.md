# Copilot Instructions for FeedReader

## Project Overview

FeedReader is an iOS RSS feed reader built with Swift and UIKit. It started as a BBC News reader and has grown into a comprehensive reading platform with 163+ Swift source files and 123+ test files covering autonomous intelligence features, reading analytics, article analysis, and feed management.

## Architecture

- **UIKit + Storyboard**: `Main.storyboard` with `UINavigationController` → `StoryTableViewController` → `StoryViewController` flow
- **MVC pattern**: Models, managers (singletons), view controllers
- **SPM dual target**: Xcode project (`FeedReader.xcodeproj`) + Swift Package Manager (`FeedReaderCore` library in `Sources/FeedReaderCore`)
- **No external dependencies**: Pure Foundation/UIKit — no CocoaPods, no SPM packages

## Module Map (163 files, 12 functional areas)

### Core App (10 files)
| File | Purpose |
|------|---------|
| `Story.swift` | Data model — `NSObject` + `NSSecureCoding`, failable init, URL safety, HTML stripping |
| `Feed.swift` | Feed source model with URL, title, category |
| `StoryTableViewController.swift` | Main feed list — RSS parsing, image caching, table view |
| `StoryViewController.swift` | Story detail — title, description, bookmark/share, Safari link |
| `StoryTableViewCell.swift` | Custom table cell with title, description, thumbnail |
| `AppDelegate.swift` | App lifecycle (minimal) |
| `Reachability.swift` | Network connectivity via `SCNetworkReachability` |
| `FeedReaderLogger.swift` | Privacy-aware `os_log` wrapper (replaces raw `print()`) |
| `HTMLEscaping.swift` | HTML entity decoding utilities |
| `DateFormatting.swift` | RSS date parsing helpers |

### Feed Management (20+ files)
`FeedManager`, `FeedCategoryManager`, `FeedDiscoveryManager`, `FeedMergeManager`, `FeedBundleManager`, `FeedBackupManager`, `FeedMigrationAssistant`, `FeedUpdateScheduler`, `FeedNotificationManager`, `FeedSnoozeManager`, `FeedRatingManager`, `FeedPriorityRanker`, `FeedHealthManager`, `FeedHealthDashboardViewController`, `FeedDiffTracker`, `FeedComparisonManager`, `FeedPerformanceAnalyzer`, `FeedSubscriptionAnalyzer`, `SmartFeedManager`, `SmartFeedMixer`, `SmartFeedSearch`, `SmartUnsubscriber`, `FeedListViewController`, `OPMLManager`

### Autonomous Intelligence (12 files)
`FeedPredictiveAlerts`, `FeedKnowledgeGraph`, `FeedCuriosityEngine`, `FeedDebateArena`, `FeedNarrativeTracker`, `FeedSignalBooster`, `FeedSerendipityEngine`, `FeedImpactTracker`, `FeedBurnoutDetector`, `FeedAutopilot`, `FeedInboxZero`, `FeedTemporalOptimizer`

### Article Analysis & Enrichment (30+ files)
`ArticleSentimentAnalyzer`, `ArticleReadabilityAnalyzer`, `ArticleSummarizer`, `ArticleSummaryGenerator`, `ArticleFactChecker`, `ArticleTrendDetector`, `ArticleEngagementPredictor`, `ArticleLanguageDetector`, `ArticleGeoTagger`, `ArticleLinkExtractor`, `ArticleCrossReferenceEngine`, `ArticleRelationshipMapper`, `ArticleSimilarityManager`, `ArticleDeduplicator`, `ArticleOutlineGenerator`, `TopicClassifier`, `TextAnalyzer`, `SourceCredibilityScorer`, `SentimentTrendsTracker`, `ContentFilter`, `ContentFilterManager`, `ArticleDarkModeFormatter`, `ArticleComparisonView`, `ArticlePaywallDetector`, `ArticleFreshnessTracker`, `ArticleVersionTracker`, `ArticleEditTracker`, `ArticleWordCountTracker`, `VocabularyFrequencyProfiler`

### Reading Analytics & Gamification (25+ files)
`ReadingStatsManager`, `ReadingStatsViewController`, `ReadingHistoryManager`, `ReadingSessionTracker`, `ReadingSpeedTracker`, `ReadingPaceCalculator`, `ReadingTimeEstimator`, `ReadingTimeBudget`, `ReadingGoalsManager`, `ReadingStreakTracker`, `ReadingChallengeManager`, `ReadingAchievementsManager`, `ReadingHabitsProfiler`, `ReadingInsightsGenerator`, `ReadingReportCard`, `ReadingYearInReview`, `ReadingActivityHeatmap`, `ReadingBingoManager`, `ReadingFocusTimer`, `ReadingRitualManager`, `ReadingPlaylistManager`, `ReadingCoach`, `ReadingDataExporter`

### Bookmarks & Collections (10+ files)
`BookmarkManager`, `BookmarkFolderManager`, `BookmarksViewController`, `ArticleCollectionManager`, `ArticleHighlight`, `ArticleHighlightsManager`, `ArticleNotesManager`, `ArticleNote`, `ArticleQuoteJournal`, `ArticleTagManager`, `ReadStatusManager`

### Sharing & Export (8+ files)
`ShareManager`, `AnnotationShareManager`, `ArticleReadingListSharer`, `ArticleClipboard`, `ArticleCitationGenerator`, `ArticleThreadComposer`, `ArticleThreadManager`, `ReadLaterExporter`, `PersonalFeedPublisher`

### Learning & Study (5+ files)
`ArticleFlashcardGenerator`, `ArticleQuizGenerator`, `ArticleSpacedReview`, `ArticleSpeedReadPresenter`, `ReadingJournalManager`

### Content Discovery (5+ files)
`ArticleRecommendationEngine`, `ContentCalendar`, `DigestGenerator`, `ArticleDigestComposer`, `FeedSourceDiversityAuditor`

### Offline & Caching (5+ files)
`OfflineCacheManager`, `OfflineArticlesViewController`, `ImageCache`, `ReadingPositionManager`, `ReadingQueueManager`

### Privacy & Security (3 files)
`FeedPrivacyGuard`, `FeedWeatherReporter`, `URLValidator`

### Storage Utilities (5 files)
`SecureCodingStore`, `UserDefaultsCodableStore`, `VersionedCodableStore`, `JSONCoding`, `KeywordAlert` + `KeywordAlertManager`

### Visualization (4 files)
`WordCloudGenerator`, `WordCloudViewController`, `VocabularyProfileViewController`, `ArticleTextToSpeech`

## Building

```bash
# Xcode build (no code signing for CI)
xcodebuild build \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# SPM build (FeedReaderCore library)
swift build
```

## Testing

123 test files in `FeedReaderTests/` covering models, managers, engines, and view controllers.

```bash
# Xcode tests
xcodebuild test \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -configuration Debug \
  -enableCodeCoverage YES \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# SPM tests
swift test --enable-code-coverage
```

Test fixtures: `storiesTest.xml`, `multiStoriesTest.xml`, `malformedStoriesTest.xml`

## Conventions

- **Swift 5+**, targets iOS 13+
- **No external dependencies** — pure Foundation/UIKit
- **`NSSecureCoding`** for persistence — always use typed `decodeObject(of:forKey:)` methods
- **Failable inits** — `Story.init?()` rejects empty titles, empty bodies, unsafe URLs
- **`os_log` via `FeedReaderLogger`** — never use raw `print()` (CWE-532 prevention)
- **Image caching** — `NSCache` (in-memory) for thumbnails
- **Network requests** — `URLSession.shared.dataTask` with `[weak self]` capture
- **UI updates** — always dispatch to main thread via `DispatchQueue.main.async`
- **XML parsing** — delegate pattern (`XMLParserDelegate`)

## Security Rules

- **URL scheme validation**: `Story.isSafeURL()` allows only `https`/`http` — never bypass
- **HTML sanitization**: `Story.stripHTML()` in init path — keep it there
- **NSSecureCoding**: Always use secure deserialization with typed decoding
- **No `print()`**: Use `FeedReaderLogger` to prevent data exposure in logs

## What to Watch Out For

- Storyboard segues use identifier `"ShowDetail"` — update `prepare(for:sender:)` if changed
- `Reachability.swift` uses low-level C interop (`SCNetworkReachability`) — careful with pointer ops
- `NSCoding` properties: adding new properties to `Story` requires updating `encode(with:)` AND `init?(coder:)`
- Many managers are singletons with `shared` static property — thread safety matters
