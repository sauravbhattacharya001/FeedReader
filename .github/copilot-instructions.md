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
| `FeedReader/StoryViewController.swift` | Story detail view — loads article in `WKWebView` |
| `FeedReader/StoryTableViewCell.swift` | Custom table cell with title, description, thumbnail |
| `FeedReader/Reachability.swift` | Network connectivity check |
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
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Test files are in `FeedReaderTests/`:
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
