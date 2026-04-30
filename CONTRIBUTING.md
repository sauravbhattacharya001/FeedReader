# Contributing to FeedReader

Thank you for considering contributing to FeedReader! Whether it's a bug fix, new feature, documentation improvement, or test — all contributions are welcome.

## Table of Contents

- [First-Time Contributors](#first-time-contributors)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Commit Message Convention](#commit-message-convention)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Debugging Common Issues](#debugging-common-issues)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Reporting Issues](#reporting-issues)
- [Code of Conduct](#code-of-conduct)

## First-Time Contributors

New to FeedReader? Here's the fastest path to your first contribution:

1. Look for issues labeled [`good first issue`](https://github.com/sauravbhattacharya001/FeedReader/labels/good%20first%20issue) — these are scoped and well-documented.
2. Read [ARCHITECTURE.md](ARCHITECTURE.md) for a high-level map of the codebase.
3. Start with `Sources/FeedReaderCore/` — it has no UIKit dependency, builds fast with `swift build`, and has the best test coverage.
4. If you're unfamiliar with Swift/iOS, `Tests/FeedReaderCoreTests/` is a great place to add value without touching app UI.

**Quick wins:**
- Improve a docstring or add `/// - Parameter` documentation to a public method
- Add a missing test case for an edge condition (see [TESTING.md](TESTING.md) for coverage gaps)
- Fix a typo or broken link in documentation

## Getting Started

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/FeedReader.git
   cd FeedReader
   ```
3. **Choose your workflow:**
   - **Full app:** Open `FeedReader.xcodeproj` in Xcode
   - **Core library only:** Use Swift Package Manager (see below)
4. **Build and run** on a simulator (Cmd+R) to verify everything works.

## Project Structure

FeedReader has two layers: the iOS app and a standalone core library.

```
FeedReader/
├── FeedReader/                      # iOS app (162 Swift files)
│   ├── AppDelegate.swift            # App lifecycle
│   ├── RSSFeedParser.swift          # Original XML parser
│   ├── Story.swift / Feed.swift     # App data models
│   ├── FeedManager.swift            # Multi-feed management
│   ├── BookmarkManager.swift        # Bookmark persistence (NSCoding)
│   ├── ImageCache.swift             # Async image loading + NSCache
│   ├── Reachability.swift           # Network connectivity
│   ├── Article*.swift               # Article analysis, export, quiz, etc.
│   ├── Feed*.swift                  # Feed health, autopilot, serendipity, etc.
│   ├── Reading*.swift               # Reading stats, habits, gamification
│   ├── *ViewController.swift        # UIKit view controllers
│   └── Base.lproj/                  # Storyboards
│
├── Sources/FeedReaderCore/          # SPM library (18 Swift files)
│   ├── RSSParser.swift              # Standalone RSS parser
│   ├── FeedItem.swift / RSSStory.swift  # Core models
│   ├── FeedCacheManager.swift       # Feed caching
│   ├── FeedHealthMonitor.swift      # Feed health tracking
│   ├── KeywordExtractor.swift       # Text analysis
│   ├── TextUtilities.swift          # String helpers
│   ├── OPMLManager.swift            # OPML import/export
│   └── ArticleArchiveExporter.swift # Archive export
│
├── FeedReaderTests/                 # XCTest suite for the iOS app (122 test files)
├── Tests/FeedReaderCoreTests/       # XCTest suite for the SPM library (8 test files)
├── docs/                            # Generated documentation
├── Package.swift                    # SPM manifest (swift-tools-version:5.9)
├── FeedReaderCore.podspec           # CocoaPods spec
└── Dockerfile                       # Docker build environment
```

**Key distinction:** `FeedReader/` is the full iOS app with UIKit. `Sources/FeedReaderCore/` is the headless core library distributed via SPM and CocoaPods — it has no UIKit dependency and can be used in any Swift project.

### Module Catalog by Functional Area

With 162 source files, knowing where things live is essential. Here's every module organized by what it does:

#### Core Data Models & Parsing
| Module | Purpose |
|--------|---------|
| `Story.swift` | Main article data model (NSCoding) |
| `Feed.swift` | Feed source model |
| `RSSFeedParser.swift` | App-layer XML feed parser (NSXMLParser delegate) |
| `JSONCoding.swift` | JSON serialization helpers |
| `DateFormatting.swift` | RSS date format parsing |
| `HTMLEscaping.swift` | HTML entity decoding |
| `SecureCodingStore.swift` | NSSecureCoding persistence wrapper |
| `UserDefaultsCodableStore.swift` | Type-safe UserDefaults Codable store |
| `VersionedCodableStore.swift` | Versioned Codable persistence with migration |

#### Feed Management (37 modules)
| Module | Purpose |
|--------|---------|
| `FeedManager.swift` | Multi-feed CRUD, subscription management |
| `FeedCategoryManager.swift` | Feed categorization and folder organization |
| `FeedDiscoveryManager.swift` | Auto-discover RSS feeds from URLs |
| `FeedMergeManager.swift` | Merge duplicate or related feeds |
| `FeedBundleManager.swift` | Curated feed bundles ("starter packs") |
| `FeedMigrationAssistant.swift` | Import feeds from other apps |
| `FeedBackupManager.swift` | Export/import feed subscriptions |
| `FeedUpdateScheduler.swift` | Smart refresh scheduling per feed |
| `FeedSnoozeManager.swift` | Temporarily pause feed updates |
| `FeedPriorityRanker.swift` | Rank feeds by user engagement |
| `FeedRatingManager.swift` | User-assigned feed quality ratings |
| `FeedHealthManager.swift` | Track feed uptime and error rates |
| `FeedAnomalyDetector.swift` | Detect unusual feed behavior |
| `FeedPerformanceAnalyzer.swift` | Response time and reliability metrics |
| `FeedDiffTracker.swift` | Track article additions/removals per refresh |
| `FeedTimelineReconstructor.swift` | Rebuild chronological feed history |
| `FeedComparisonManager.swift` | Compare two feeds side-by-side |
| `FeedSourceDiversityAuditor.swift` | Audit political/topical diversity |
| `FeedEngagementScoreboard.swift` | Gamified feed engagement tracking |
| `FeedSubscriptionAnalyzer.swift` | Analyze subscription patterns |
| `FeedAnnotationManager.swift` | Per-feed user annotations |
| `FeedNotificationManager.swift` | Per-feed notification rules |
| `FeedPrivacyGuard.swift` | Privacy-sensitive feed handling |
| `SmartFeedManager.swift` | AI-powered feed recommendations |
| `SmartFeedMixer.swift` | Cross-feed article blending |
| `SmartFeedSearch.swift` | Full-text search across all feeds |
| `SmartUnsubscriber.swift` | Suggest feeds to unsubscribe from |
| `FeedAutopilot.swift` | Fully automated feed curation |
| `FeedAutomationEngine.swift` | Rule-based feed automation |
| `FeedPredictiveAlerts.swift` | Predict interesting upcoming articles |
| `FeedSignalBooster.swift` | Amplify weak but relevant signals |
| `FeedSerendipityEngine.swift` | Surface surprising content |
| `FeedCuriosityEngine.swift` | Curiosity-driven exploration |
| `FeedDebateArena.swift` | Multi-perspective debate view |
| `FeedKnowledgeGraph.swift` | Build knowledge graph from feeds |
| `FeedNarrativeTracker.swift` | Track evolving stories across feeds |
| `FeedWeatherReporter.swift` | "Feed weather" health summary |

#### Autonomous Intelligence (6 modules)
| Module | Purpose |
|--------|---------|
| `FeedBurnoutDetector.swift` | Detect reading burnout patterns |
| `FeedForgettingCurve.swift` | Spaced-repetition article resurfacing |
| `FeedImpactTracker.swift` | Measure real-world article impact |
| `FeedInboxZero.swift` | Inbox-zero workflow for feeds |
| `FeedReadingCoach.swift` | Personalized reading guidance |
| `FeedInterestEvolver.swift` | Autonomous interest evolution |

#### Article Analysis & Processing (51 modules)
| Module | Purpose |
|--------|---------|
| `ArticleSummarizer.swift` | Single-article summarization |
| `ArticleSummaryGenerator.swift` | Batch summary generation |
| `ArticleDigestComposer.swift` | Daily digest compilation |
| `ArticleOutlineGenerator.swift` | Article structure extraction |
| `ArticleReadabilityAnalyzer.swift` | Readability scoring (Flesch-Kincaid, etc.) |
| `ArticleSentimentAnalyzer.swift` | Sentiment analysis per article |
| `ArticleMoodTracker.swift` | Track emotional tone over time |
| `ArticleFactChecker.swift` | Basic claim verification |
| `ArticleLanguageDetector.swift` | Identify article language |
| `ArticleLinkExtractor.swift` | Extract and classify embedded links |
| `ArticleGeoTagger.swift` | Extract geographic references |
| `ArticleTrendDetector.swift` | Identify trending topics |
| `ArticleDeduplicator.swift` | Find and merge duplicate articles |
| `ArticleSimilarityManager.swift` | Compute article similarity scores |
| `ArticleCrossReferenceEngine.swift` | Cross-reference related articles |
| `ArticleRelationshipMapper.swift` | Map article relationships |
| `ArticleEngagementPredictor.swift` | Predict user engagement with articles |
| `ArticlePaywallDetector.swift` | Detect paywalled content |
| `ArticleEditTracker.swift` | Track article post-publication edits |
| `ArticleVersionTracker.swift` | Version history for edited articles |
| `ArticleFreshnessTracker.swift` | Track content freshness/staleness |
| `ArticleExpiryManager.swift` | Auto-archive expired articles |
| `ArticleWordCountTracker.swift` | Word count stats |
| `TextAnalyzer.swift` | General-purpose text analysis |
| `TopicClassifier.swift` | Topic/category classification |
| `VocabularyFrequencyProfiler.swift` | Vocabulary frequency analysis |
| `SentimentTrendsTracker.swift` | Long-term sentiment trends |
| `SourceCredibilityScorer.swift` | Score source trustworthiness |
| `ContentFilter.swift` | Content filtering rules |
| `ContentFilterManager.swift` | Filter rule management |
| `ContentCalendar.swift` | Calendar view of content |
| `KeywordAlert.swift` | Keyword alert model |
| `KeywordAlertManager.swift` | Manage keyword alerts |
| `DigestGenerator.swift` | Generate reading digests |
| `PersonalFeedPublisher.swift` | Publish personal curated feeds |
| `ArticleHighlight.swift` | Highlight data model |
| `ArticleHighlightsManager.swift` | Manage article highlights |
| `ArticleNote.swift` | Note data model |
| `ArticleNotesManager.swift` | Manage article notes |
| `ArticleTagManager.swift` | Article tagging system |
| `ArticleQuoteJournal.swift` | Save notable quotes |
| `ArticleReactionManager.swift` | Emoji/reaction system for articles |
| `AnnotationShareManager.swift` | Share annotations/highlights |
| `ArticleClipboard.swift` | Article clipping and excerpts |
| `ArticleArchiveExporter.swift` | Export article archives |
| `ArticleReadingListSharer.swift` | Share reading lists |
| `ArticleCitationGenerator.swift` | Generate citations (APA, MLA, etc.) |
| `ArticleThreadComposer.swift` | Compose article discussion threads |
| `ArticleThreadManager.swift` | Manage discussion threads |
| `ArticleTimeCapsule.swift` | Schedule articles for future reading |
| `ArticleTranslationMemory.swift` | Cache article translations |

#### Reading Engagement & Gamification (25 modules)
| Module | Purpose |
|--------|---------|
| `ReadingSessionTracker.swift` | Track individual reading sessions |
| `ReadingSpeedTracker.swift` | WPM measurement and trends |
| `ReadingPaceCalculator.swift` | Estimated time to finish |
| `ReadingTimeEstimator.swift` | Article read-time predictions |
| `ReadingTimeBudget.swift` | Daily reading time budgets |
| `ReadingPositionManager.swift` | Remember scroll position per article |
| `ReadingHistoryManager.swift` | Full reading history log |
| `ReadStatusManager.swift` | Read/unread state management |
| `ReadingStatsManager.swift` | Aggregated reading statistics |
| `ReadingInsightsGenerator.swift` | Generate reading habit insights |
| `ReadingHabitsProfiler.swift` | Profile reading patterns |
| `ReadingActivityHeatmap.swift` | GitHub-style reading heatmap |
| `ReadingReportCard.swift` | Periodic reading report cards |
| `ReadingYearInReview.swift` | Annual reading summary |
| `ReadingGoalsManager.swift` | Set and track reading goals |
| `ReadingChallengeManager.swift` | Reading challenges (30-day, etc.) |
| `ReadingBingoManager.swift` | Reading bingo card gamification |
| `ReadingAchievementsManager.swift` | Unlock reading achievements |
| `ReadingStreakTracker.swift` | Daily reading streak tracking |
| `ReadingFocusTimer.swift` | Pomodoro-style reading timer |
| `ReadingRitualManager.swift` | Custom reading ritual routines |
| `ReadingPlaylistManager.swift` | Curated article playlists |
| `ReadingQueueManager.swift` | Reading queue management |
| `ReadingJournalManager.swift` | Reading journal entries |
| `ReadingDataExporter.swift` | Export all reading data |

#### Study & Learning (4 modules)
| Module | Purpose |
|--------|---------|
| `ArticleQuizGenerator.swift` | Generate comprehension quizzes |
| `ArticleFlashcardGenerator.swift` | Create flashcards from articles |
| `ArticleSpacedReview.swift` | Spaced-repetition review scheduling |
| `ArticleFlashback.swift` | "On this day" article flashbacks |

#### Presentation & UI (10 modules)
| Module | Purpose |
|--------|---------|
| `ArticleSpeedReadPresenter.swift` | RSVP speed-reading mode |
| `ArticleDarkModeFormatter.swift` | Dark mode content formatting |
| `ArticleTextToSpeech.swift` | Read articles aloud (AVSpeechSynthesizer) |
| `ArticleComparisonView.swift` | Side-by-side article comparison UI |
| `WordCloudGenerator.swift` | Generate word clouds from articles |
| `FeedReaderLogger.swift` | Privacy-aware os_log logging |
| `ImageCache.swift` | Async image loading + NSCache |
| `Reachability.swift` | Network connectivity monitoring |
| `URLValidator.swift` | URL validation and sanitization |
| `OfflineCacheManager.swift` | Offline article caching |

#### Bookmarks & Read Later (4 modules)
| Module | Purpose |
|--------|---------|
| `BookmarkManager.swift` | Bookmark persistence (NSCoding) |
| `BookmarkFolderManager.swift` | Bookmark folder organization |
| `ReadLaterExporter.swift` | Export read-later lists |
| `ArticleReadLaterReminder.swift` | Remind about saved articles |

#### Sharing (2 modules)
| Module | Purpose |
|--------|---------|
| `ShareManager.swift` | Multi-platform sharing |
| `OPMLManager.swift` | OPML import/export |

#### View Controllers (8 modules)
| Module | Purpose |
|--------|---------|
| `FeedListViewController.swift` | Feed source list |
| `StoryTableViewController.swift` | Article list (main screen) |
| `StoryViewController.swift` | Article detail view |
| `BookmarksViewController.swift` | Bookmarks screen |
| `ReadingStatsViewController.swift` | Reading statistics dashboard |
| `OfflineArticlesViewController.swift` | Offline articles browser |
| `FeedHealthDashboardViewController.swift` | Feed health dashboard |
| `VocabularyProfileViewController.swift` | Vocabulary insights |
| `NoInternetFoundViewController.swift` | No connectivity screen |
| `WordCloudViewController.swift` | Word cloud display |

## Development Setup

### Requirements

- **Xcode 15+** (Swift 5.9+)
- **iOS 14+** Simulator or device
- **macOS** with Xcode Command Line Tools installed

### Building the iOS App

```bash
open FeedReader.xcodeproj
# Build: Cmd+B | Run: Cmd+R | Test: Cmd+U
```

### Building the Core Library (SPM)

```bash
swift build
swift test
```

### No External Dependencies

FeedReader uses zero third-party libraries. Everything is built with Apple frameworks:
- `Foundation` / `UIKit` — core UI and data
- `XMLParser` — RSS feed parsing
- `NSCache` / `NSCoding` — caching and persistence
- `SystemConfiguration` — network reachability

No CocoaPods, Carthage, or SPM dependency setup needed.

## Coding Standards

### Swift Style

- Follow existing code conventions (Swift 5 style)
- Use `// MARK: -` sections to organize view controller code
- Prefer descriptive variable and method names
- Keep methods focused — one responsibility per method
- Use `guard` for early returns over nested `if` blocks

### Architecture Patterns

- **Delegate pattern** for parser callbacks and view controller communication
- **NSCoding** for persistence in the app layer
- **Codable** for models in `FeedReaderCore`
- **NSCache** for in-memory caching (not custom dictionaries)
- **Protocol-oriented design** for testable interfaces

### Where to Put New Code

| Type | Location |
|------|----------|
| Platform-independent logic (parsing, models, text processing) | `Sources/FeedReaderCore/` |
| iOS-specific UI, view controllers, UIKit extensions | `FeedReader/` |
| Tests for core library | `Tests/FeedReaderCoreTests/` |
| Tests for iOS app | `FeedReaderTests/` |

When in doubt, prefer `FeedReaderCore` — it's easier to test and reuse.

### Things to Avoid

- Don't introduce third-party dependencies without discussion first
- Don't break offline functionality — cached stories must always work
- Don't trust RSS feed content — sanitize/validate external data
- Don't force-unwrap optionals unless the value is guaranteed (e.g., storyboard outlets)

## Commit Message Convention

We use a lightweight [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <short summary>

<optional body — explain *why*, not *what*>

Fixes #<issue-number>
```

**Types:**

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code restructuring (no behavior change) |
| `test` | Adding or improving tests |
| `docs` | Documentation only |
| `perf` | Performance improvement |
| `security` | Security hardening |
| `chore` | Build config, CI, tooling |

**Scopes:** `core` (FeedReaderCore), `app` (iOS app), `tests`, `ci`, `docs`

**Examples:**
```bash
git commit -m "fix(core): handle empty CDATA sections in RSS items

RSSParser.swift crashed on <description><![CDATA[]]></description>
because the CDATA handler assumed non-empty content.

Fixes #42"

git commit -m "test(core): add edge cases for KeywordExtractor"

git commit -m "perf(app): lazy-load thumbnails in StoryTableViewCell"
```

## Making Changes

1. **Create a feature branch** from `master`:
   ```bash
   git checkout -b feature/my-improvement
   ```

2. **Make your changes** in small, logical commits following the [commit convention](#commit-message-convention).

3. **Test thoroughly** (see [Testing](#testing) below).

4. **Commit** with a clear message:
   ```bash
   git commit -m "feat(app): add swipe-to-delete for bookmarks
   
   Implements UITableViewDelegate editingStyle to allow
   removing bookmarks with a swipe gesture."
   ```

## Testing

FeedReader has two test suites. See [TESTING.md](TESTING.md) for the full testing guide.

### Quick Start

```bash
# SPM core library tests (fast, no simulator needed)
swift test

# Full iOS app tests via Xcode
xcodebuild test \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### What to Test

- **Model logic** — encoding/decoding, equality, date handling
- **Feed parsing** — `RSSParser` / `RSSFeedParser` with various XML inputs
- **Managers** — BookmarkManager, FeedManager, FeedCacheManager CRUD operations
- **Core library** — KeywordExtractor, TextUtilities, OPMLManager
- **UI** — manual testing for view controller changes (see checklist below)

### Manual Testing Checklist

Before submitting a PR, verify:

- [ ] App launches and displays feed stories
- [ ] Pull-to-refresh fetches new stories
- [ ] Stories load correctly when tapping a feed
- [ ] Bookmarking a story works
- [ ] Bookmarks screen shows saved stories
- [ ] Search filters stories in real-time
- [ ] Disabling network shows cached stories / offline screen
- [ ] Image thumbnails load and cache properly
- [ ] Adding/removing feed sources works

## Submitting a Pull Request

1. **Push** your branch to your fork:
   ```bash
   git push origin feature/my-improvement
   ```

2. **Open a Pull Request** against `master` on the upstream repo.

3. **Fill out the PR template** — describe your changes, what you tested, and include screenshots for UI changes.

4. **Respond to feedback** — we may request changes or ask questions.

### PR Guidelines

- Keep PRs focused. One feature or fix per PR.
- Include before/after screenshots for any UI changes.
- Reference related issues (e.g., "Fixes #12").
- Make sure CI passes before requesting review.
- If your change touches `FeedReaderCore`, add or update SPM tests.

## Reporting Issues

- Use the [Bug Report](https://github.com/sauravbhattacharya001/FeedReader/issues/new?template=bug_report.yml) template for bugs.
- Use the [Feature Request](https://github.com/sauravbhattacharya001/FeedReader/issues/new?template=feature_request.yml) template for ideas.
- For **security vulnerabilities**, follow [SECURITY.md](SECURITY.md) — do not open a public issue.

## Test Coverage Gaps

With 122 test files covering 162 source files, there are still **73 modules without dedicated tests**. These are excellent contribution targets — no deep app knowledge needed, just read the module and write XCTests.

### High-Impact Untested Modules

These modules have complex logic that would benefit most from testing:

| Module | Why It Matters |
|--------|----------------|
| `BookmarkManager.swift` | Core persistence — data loss bugs are catastrophic |
| `RSSFeedParser.swift` | XML parsing edge cases (malformed feeds, encoding) |
| `SmartFeedManager.swift` | Recommendation logic affecting what users see |
| `SmartFeedSearch.swift` | Search relevance and ranking |
| `FeedHealthManager.swift` | Health tracking accuracy |
| `ArticleSentimentAnalyzer.swift` | NLP accuracy on diverse content |
| `ArticlePaywallDetector.swift` | Detection heuristics for different paywall types |
| `ContentFilterManager.swift` | Filter rule application and precedence |
| `SecureCodingStore.swift` | Security-critical persistence |
| `URLValidator.swift` | Security-critical input validation |

### Quick-Win Test Targets

These modules are small/pure and easy to test in isolation:

- `DateFormatting.swift` — Parse various RSS date formats
- `HTMLEscaping.swift` — Entity decoding edge cases
- `JSONCoding.swift` — Serialization round-trips
- `ArticleCitationGenerator.swift` — Citation format correctness
- `ReadingPaceCalculator.swift` — WPM calculations
- `ReadingTimeEstimator.swift` — Time estimate accuracy
- `ArticleWordCountTracker.swift` — Word counting with various content
- `FeedForgettingCurve.swift` — Spaced-repetition interval math

### Autonomous Intelligence Modules (All Untested)

The entire autonomous intelligence suite lacks tests:

- `FeedBurnoutDetector.swift` — Burnout pattern detection
- `FeedCuriosityEngine.swift` — Curiosity-driven recommendations
- `FeedDebateArena.swift` — Multi-perspective article pairing
- `FeedImpactTracker.swift` — Article impact measurement
- `FeedInboxZero.swift` — Inbox-zero workflow logic
- `FeedKnowledgeGraph.swift` — Knowledge graph construction
- `FeedNarrativeTracker.swift` — Evolving story tracking
- `FeedPredictiveAlerts.swift` — Prediction algorithms
- `FeedSerendipityEngine.swift` — Serendipity scoring
- `FeedSignalBooster.swift` — Signal amplification logic
- `FeedReadingCoach.swift` — Coaching recommendation logic

Pick any of these and add a test file following the `FeedReaderTests/` naming pattern (e.g., `FeedBurnoutDetectorTests.swift`). Even 5–10 focused tests per module dramatically improves confidence.

## Performance Profiling

FeedReader handles large feed lists, image caching, and XML parsing on mobile devices with constrained resources. If your change touches hot paths, profile it.

### When to Profile

- **Always profile** changes to: `RSSFeedParser`, `ImageCache`, `FeedManager.refreshAll()`, `SmartFeedManager`, `FeedKnowledgeGraph`, any batch-processing logic
- **Consider profiling** changes that add: new timers/observers, collection iterations over feed items, CoreData/NSCoding operations

### Instruments Quick Start

```bash
# 1. Build for profiling (Release config, optimizations enabled)
xcodebuild build-for-testing \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# 2. Launch Instruments from command line
open -a Instruments
```

**Recommended Instruments templates:**

| Scenario | Template | What to Look For |
|----------|----------|------------------|
| Feed refresh feels slow | Time Profiler | Hot functions in `RSSFeedParser.parse()`, redundant `NSKeyedArchiver` calls |
| Memory grows unbounded | Allocations | Leaked `Story` objects, unbounded `ImageCache` growth |
| Scrolling stutters | Core Animation | Off-main-thread UIKit calls, excessive `layoutSubviews` |
| Battery drain | Energy Log | Background fetch frequency, network keep-alive |
| Disk I/O spikes | File Activity | Synchronous writes on main thread, excessive cache flushes |

### Memory Budget Guidelines

- **Image cache**: Should not exceed 50MB resident (configured via `NSCache.totalCostLimit`)
- **Feed model objects**: ~2KB per `Story`, ~500 bytes per `Feed` — budget for 10K stories max in memory
- **Knowledge graph**: Nodes should be lazily loaded; full graph materialization only during background processing
- **Parsing buffers**: XML parser should stream, never load entire feed XML into a single `String`

### SPM Benchmark Tests

For algorithmic changes to the core library, add benchmark assertions:

```swift
import XCTest

func testKeywordExtractionPerformance() {
    let longArticle = String(repeating: "sample text with various keywords ", count: 1000)
    measure {
        _ = KeywordExtractor.extract(from: longArticle, maxKeywords: 10)
    }
}

func testFeedParsingPerformance() throws {
    let largeFeed = try loadFixture("large_feed_500_items.xml")
    measure {
        _ = RSSParser.parse(data: largeFeed)
    }
}
```

**Performance regression rule**: If your `measure {}` block is >20% slower than the baseline on the same hardware, investigate before submitting. Document any intentional trade-offs (e.g., "parsing is 15% slower but memory usage drops 40%").

### Network Performance

- Use `URLSession` metrics (`task.metrics`) to verify no redundant redirects or TLS renegotiations
- Feed refresh should use conditional GET (`If-Modified-Since` / `ETag`) — verify with Charles Proxy or `nscurl`
- Image downloads must respect `Cache-Control` headers; don't re-download cached images

## Debugging Common Issues

### Build Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No such module 'UIKit'` in SPM build | SPM targets can't use UIKit | Move UIKit code to `FeedReader/`, keep `Sources/FeedReaderCore/` platform-independent |
| `NSKeyedUnarchiver` crash on launch | `Story` model changed without migration | Delete the app from simulator (Cmd+Shift+H → long press → Remove), or reset simulator (Device → Erase All Content) |
| Storyboard segue crash | Identifier mismatch | Verify `"ShowDetail"` identifier in `Main.storyboard` matches `prepare(for:sender:)` |
| Tests fail with `canOpenURL` error | `UIApplication` unavailable in test host | Mock URL validation instead of calling `UIApplication.shared` directly |
| `swift build` succeeds but `xcodebuild` fails | Xcode project references differ from `Package.swift` | Ensure new files are added to both the Xcode project and `Package.swift` sources |

### Network & Feed Issues

- **No stories appearing**: Check `Reachability.swift` — the BBC feed URL may have changed or be geo-blocked. Try a different RSS source temporarily.
- **Images not loading**: `ImageCache` uses `NSCache` which evicts under memory pressure. Verify the image URL returns valid data with `curl`.
- **Stale cached data**: NSCoding archives are in the app's documents directory. Clear with `FileManager.default.removeItem(at: archivePath)`.

### Running Tests Without Xcode

The SPM test suite runs on any macOS or Linux machine with Swift installed:

```bash
# macOS (no Xcode project needed)
swift test --parallel

# Linux (Docker)
docker build -t feedreader . && docker run feedreader swift test
```

For iOS-specific tests (anything in `FeedReaderTests/`), you need Xcode and a simulator.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior via the repository's issue tracker or by contacting the maintainer directly.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

Questions? Open a discussion or reach out via an issue. Happy coding! 🚀
