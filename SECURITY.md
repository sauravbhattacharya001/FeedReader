# Security Policy

## Overview

FeedReader processes external RSS feed data from the internet and renders it in a native iOS UI. Since RSS feeds are untrusted input, several security measures are in place to prevent injection, data exfiltration, and unsafe resource loading.

## Security Measures

### URL Scheme Validation

All URLs from RSS feed data are validated before use. Only `https` and `http` schemes are allowed.

**What it prevents:** `javascript:`, `file://`, `data:`, `tel:`, and custom URL scheme injection from malicious feed content.

**Where:** `Story.isSafeURL(_:)` — called during model initialization, image loading, and link opening.

```swift
// Rejects: javascript:alert(1), file:///etc/passwd, data:text/html,...
static func isSafeURL(_ urlString: String?) -> Bool {
    guard let scheme = URL(string: urlString)?.scheme?.lowercased() else { return false }
    return ["https", "http"].contains(scheme)
}
```

### HTML Sanitization

RSS `<description>` content is stripped of all HTML tags before display to prevent markup injection.

**What it prevents:** Injected HTML/CSS that could alter the UI, phishing overlays, or tracking pixels.

**Where:** `Story.stripHTML(_:)` — applied during `Story.init()`. Common HTML entities (`&amp;`, `&lt;`, etc.) are decoded after tag removal.

### Secure Deserialization

Offline story caching uses `NSSecureCoding` instead of basic `NSCoding`. The `Story` class declares `supportsSecureCoding = true`, and deserialization uses typed methods (`decodeObject(of:forKey:)`) to prevent object substitution attacks.

**What it prevents:** Archive injection where a corrupted/malicious `.stories` file instantiates unexpected classes during deserialization.

**Where:** `Story.init?(coder:)` uses `decodeObject(of: NSString.self, ...)` and `decodeObject(of: UIImage.self, ...)`.

### Failable Initialization

`Story.init?()` returns `nil` (and the story is silently dropped) if:
- Title or description is empty
- Link URL fails scheme validation

This ensures malformed or malicious feed entries never enter the data model.

### Network Security

- All feed URLs use HTTPS by default (BBC News feed: `https://feeds.bbci.co.uk/...`)
- HTTP response status codes are validated before parsing (only 2xx accepted)
- Network requests use `URLSession` with default App Transport Security (ATS) protections

### Image Loading

- Thumbnail URLs extracted from RSS `<media:thumbnail>` attributes are validated with `isSafeURL()` before loading
- Images are loaded via `URLSession` (not `UIWebView` or direct URL rendering)
- Image cache (`NSCache`) automatically evicts under memory pressure

## Automated Security Scanning

- **CodeQL** runs on every push and PR via GitHub Actions (`.github/workflows/codeql.yml`)
- **Dependabot** monitors for dependency vulnerabilities (`.github/dependabot.yml`)
- **CI linting** validates code structure on every push

## Reporting a Vulnerability

If you discover a security vulnerability, please email [online.saurav@gmail.com](mailto:online.saurav@gmail.com) rather than opening a public issue. Include:

1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

You should receive a response within 48 hours.

## Threat Model

| Threat | Mitigation | Status |
|--------|-----------|--------|
| Malicious RSS feed injects JavaScript via links | URL scheme allowlist (`https`/`http` only) | ✅ |
| HTML injection in story descriptions | `stripHTML()` removes all tags before display | ✅ |
| Object substitution via corrupted archive | `NSSecureCoding` with typed deserialization | ✅ |
| Tracking pixels in feed content | HTML stripped; images only load from validated URLs | ✅ |
| Man-in-the-middle on feed fetch | HTTPS + ATS enforcement | ✅ |
| Denial of service via huge feed | iOS memory limits + `NSCache` auto-eviction | ✅ |
