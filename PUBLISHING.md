# Publishing FeedReaderCore

FeedReaderCore is distributed via **Swift Package Manager** and **CocoaPods**.

## Automated Publishing

The `.github/workflows/publish.yml` workflow runs automatically on version tags:

```bash
git tag v1.3.0
git push origin v1.3.0
```

This triggers:
1. **SPM validation** — builds and tests on macOS and Linux
2. **Podspec validation** — `pod lib lint`
3. **CocoaPods Trunk push** — publishes to the CocoaPods registry
4. **Swift Package Index** notification

## Setup Required

### CocoaPods Trunk Token

To enable automated CocoaPods publishing:

1. Register with CocoaPods Trunk (one-time):
   ```bash
   pod trunk register online.saurav@gmail.com 'Saurav Bhattacharya'
   ```

2. Get your session token:
   ```bash
   cat ~/.netrc | grep -A2 trunk.cocoapods.org
   ```

3. Add the token as a GitHub repository secret:
   - Go to Settings → Secrets and variables → Actions
   - Add `COCOAPODS_TRUNK_TOKEN` with your token value

### Swift Package Index

No setup needed. [Swift Package Index](https://swiftpackageindex.com) automatically discovers tagged releases from public GitHub repositories. To register your package:

1. Visit https://swiftpackageindex.com/add-a-package
2. Submit `https://github.com/sauravbhattacharya001/FeedReader`

## Consumer Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/sauravbhattacharya001/FeedReader.git", from: "1.2.0")
]
```

### CocoaPods

```ruby
pod 'FeedReaderCore', '~> 1.2.0'
```

## Versioning

Follow [Semantic Versioning](https://semver.org/):
- **Patch** (1.2.x): Bug fixes, no API changes
- **Minor** (1.x.0): New features, backward compatible
- **Major** (x.0.0): Breaking API changes

Always update the podspec version to match the git tag. The publish workflow does this automatically.
