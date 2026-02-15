# Changelog

All notable changes to FeedReader are documented in this file.

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

[v1.0.0]: https://github.com/sauravbhattacharya001/FeedReader/releases/tag/v1.0.0
