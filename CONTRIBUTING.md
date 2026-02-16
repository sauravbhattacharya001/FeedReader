# Contributing to FeedReader

Thank you for considering contributing to FeedReader! Whether it's a bug fix, new feature, documentation improvement, or test — all contributions are welcome.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Architecture Overview](#architecture-overview)
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
3. **Open** the project in Xcode:
   ```bash
   open FeedReader.xcodeproj
   ```
4. **Build and run** on a simulator (Cmd+R) to verify everything works.

## Development Setup

### Requirements

- **Xcode 8+** (Swift 3 codebase)
- **iOS 10+** Simulator or device
- **macOS** with Xcode Command Line Tools installed

### No External Dependencies

FeedReader uses zero third-party libraries. Everything is built with Apple frameworks:
- `Foundation` / `UIKit` — core UI and data
- `XMLParser` — RSS feed parsing
- `NSCache` / `NSCoding` — caching and persistence
- `SystemConfiguration` — network reachability

No CocoaPods, Carthage, or SPM setup needed.

## Architecture Overview

The project follows a straightforward MVC pattern:

```
FeedReader/
├── AppDelegate.swift                 # App lifecycle
├── RSSFeedParser.swift               # XML parsing for RSS feeds
├── Story.swift                       # Story data model (NSCoding)
├── Feed.swift                        # Feed source model
├── FeedManager.swift                 # Multi-feed source management
├── BookmarkManager.swift             # Bookmark persistence
├── ImageCache.swift                  # Async image loading + NSCache
├── Reachability.swift                # Network connectivity detection
├── StoryTableViewController.swift    # Main feed list (UITableViewController)
├── StoryViewController.swift         # Story detail view
├── StoryTableViewCell.swift          # Custom table cell
├── FeedListViewController.swift      # Feed source management UI
├── BookmarksViewController.swift     # Saved stories UI
├── NoInternetFoundViewController.swift # Offline fallback screen
└── Base.lproj/                       # Storyboards
```

**Key data flows:**
- `RSSFeedParser` fetches and parses XML → produces `[Story]`
- `StoryTableViewController` displays stories, handles search/filter, caching
- `ImageCache` loads thumbnails asynchronously with in-memory caching
- `BookmarkManager` persists bookmarked stories via `NSCoding`
- `FeedManager` manages multiple feed sources with presets and custom URLs

## Coding Standards

### Swift Style

- Follow existing code conventions in the project (Swift 3 style)
- Use `// MARK: -` sections to organize view controller code
- Prefer descriptive variable and method names
- Keep methods focused — one responsibility per method
- Use `guard` for early returns over nested `if` blocks

### Patterns to Follow

- **Delegate pattern** for parser callbacks and view controller communication
- **NSCoding** for persistence (not Codable, since this is Swift 3)
- **NSCache** for in-memory caching (not custom dictionaries)
- **SCNetworkReachability** for network checks (no third-party reachability libraries)

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

3. **Test thoroughly:**
   - Build and run on simulator
   - Test with and without network connectivity
   - Verify offline caching still works
   - Check bookmarks persist across app restarts

4. **Commit** with a clear message:
   ```bash
   git commit -m "Add swipe-to-delete for bookmarks
   
   Implements UITableViewDelegate editingStyle to allow
   removing bookmarks with a swipe gesture."
   ```

## Testing

### Running Tests

```bash
# Via Xcode
Cmd+U

# Via command line
xcodebuild test -project FeedReader.xcodeproj -scheme FeedReader -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Coverage Areas

Tests live in `FeedReaderTests/`. When contributing, consider adding tests for:

- **Model logic** — `Story` encoding/decoding, equality, date handling
- **Feed parsing** — `RSSFeedParser` with various XML inputs
- **BookmarkManager** — add, remove, duplicate handling, persistence
- **ImageCache** — cache hits, cache misses, eviction
- **FeedManager** — feed CRUD, preset feeds, custom URLs

### Manual Testing Checklist

Before submitting a PR, verify:

- [ ] App launches and displays feed stories
- [ ] Pull-to-refresh fetches new stories
- [ ] Stories load correctly when tapping a feed
- [ ] Bookmarking a story works (swipe or button)
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
