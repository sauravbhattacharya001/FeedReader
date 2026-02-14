# Changelog

All notable changes to FeedReader are documented in this file.

## [v1.0.0] — 2026-02-14

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
