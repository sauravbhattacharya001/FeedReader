# Changelog

All notable changes to FeedReader are documented in this file.

This file is now backfilled to track every published GitHub release. For the
canonical, signed release notes (with asset checksums and `Full Changelog`
links), see https://github.com/sauravbhattacharya001/FeedReader/releases.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **FeedReadingPaceAnalyzer** — on-device reading pace analytics engine.
  Tracks words-per-minute across sessions, classifies pace (skimming/fast/
  normal/slow/deep-reading), detects 6 anomaly types (rushing long content,
  dwelling on short content, pace spikes, pace drops, fatigue patterns,
  topic struggles), builds per-topic and per-feed pace profiles with
  median/average/fastest/slowest WPM, generates time-window trends
  (7-day/30-day with direction detection), provides personalized reading
  time estimates for unseen articles (topic > feed > global > default
  fallback chain), emits P0-P3 prioritized recommendations, A-F grading,
  and structured insights. Injectable clock for deterministic testing.
  31 XCTest cases.

- **FeedReadingStreakEngine** — gamification engine for reading habits:
  reading streaks (current/longest/active detection), 30+ unlockable
  achievements across 6 categories (streak, volume, diversity, speed,
  dedication, exploration), tiered progression (bronze→diamond),
  XP system, milestone tracking with next-milestone projection,
  motivational nudges (streak-at-risk, milestone-close, celebrate,
  come-back, challenge), special badges (Night Owl, Early Bird,
  Weekend Warrior), new-unlock detection API for real-time toast
  notifications, injectable clock for testability. 28 XCTest cases.

## [v1.14.0] — 2026-05-20 — Reader-Fatigue Advisor & Performance Hygiene Wave

Twelve commits since v1.13.0. This release adds a new agentic advisor that
watches the *human reader* (not the feed) for burnout signals, tightens two
O(N²) hot paths in the cross-reference and serendipity engines, fuses the
word-frequency tokenization loop, hardens CI YAML and the coverage report,
expands publishable XCTest coverage and modernizes the issue-template set.

### Added

- **FeedReadingFatigueAdvisor** — agentic advisor that watches the human
  reader's cognitive load over recent reading sessions. 10 weighted
  fatigue signals (volume, depth, diversity, sentiment, timing,
  continuity), 0–100 composite fatigue score, A–F grade, 5-tier verdict
  ladder (`fresh` → `engaged` → `mildFatigue` → `heavyFatigue` →
  `burnout`), deduped P0-first playbook with blast-radius and
  reversibility, cautious/balanced/aggressive risk-appetite knob,
  deterministic given a fixed `now` closure, text / markdown /
  byte-stable JSON renderers.
- **FeedSerendipityEngine XCTest suite** — covers scoring, novelty decay
  and JSON export.
- **Issue templates** — accessibility, feed-compatibility, and
  good-first-issue templates added; modernized `config.yml`.
- **Pull-request runbook** — `PUBLISHING.md` expanded with checklists,
  recovery procedures and per-job CI semantics.

### Performance

- **FeedSerendipityEngine** — hoisted `Set` construction out of the
  O(N²) `discover` loop so the per-iteration overhead drops from
  O(N) set-build to O(1) membership test.
- **FeedCrossReferenceEngine** — precomputed keyword sets and negation
  flags once per article in the O(N²) matcher / clusterer loops,
  eliminating redundant tokenization on every pair.
- **TextUtilities** — fused `computeWordFrequencies` tokenization and
  counting into a single pass; removes one full string traversal per
  call.

### Fixed

- **CI** — repaired a YAML parse error in the `List available simulators`
  step that was failing the iOS pipeline.

### Documentation

- **FeedNarrativeArcTracker** — replaced sparse trailing comments on the
  public surface with proper `///` doc comments so Xcode Quick Help,
  DocC and SourceKit-LSP can surface them. Covers `NarrativePhase`,
  `TurningPointType`, `NarrativeArticle`, `NarrativeThread`,
  `NarrativeTurningPoint`, `NarrativeConvergence`, `NarrativeForecast`,
  `NarrativeReport`, and the public `FeedNarrativeArcTracker` surface
  (`followStory`, `unfollowStory`, `getStories(...)`, `analyze`,
  `storyCount`, `articleCount`, `reset`).
- **FeedPredictiveInterestEngine** — `///` doc comments added across the
  public API.
- **ArticleDigestComposer** — `///` doc comments expanded across the
  public API.

### CI / Tooling

- **Coverage report** — extracted inline Python heredocs from the
  coverage CI step into `scripts/coverage_report.py` so the script is
  diff-reviewable, locally runnable, and lintable.

### Notes for Adopters

This release is **API-additive only**. The new
`FeedReadingFatigueAdvisor` and its supporting `ReadingSession`,
`FatigueVerdict`, `FatigueSignal`, `FatigueAction`, `FatiguePriority`,
`FatigueRiskAppetite`, `FatigueFinding`, `FatiguePlaybookItem`, and
`FatigueReport` types are net-new. No public signatures were renamed or
removed; the SPM `from: "1.13.0"` floor is sufficient for adopters who
don't need the new advisor.

## [v1.13.0] — 2026-05-17 — Cross-Reference, Predictive & Hygiene Wave

Fifty-one commits since v1.12.0. This release adds 13 new autonomous reading
intelligence engines, fixes a long-standing Atom feed bug, hardens HTML and
OPML attack surface, removes wasted regex recompilations from hot paths, and
lands several new test suites.

### Added — Autonomous Intelligence Engines

- **FeedRelevanceDecayEngine** — tracks how article relevance fades over time
  and surfaces stale-but-still-saved items.
- **FeedPredictiveInterestEngine** — predicts future topic interest from
  reading trajectory.
- **FeedBlindSpotDetector** — flags knowledge gaps the user is consistently
  not reading.
- **FeedTopicRadar** — autonomous emerging-topic detection across active feeds.
- **FeedSubscriptionROI** — value analysis per subscribed feed (read-through,
  save rate, time-spent vs cost).
- **FeedCrossReferenceEngine** — cross-article fact corroboration and
  contradiction detection across sources.
- **FeedTemporalOptimizer** — publishing-pattern analysis and best read-time
  recommendations.
- **FeedNarrativeArcTracker** — multi-article storyline arc detection.
- **Feed Knowledge Graph** — personal knowledge graph builder linking
  entities, topics, and read articles.
- **Feed Source Credibility Engine** — autonomous trust profiling for RSS
  sources, complementing the static SourceCredibilityScorer.
- **Feed Editorial Drift Compass** — detects editorial-tone shifts within a
  single source over time.
- **FeedAttentionAllocator** — daily attention-budget manager across feeds.
- **PR size labeler** workflow + expanded auto-labeling coverage.

### Fixed

- **RSSParser** — repaired broken Atom `<link rel="alternate">` extraction
  that was dropping the canonical article URL for many Atom feeds.
- **ArticleReactionManager** — fixed a data race by moving to a concurrent
  queue for thread-safe reaction state.

### Security

- **XSS (CWE-79)** — added single-quote escaping to `htmlEscaped` across 7
  files that render user / feed content into HTML.
- **SSRF (CWE-918)** — hardened OPML URL-based import with destination
  validation, plus added size guards on automation and annotation import
  paths to bound memory.
- **Path traversal (CWE-22)** — fixed `FeedBackupManager` so backup file
  paths cannot escape the backup directory.

### Performance

- **Hoisted regex compilation** — six `NSRegularExpression` instances in
  `FeedTimelineReconstructor`, `FeedCrossReferenceEngine`, and
  `ArticleFactChecker` are now compiled once as `static let` instead of
  being rebuilt on every call. NSRegularExpression is thread-safe for
  matching, so this is a pure win in CPU and Foundation allocations under
  batch article ingest.
- **ArticleDeduplicator** — O(1) indexed duplicate-group lookups plus a
  length-based early-reject in the dedup scan.
- **FeedSourceDiversityAuditor** — O(E) pre-bucketed event counts in
  `computeConsistency`.

### Refactored

- **FeedPrivacyGuard** — unified pattern detection rules and extracted a
  shared scan-aggregation helper.

### Tests

- **FeedReaderCore TextUtilities & ArticleDigestComposer** — comprehensive
  unit coverage for the shared text utilities and the digest composer.
- **FeedDebateArena + ArticleDigestComposer** — 57 tests.
- **FeedAnomalyDetector** — 44 tests covering anomaly detection, trust
  scoring, and persistence.
- **FeedContentCalendar + FeedCacheManager** — 65 SPM tests.
- **ArticleEngagementPredictor** — 25 tests.

### Docs & CI

- **CHANGELOG backfill** — every release from v1.4.0 through v1.12.0 is now
  documented in this file.
- **Reader Intelligence**, **Feed Intelligence & Hygiene**, and
  **Autonomous Intelligence** documentation pages added.
- **copilot-instructions.md** rewritten for the full 163-file codebase.
- **CONTRIBUTING.md** — expanded with module catalog, test coverage gaps,
  and a new Performance Profiling section.
- **CODE_OF_CONDUCT.md** added.
- **CI** — automated package publishing workflow (SPM + CocoaPods),
  CodeQL path filters with concurrency and `upload: always` SARIF, stale
  issue/PR bot, SPM caching, job timeouts, and permissions hardening.
- **Badges** — stale issues, SPM compatible, contributors, dependabot.

Full diff: https://github.com/sauravbhattacharya001/FeedReader/compare/v1.12.0...v1.13.0

## [v1.12.0] — 2026-04-27

### Tests

- **SourceCredibilityScorer test suite** — 35 tests covering domain extraction,
  tier scoring, clickbait / capitalization / punctuation heuristics, author
  attribution, correction notices, disclosure detection, sourcing & hedging
  analysis, `.gov` / `.edu` scoring bonus, suspicious-domain patterns, score
  clamping, `Codable` round-trip, moderate-domain handling, and edge cases.

## [v1.11.0] — 2026-04-27 — Autonomous Intelligence Suite

### Added (12 new autonomous modules)

- **FeedPredictiveAlerts** — proactive content-monitoring alert engine
- **FeedTimelineReconstructor** — chronological event timeline reconstruction
- **FeedSerendipityEngine** — serendipitous article discovery beyond habits
- **FeedCuriosityEngine** — curiosity-driven exploration of unexpected topics
- **FeedForgettingCurve** — spaced-repetition memory retention tracker
- **FeedImpactTracker** — article impact tracking & measurement over time
- **FeedDebateArena** — argument extraction & debate visualization
- **FeedAnomalyDetector** — anomaly detection for unusual feed behaviour
- **FeedReadingCoach** — personal reading coach with adaptive recommendations
- **FeedInboxZero** — autonomous inbox-zero strategy for feed triage
- **FeedContentCalendar** — publication-pattern detection & scheduling insights
- **FeedSourceDiversityAuditor** — echo-chamber detection & diversity auditing

### Performance

- O(E) pre-bucketed event counts in `computeConsistency` — eliminates
  per-query linear scans.
- O(1) indexed duplicate-group lookups + length-based early reject in
  `ArticleDeduplicator.scan()`.
- Single-pass tokenizer in `SentimentRadar` — eliminates redundant title
  re-tokenization.
- Cached `normalizedURL` and deduplicated `uniqued()` in `ArticleDeduplicator`.
- Eliminated array allocations in `FeedTrendForecaster` momentum computation.

### Security

- **Path traversal fix in `FeedBackupManager` (CWE-22)** — user-supplied
  paths are now validated against the backup root.

### Refactoring

- Unified pattern-detection rules and extracted shared scan aggregation in
  `FeedPrivacyGuard`.
- Replaced inline `JSONEncoder` / `JSONDecoder` with a shared `JSONCoding`
  instance and `UserDefaultsCodableStore`.
- Deduplicated `escapeHTML` into a shared `String.htmlEscaped` extension.

### Code Quality

- Replaced 22 raw `print()` calls across 14 files with privacy-aware
  `os_log` via `FeedReaderLogger` (CWE-532 prevention).

### Documentation

- Added `CODE_OF_CONDUCT.md` and expanded `CONTRIBUTING.md` with a
  first-time contributor section.
- New Autonomous Intelligence documentation page covering 11 features.
- Added a changelog page to the GitHub Pages site.

### Tests

- 25 new tests for `ArticleEngagementPredictor` (cold start, scoring, FIFO
  trimming, model retraining, analytics, classification).

## [v1.10.0] — 2026-04-21

### Added

- **FeedSignalBooster** — autonomous cross-feed trending-topic detector that
  surfaces emerging themes across all subscribed feeds.
- **SmartUnsubscriber** — autonomous feed-subscription hygiene that flags
  stale or low-engagement feeds and suggests cleanup actions.

## [v1.9.0] — 2026-04-20

### Added

- **FeedSerendipityEngine** — autonomous serendipity discovery that surfaces
  unexpected but relevant content across feeds.
- **FeedAutopilot** — autonomous reading-queue curator that learns reading
  preferences and adapts to your habits.
- **FeedNarrativeTracker** — cross-feed story narrative tracking with
  evolution detection for developing stories.
- **Feed Health Dashboard** — interactive feed-monitoring UI for real-time
  feed status and diagnostics.
- **ArticleDigestComposer** — newsletter-style digest generator for curated
  article summaries.
- **ArticleFlashcardGenerator** — SM-2 spaced-repetition flashcard system.

### Performance

- Replaced O(n²) string concatenation with fragment buffering in the RSS
  parser.
- Debounced `FeedCacheManager` disk writes during bulk refresh.

### Security

- Sanitized `customCSS` in `ArticleArchiveExporter` to prevent XSS
  injection.
- Added `Content-Type` validation before XML parsing to reject non-XML
  responses (e.g., redirected HTML error/login pages) early.

### Refactoring & Cleanup

- Extracted shared `TextUtilities` to centralize word frequency, stop
  words, and escape functions.
- Added O(1) rule lookup index to `FeedAutomationEngine`.
- Migrated `FeedBackupManager` to CryptoKit; consolidated stop-words.

### CI / CD

- Added SPM build & test steps to `copilot-setup-steps.yml`.
- Added dependency grouping to the Dependabot config.
- Fixed duplicate coverage threshold and added a job summary.

## [v1.8.0] — 2026-04-09

### Added

- **Feed Health Dashboard** — interactive feed-monitoring UI for at-a-glance
  feed status.
- **ArticleDigestComposer** — newsletter-style digest generator.
- **ArticleFlashcardGenerator** — SM-2 spaced-repetition flashcards for
  learning from articles.

### Security

- Sanitized `customCSS` in `ArticleArchiveExporter` to prevent XSS
  injection.

### Fixed

- Added `Content-Type` validation before XML parsing to reject non-XML
  responses early.
- Removed a duplicate coverage threshold in CI; added a CI job summary.

### Refactoring

- Added O(1) rule lookup index to `FeedAutomationEngine` for faster
  automation matching.
- Centralized word-frequency computation in `TextUtilities`.
- Extracted shared `TextUtilities` to eliminate duplicated stop words,
  escape functions, and word counting.

## [v1.7.0] — 2026-04-03

### Added

- **ArticleFlashcardGenerator** — SM-2 spaced-repetition flashcard system
  for active recall from articles.
- **ArticleFactChecker** — heuristic claim extraction and verifiability
  analysis.
- **ArticleQuizGenerator** — comprehension quiz engine for active reading.
- **ArticleReadingListSharer** — curate and share reading lists as HTML,
  Markdown, JSON, or OPML.
- **ArticleTimeCapsule** — bury articles for future resurfacing with
  preset durations, reflections, tags, stats, and export.
- **Reading Bingo** — gamified 5×5 bingo card with reading challenges.
- **ReadingPaceCalculator** — queue completion forecasting and pace
  analysis.
- **ArticleSummarizer** & **ArticleSummaryGenerator** — TF-IDF extractive
  text summarization.
- **RSVP Speed Reading** — rapid serial visual presentation mode
  (`ArticleSpeedReadPresenter`).

### Performance

- HTTP conditional GET caching (ETag / Last-Modified) for RSS feeds —
  reduces bandwidth on unchanged feeds.
- Enum dispatch replaces string comparisons in the RSS parser for faster
  feed parsing.

### Refactoring

- Extracted shared `TextUtilities` to eliminate duplicated stop words,
  escape functions, and word counting across modules.
- Centralized word-frequency computation in `TextUtilities`.
- Fixed triple-declared `storyStore` property and typo in
  `StoryTableViewController`.
- Reduced code duplication in `ReadingDataExporter` import methods.

### Tests

- Comprehensive test suite for `KeywordExtractor`.

## [v1.6.0] — 2026-03-31

### Added

- **FeedWeatherReporter 🌦️** — weather-metaphor analytics for feed
  activity. Analyzes feed-update patterns and presents activity levels
  using intuitive weather analogies (sunny = active, stormy = very
  active, calm = quiet), useful for quickly gauging feed health and
  engagement at a glance.

## [v1.5.0] — 2026-03-30

### Added

- **Smart Feed Mixer** — blend articles from multiple feeds with
  customizable ratios.
- **Article Word Count Tracker** — reading-volume analytics across feeds.
- **Bookmark Folder Manager** — organize bookmarks into named folders.
- **Feed Burnout Detector** — detect information overload and reading
  burnout patterns.
- **Feed Rating Manager** — rate feeds on a 1–5 star scale.
- **Article Paywall Detector** — identify paywalled articles before
  opening.
- **Feed Engagement Scoreboard** — track and rank feed-engagement
  metrics.
- **Article Quiz Generator** — auto-generate quizzes from article
  content.

### Performance

- Optimized Levenshtein distance with two-row DP and early termination.

### Security

- Sanitized `font-family` CSS to prevent injection (CWE-79).

### Refactoring

- Single-pass XML escaping in `OPMLManager`.

### Fixed

- Offline-cache oversized-article drain.
- Recommendation read-count calculation.
- SSRF TEST-NET range validation.
- Double sanitization in `Story.init`.
- Duplicate `FeedHealthStatus` enum.
- Added `FeedComparisonManager` tests.

## [v1.4.0] — 2026-03-29

### Added

- **Feed Engagement Scoreboard** — track and visualize engagement across
  feeds.
- **Article Quiz Generator** — auto-generate quizzes from article content.
- **Vocabulary Frequency Profiler** — analyze word-frequency patterns.
- **Word Cloud Generator** — visual word clouds from articles.
- **Article Dark Mode Formatter** — proper dark-mode rendering for
  articles.
- **Article Flashback (On This Day)** — resurface articles from past
  dates.
- **Article Comparison View** — side-by-side article analysis.

### Security

- Sanitized export filenames to prevent path traversal (CWE-22).
- Replaced `print()` with `os_log` and removed force casts.
- Allowlisted UserDefaults keys in backup restore.
- Validated feed URLs against the SSRF filter at fetch time.
- Replaced raw `NSKeyedArchiver` with `SecureCodingStore`.

### Fixed

- ISO week numbering in `DateFormatting.yearWeek`.
- Prevented negative cache size and debounced history persistence.
- Fixed `estimatedTimeToEmpty` for queues with short articles.
- Removed duplicate `FeedHealthStatus` enum in
  `FeedPerformanceAnalyzer`.
- Prevented double HTML sanitization in the `Story` `NSCoding` path.
- Narrowed TEST-NET SSRF checks to the correct /24 ranges.
- Used actual article count in recommendation reason.
- Rejected oversized articles in `OfflineCacheManager`.
- Applied IQR outlier filtering to speed trends.
- Clamped negative article counts in the scheduler.

### Performance

- Single-pass snapshot aggregation in `ArticleTrendDetector`.

### Refactoring

- Consolidated duplicate stop-word lists into `TextAnalyzer`.
- Removed duplicate `ArticleSummaryGenerator`.
- Used `SecureCodingStore` for story persistence.
- Extracted toast helper to an extension.

### Tests & CI

- Comprehensive tests for `FeedComparisonManager` and
  `ArticleLinkExtractor`.
- Enforced code-coverage thresholds in CI and Codecov.

### Docs

- Added Swift docstrings to `ContentFilter` and
  `BookmarksViewController`.
- Added a table of contents and quick-start section to the README.

## [v1.3.0] — 2026-02-19

### Read/Unread Tracking

- **Auto-mark as read** — Stories are automatically marked as read when tapped or when navigating to detail view
- **Blue dot indicator** — Unread stories display a blue dot on the left edge of the cell
- **Visual dimming** — Read stories appear slightly dimmed (lower opacity) for quick visual scanning
- **Unread count in title** — Navigation bar shows "(X unread)" when unread stories exist
- **Segmented filter** — All/Unread/Read filter with live counts in the table header
- **Mark All Read** — ✓ checkmark button in nav bar to mark all stories as read with confirmation dialog
- **Swipe to toggle** — Swipe left on any story to toggle read/unread status (envelope icon)
- **Persistent storage** — Read status persisted via UserDefaults with automatic pruning (max 5,000 links)
- **Efficient lookups** — O(1) read status checks via Set-based index
- **Change notifications** — `.readStatusDidChange` notification for reactive UI updates
- **42 new tests** — ReadStatusManager (mark read/unread, toggle, filter, count, persistence, notifications, edge cases, ReadFilter enum)

## [v1.2.0] — 2026-02-15

### Multi-Feed Support

- **Feed Manager** — New feed management screen accessible via 📡 antenna icon in the navigation bar
- **10 built-in presets** — BBC World News, BBC Technology, BBC Science, BBC Business, NPR News, Reuters World, TechCrunch, Ars Technica, Hacker News, The Verge
- **Custom feeds** — Add any RSS/Atom feed by URL with validation
- **Feed toggling** — Enable/disable individual feeds without removing them
- **Feed reordering** — Drag-to-reorder feeds in edit mode
- **Swipe to remove** — Remove feeds with swipe-to-delete
- **Multi-feed aggregation** — Stories from all enabled feeds are merged with duplicate detection (by link URL)
- **Persistent storage** — Feed configuration persisted via NSSecureCoding
- **Dynamic title** — Navigation bar shows active/total feed count
- **35 new tests** — Feed model (NSCoding, equality, presets) and FeedManager (CRUD, toggle, reorder, custom URL validation, reset)

## [v1.1.0] — 2026-02-14

### Bookmarks & Search

### Initial stable release

A native iOS RSS feed reader with offline caching, async image loading, and network-aware UI.

### Features

- **RSS feed parsing** — `XMLParser`-based RSS/XML feed reader, currently configured for BBC World News
- **Offline caching** — Stories persisted via `NSCoding` / `NSKeyedArchiver` for offline reading
- **Network detection** — `SCNetworkReachability`-based connectivity checks with dedicated offline UI
- **Async image loading** — Story thumbnails load on background threads with `NSCache` in-memory cache
- **Detail view** — Tap any story for full description with link to original article in Safari
- **Smart refresh** — Avoids redundant network fetches on back-navigation from detail view

### Bug Fixes (pre-release history)

- Fixed force-unwrap crashes on malformed feed data (#3)
- Moved RSS feed fetching off main thread to prevent UI freezes (#4)
- Fixed dead image-loading code — thumbnails now load from URL (#5)
- Replaced deprecated Reuters RSS feed with BBC News (#6)
- Added `NSCache`-based image caching to prevent redundant requests on scroll (#7)
- Fixed redundant feed reload on back-navigation (#8)

### Infrastructure

- CI workflow for iOS build, test, and lint (GitHub Actions)
- Docker build/push workflow
- Comprehensive unit tests for model, XML parser, and view controllers
- GitHub Copilot agent setup for autonomous issue/PR work
- MIT license

### Security & Quality

- Replaced all force-unwraps with safe guard-let patterns
- Migrated deprecated APIs (`NSKeyedArchiver`, `UIApplication.openURL`)
- Switched to HTTPS for all network requests
- Safe decoding in `Story.init(coder:)` to prevent crashes on corrupted archives
- Removed dead code and tracked user data

[v1.12.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.12.0
[v1.11.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.11.0
[v1.10.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.10.0
[v1.9.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.9.0
[v1.8.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.8.0
[v1.7.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.7.0
[v1.6.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.6.0
[v1.5.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.5.0
[v1.4.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.4.0
[v1.3.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.3.0
[v1.2.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.2.0
[v1.1.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.1.0
[v1.0.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.0.0
