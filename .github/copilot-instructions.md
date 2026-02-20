# Copilot Instructions for FeedReader

## Project Overview

FeedReader is an iOS RSS feed reader app built with Swift and UIKit. It fetches and displays news articles from BBC News RSS feeds, with offline support via NSCoding persistence.

## Architecture

- **UIKit + Storyboard**: The app uses `Main.storyboard` for the UI layout with a `UINavigationController` → `StoryTableViewController` → `StoryViewController` flow.
- **MVC pattern**: Models in `Story.swift`, views in storyboard + `StoryTableViewCell.swift`, controllers in `StoryTableViewController.swift` and `StoryViewController.swift`.
- **XML parsing**: RSS feeds are parsed using Foundation's `XMLParser` (delegate pattern in `StoryTableViewController`).
- **Network checking**: `Reachability.swift` uses `SCNetworkReachability` to detect connectivity.

## Key Files

| File | Purpose |
|------|---------|
| `FeedReader/Story.swift` | Data model — `NSObject` + `NSCoding` for archiving |
| `FeedReader/StoryTableViewController.swift` | Main feed list — RSS parsing, image caching, table view |
| `FeedReader/StoryViewController.swift` | Story detail view — shows title, description, bookmark/share, and Safari link |
| `FeedReader/StoryTableViewCell.swift` | Custom table cell with title, description, thumbnail |
| `FeedReader/Reachability.swift` | Network connectivity check |
| `FeedReader/BookmarkManager.swift` | Singleton bookmark persistence — add/remove/toggle with `NSSecureCoding` |
| `FeedReader/BookmarksViewController.swift` | Bookmarks list — swipe-to-delete, empty state, clear all |
| `FeedReader/NoInternetFoundViewController.swift` | Offline fallback screen with retry button |
| `FeedReader/AppDelegate.swift` | App lifecycle (minimal) |
| `FeedReader/Base.lproj/Main.storyboard` | UI layout |

## Building

```bash
# Build (no code signing for CI)
xcodebuild build \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

## Testing

```bash
# Run unit tests
xcodebuild test \
  -project FeedReader.xcodeproj \
  -scheme FeedReader \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -configuration Debug \
  -enableCodeCoverage YES \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

### Code Coverage

Code coverage is enabled in the Xcode scheme and CI workflow:

- **Xcode scheme**: `codeCoverageEnabled = "YES"` in `FeedReader.xcscheme`
- **CI**: The `build-and-test` job passes `-enableCodeCoverage YES` to `xcodebuild test`
- **SPM**: The `spm-test` job runs `swift test --enable-code-coverage` for the `FeedReaderCore` package
- **Reports**: Coverage JSON and human-readable summaries are uploaded as CI artifacts
- **xccov**: Use `xcrun xccov view --report --json <archive>` to inspect coverage locally

To view coverage locally after running tests:
```bash
# After xcodebuild test with -enableCodeCoverage YES -resultBundlePath TestResults
xcrun xccov view --report --json TestResults/*.xccovarchive
```

Test files are in `FeedReaderTests/`:
- `BookmarkTests.swift` — Bookmark manager tests (20 cases: add, remove, toggle, persistence, clear)
- `SearchFilterTests.swift` — Search and filter tests
- `StoryTests.swift` — Story model initialization tests
- `StoryModelTests.swift` — Extended model tests (edge cases, encoding, equality)
- `XMLParserTests.swift` — RSS XML parsing tests with fixture files
- `ViewControllerTests.swift` — View controller lifecycle tests

Test fixtures: `storiesTest.xml`, `multiStoriesTest.xml`, `malformedStoriesTest.xml`

## Conventions

- **Swift version**: Swift 5+ (targets iOS 13+)
- **No external dependencies**: Pure Foundation/UIKit, no CocoaPods or SPM packages
- **Image caching**: Uses `NSCache` (in-memory) for thumbnails
- **Offline support**: Stories are archived to disk via `NSKeyedArchiver`/`NSKeyedUnarchiver`
- **RSS source**: BBC News World (`https://feeds.bbci.co.uk/news/world/rss.xml`)

## Common Patterns

- Network requests use `URLSession.shared.dataTask` with `[weak self]` capture
- UI updates are dispatched to the main thread via `DispatchQueue.main.async`
- XML parsing uses the delegate pattern (`XMLParserDelegate`)
- `Story` init is failable (`init?`) — returns nil if title/body empty or link invalid

## What to Watch Out For

- `UIApplication.shared.canOpenURL` is used for link validation — this requires the app context (won't work in pure unit tests without mocking)
- Storyboard segues use identifier `"ShowDetail"` — don't change without updating `prepare(for:sender:)`
- The `Reachability` class uses low-level C interop (`SCNetworkReachability`) — be careful with pointer/memory operations
- `NSCoding` is used for persistence — adding new properties to `Story` requires updating both `encode(with:)` and `init?(coder:)`

## Security Considerations

This app processes untrusted RSS feed data. Key security measures to maintain:

- **URL scheme validation**: `Story.isSafeURL()` only allows `https`/`http` — never bypass this for links or images
- **HTML sanitization**: `Story.stripHTML()` removes all HTML from descriptions — keep this in the init path
- **NSSecureCoding**: `Story` uses secure deserialization — always use typed `decodeObject(of:forKey:)` methods
- **Failable init**: `Story.init?()` rejects empty titles, empty bodies, and unsafe link URLs — don't make it non-failable

See `SECURITY.md` for the full threat model and security policy.
