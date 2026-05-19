# Publishing FeedReaderCore

FeedReaderCore is distributed via **Swift Package Manager** and **CocoaPods**.

This document is the operational runbook: how releases get cut, what the
pipeline validates, what to do when a step fails, and how to recover by
publishing manually if the automation can't.

---

## TL;DR — Cutting a Release

```bash
# 1. Make sure master is green and CHANGELOG.md has an entry for the new version.
# 2. Tag and push.
git tag v1.14.0
git push origin v1.14.0
```

That's it. The `.github/workflows/publish.yml` workflow does the rest:

1. Builds and tests the package on **macOS 14** *and* **Linux** (debug + release).
2. Lints the podspec with `pod lib lint`.
3. Bumps the `s.version` line in `FeedReaderCore.podspec` to match the tag.
4. Pushes the podspec to the CocoaPods Trunk registry.
5. Emits a manifest snapshot so downstream Swift Package Index discovery
   has a clear record.

> The job graph is `validate-spm + validate-podspec → publish-cocoapods` and
> `validate-spm → update-package-registry`, so a Linux build failure or
> macOS test failure aborts the publish before any registry is touched.

---

## Pre-Release Checklist

Run these locally before tagging — they mirror what CI will check, and they
catch the vast majority of release-day surprises:

```bash
# Resolve + build (matches CI's "Resolve dependencies" + "Build (Debug/Release)" steps)
swift package resolve
swift build
swift build -c release

# Run the full SPM test suite (matches "Run tests")
swift test

# Lint the podspec exactly as CI does
pod lib lint FeedReaderCore.podspec --allow-warnings --skip-tests
```

Also confirm:

- [ ] `CHANGELOG.md` has a header for the new version with a meaningful summary.
- [ ] `README.md`'s `from: "x.y.z"` SPM snippet still makes sense for new
      adopters (bump the floor only on intentional API additions, not patches).
- [ ] The tag follows `vMAJOR.MINOR.PATCH` exactly — no `v1.14`, no `1.14.0`.
      The workflow strips the leading `v` to derive the podspec version.
- [ ] No uncommitted changes to `FeedReaderCore.podspec`. CI rewrites the
      `s.version` line at publish time; local edits will be overwritten.

---

## What Each CI Job Actually Does

| Job | Where it runs | What it proves |
|---|---|---|
| `validate-spm` (matrix: macos-14, ubuntu-latest) | GitHub-hosted | The package builds and tests pass on both Apple and Linux toolchains — important because consumers may use FeedReaderCore in Linux server-side Swift, and Foundation behaves differently there. |
| `validate-podspec` | macos-14 | The podspec parses, source files are reachable, and there are no fatal lint errors. Warnings are allowed. Tests are skipped (the SPM job already runs them; podspec test runs are slow and redundant). |
| `publish-cocoapods` | macos-14 | Rewrites `s.version` to match the tag, then runs `pod trunk push`. Requires the `COCOAPODS_TRUNK_TOKEN` repo secret. Only runs if both validation jobs succeed. |
| `update-package-registry` | ubuntu-latest | Best-effort notification step. Swift Package Index polls GitHub for new tags on its own, so this job is mainly a human-readable receipt in the workflow logs. |

---

## Setup Required (One-Time)

### CocoaPods Trunk Token

To enable automated CocoaPods publishing:

1. Register with CocoaPods Trunk:
   ```bash
   pod trunk register online.saurav@gmail.com 'Saurav Bhattacharya'
   ```
   You'll get a confirmation email. Click the link to activate the session.

2. Get your session token:
   ```bash
   cat ~/.netrc | grep -A2 trunk.cocoapods.org
   ```
   (or `~/Library/Application Support/CocoaPods/.cocoapods` on newer setups).

3. Add the token as a GitHub repository secret:
   - Go to **Settings → Secrets and variables → Actions**
   - Add `COCOAPODS_TRUNK_TOKEN` with your token value
   - The secret must be available to the `publish-cocoapods` job. If you're
     publishing from a fork or environment, double-check secret scoping.

### Swift Package Index

No setup needed. [Swift Package Index](https://swiftpackageindex.com)
automatically discovers tagged releases from public GitHub repositories.
To register the package the first time:

1. Visit https://swiftpackageindex.com/add-a-package
2. Submit `https://github.com/sauravbhattacharya001/FeedReader`

After that, every new `v*` tag gets indexed automatically within a few minutes.

---

## Consumer Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/sauravbhattacharya001/FeedReader.git", from: "2.0.0")
]
```

### CocoaPods

```ruby
pod 'FeedReaderCore', '~> 2.0'
```

---

## Versioning

Follow [Semantic Versioning](https://semver.org/):

- **Patch** (`1.2.x`): Bug fixes, no public API changes.
- **Minor** (`1.x.0`): New features, backward compatible. Existing call sites
  keep compiling and behaving the same.
- **Major** (`x.0.0`): Breaking API changes — renamed types, removed methods,
  changed default behavior of public APIs.

Always tag in the form `vMAJOR.MINOR.PATCH`. The publish workflow strips the
leading `v` and rewrites the podspec to match, so the git tag is the single
source of truth — **do not** hand-bump `s.version` in `FeedReaderCore.podspec`
before tagging.

---

## Troubleshooting

### `pod trunk push` fails with `[!] Unable to accept duplicate entry`

The version you're trying to publish already exists on CocoaPods Trunk.
Trunk is append-only — you cannot overwrite a published podspec. Bump the
patch version, re-tag, and re-push:

```bash
git tag -d v1.14.0                    # local delete
git push origin :refs/tags/v1.14.0    # remote delete (only safe before publish)
git tag v1.14.1
git push origin v1.14.1
```

### `pod trunk push` fails with `Authentication token is invalid`

The `COCOAPODS_TRUNK_TOKEN` secret has expired or been rotated. Re-run
`pod trunk register`, grab the new token from `~/.netrc`, and update the
GitHub secret. Trunk sessions don't expire on a fixed schedule but they do
get invalidated if you register from a new machine.

### SPM build fails on Linux but passes on macOS

The most common cause is a Foundation API that only exists on Apple
platforms (e.g. some `NSAttributedString` methods, some `URLSession`
delegate signatures). Reproduce locally with the official Swift Linux
container before re-tagging:

```bash
docker run --rm -v "$PWD":/work -w /work swift:5.9 swift test
```

Fix the platform divergence with `#if canImport(...)` or by gating Apple-only
features behind a separate target — do not delete the Linux job to make CI
green.

### Swift Package Index doesn't pick up the new version

Wait 15 minutes — it polls. If it still doesn't appear:

- Check that the tag is annotated and reachable from `master`/`main`.
- Confirm `Package.swift` parses with `swift package describe`.
- Visit the package page on swiftpackageindex.com and use the "Rebuild" link
  in the maintainer dropdown.

---

## Manual Publish (Emergency Fallback)

If the publish workflow is unavailable (GitHub Actions outage, secret rotation
in flight, Trunk being moody), you can publish from a developer machine. This
mirrors what the CI job does, step-for-step:

```bash
# 1. Check out the exact commit the tag points at.
git checkout v1.14.0

# 2. Validate locally.
swift package resolve
swift build -c release
swift test
pod lib lint FeedReaderCore.podspec --allow-warnings --skip-tests

# 3. Bump the podspec version to match the tag.
#    On macOS, sed needs the empty -i argument; on Linux drop it.
sed -i '' "s/s.version.*=.*/s.version          = '1.14.0'/" FeedReaderCore.podspec
grep "s.version" FeedReaderCore.podspec   # sanity check

# 4. Push to Trunk.
pod trunk push FeedReaderCore.podspec --allow-warnings --skip-tests
```

**Important:** do not commit the bumped podspec back to `master`. The CI
workflow rewrites it inside its own runner, then publishes — the value on
disk between tags should stay at whatever the last release set it to (or
the pre-release placeholder). Discard the local edit once Trunk accepts:

```bash
git checkout -- FeedReaderCore.podspec
```

---

## Verifying a Published Release

After tagging, confirm the artifact actually reached its destinations:

```bash
# CocoaPods Trunk
pod trunk info FeedReaderCore

# Swift Package Manager (resolve from a scratch project)
mkdir /tmp/spm-smoke && cd /tmp/spm-smoke
swift package init --type executable
# Edit Package.swift to add FeedReaderCore as a dependency, then:
swift build
```

A successful resolve + build against the freshly tagged version is the
strongest signal that the release is healthy for consumers.
