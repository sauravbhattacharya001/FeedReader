# Contributing to FeedReader

Thank you for considering contributing to FeedReader! Whether it's a bug fix, new feature, documentation improvement, or test — all contributions are welcome.

## Table of Contents

- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Reporting Issues](#reporting-issues)
- [Code of Conduct](#code-of-conduct)

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
├── FeedReader/                      # iOS app (150+ Swift files)
│   ├── AppDelegate.swift            # App lifecycle
│   ├── RSSFeedParser.swift          # Original XML parser
│   ├── Story.swift / Feed.swift     # App data models
│   ├── FeedManager.swift            # Multi-feed management
│   ├── BookmarkManager.swift        # Bookmark persistence (NSCoding)
│   ├── ImageCache.swift             # Async image loading + NSCache
│   ├── Reachability.swift           # Network connectivity
│   ├── Article*.swift               # Article analysis, export, quiz, etc.
│   ├── Feed*.swift                  # Feed health, autopilot, serendipity, etc.
│   ├── *ViewController.swift        # UIKit view controllers
│   └── Base.lproj/                  # Storyboards
│
├── Sources/FeedReaderCore/          # SPM library (platform-independent core)
│   ├── RSSParser.swift              # Standalone RSS parser
│   ├── FeedItem.swift / RSSStory.swift  # Core models
│   ├── FeedCacheManager.swift       # Feed caching
│   ├── FeedHealthMonitor.swift      # Feed health tracking
│   ├── KeywordExtractor.swift       # Text analysis
│   ├── TextUtilities.swift          # String helpers
│   ├── OPMLManager.swift            # OPML import/export
│   └── ArticleArchiveExporter.swift # Archive export
│
├── FeedReaderTests/                 # XCTest suite for the iOS app (107 test files)
├── Tests/FeedReaderCoreTests/       # XCTest suite for the SPM library
├── docs/                            # Generated documentation
├── Package.swift                    # SPM manifest (swift-tools-version:5.9)
├── FeedReaderCore.podspec           # CocoaPods spec
└── Dockerfile                       # Docker build environment
```

**Key distinction:** `FeedReader/` is the full iOS app with UIKit. `Sources/FeedReaderCore/` is the headless core library distributed via SPM and CocoaPods — it has no UIKit dependency and can be used in any Swift project.

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

## Making Changes

1. **Create a feature branch** from `master`:
   ```bash
   git checkout -b feature/my-improvement
   ```

2. **Make your changes** in small, logical commits.

3. **Test thoroughly** (see [Testing](#testing) below).

4. **Commit** with a clear message:
   ```bash
   git commit -m "Add swipe-to-delete for bookmarks
   
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

## Code of Conduct

Be respectful and constructive. We're all here to build something useful. Harassment, trolling, and unconstructive criticism won't be tolerated.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

Questions? Open a discussion or reach out via an issue. Happy coding! 🚀
