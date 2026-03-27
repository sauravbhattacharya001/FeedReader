//
//  ArticleDarkModeFormatter.swift
//  FeedReader
//
//  Reformats article HTML content for dark mode display.
//  Supports multiple dark themes (OLED, Sepia Night, Solarized Dark, Custom),
//  automatic image dimming, link color adjustment, and CSS injection.
//

import Foundation
import UIKit

// MARK: - Dark Mode Theme

/// Available dark mode themes for article rendering.
enum DarkModeTheme: String, Codable, CaseIterable {
    case standard    // Dark grey background, light text
    case oled        // Pure black background for AMOLED screens
    case sepiaNight  // Warm dark tones, easy on the eyes
    case solarized   // Solarized dark palette
    case custom      // User-defined colors

    var displayName: String {
        switch self {
        case .standard:   return "Standard Dark"
        case .oled:       return "OLED Black"
        case .sepiaNight: return "Sepia Night"
        case .solarized:  return "Solarized Dark"
        case .custom:     return "Custom"
        }
    }
}

// MARK: - Theme Colors

/// Color palette for a dark mode theme.
struct ThemeColors: Codable {
    let backgroundColor: String   // Hex color
    let textColor: String
    let linkColor: String
    let headingColor: String
    let codeBackground: String
    let codeForeground: String
    let borderColor: String
    let blockquoteBackground: String
    let blockquoteBorder: String
    let imageDimming: CGFloat     // 0.0 (no dim) to 1.0 (fully dimmed)

    static let standard = ThemeColors(
        backgroundColor: "#1e1e1e",
        textColor: "#e0e0e0",
        linkColor: "#6cb4ee",
        headingColor: "#ffffff",
        codeBackground: "#2d2d2d",
        codeForeground: "#c5c8c6",
        borderColor: "#333333",
        blockquoteBackground: "#252525",
        blockquoteBorder: "#555555",
        imageDimming: 0.15
    )

    static let oled = ThemeColors(
        backgroundColor: "#000000",
        textColor: "#d4d4d4",
        linkColor: "#58a6ff",
        headingColor: "#f0f0f0",
        codeBackground: "#111111",
        codeForeground: "#b5b5b5",
        borderColor: "#222222",
        blockquoteBackground: "#0a0a0a",
        blockquoteBorder: "#444444",
        imageDimming: 0.2
    )

    static let sepiaNight = ThemeColors(
        backgroundColor: "#1a1410",
        textColor: "#d4c5a9",
        linkColor: "#c4956a",
        headingColor: "#e8d5b5",
        codeBackground: "#231d15",
        codeForeground: "#bfb198",
        borderColor: "#3a2e20",
        blockquoteBackground: "#1f1812",
        blockquoteBorder: "#5a4a35",
        imageDimming: 0.1
    )

    static let solarized = ThemeColors(
        backgroundColor: "#002b36",
        textColor: "#839496",
        linkColor: "#268bd2",
        headingColor: "#93a1a1",
        codeBackground: "#073642",
        codeForeground: "#859900",
        borderColor: "#073642",
        blockquoteBackground: "#073642",
        blockquoteBorder: "#586e75",
        imageDimming: 0.1
    )

    static func colors(for theme: DarkModeTheme) -> ThemeColors {
        switch theme {
        case .standard:   return .standard
        case .oled:       return .oled
        case .sepiaNight: return .sepiaNight
        case .solarized:  return .solarized
        case .custom:     return .standard // Fallback; users override via settings
        }
    }
}

// MARK: - Formatter Settings

/// Persistent settings for the dark mode formatter.
struct DarkModeSettings: Codable {
    var isEnabled: Bool = false
    var theme: DarkModeTheme = .standard
    var customColors: ThemeColors? = nil
    var fontSizeMultiplier: CGFloat = 1.0
    var dimImages: Bool = true
    var invertLightImages: Bool = false
    var reduceMotion: Bool = false
    var lineSpacingMultiplier: CGFloat = 1.4
    var maxContentWidth: CGFloat = 720
    var fontFamily: String = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"

    /// Returns the active color palette.
    var activeColors: ThemeColors {
        if theme == .custom, let custom = customColors {
            return custom
        }
        return ThemeColors.colors(for: theme)
    }
}

// MARK: - ArticleDarkModeFormatter

/// Transforms article HTML for dark mode rendering in a WKWebView or similar.
final class ArticleDarkModeFormatter {

    // MARK: - Storage

    private static let settingsKey = "com.feedreader.darkmode.settings"

    /// Load saved settings or return defaults.
    static func loadSettings() -> DarkModeSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(DarkModeSettings.self, from: data) else {
            return DarkModeSettings()
        }
        return settings
    }

    /// Persist settings.
    static func saveSettings(_ settings: DarkModeSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: - CSS Generation

    /// Generates the dark mode CSS stylesheet for the given settings.
    static func generateCSS(for settings: DarkModeSettings) -> String {
        let c = settings.activeColors
        let fontSize = 16.0 * settings.fontSizeMultiplier

        var css = """
        :root {
            color-scheme: dark;
        }
        * {
            box-sizing: border-box;
        }
        html, body {
            background-color: \(c.backgroundColor) !important;
            color: \(c.textColor) !important;
            font-family: \(settings.fontFamily);
            font-size: \(fontSize)px;
            line-height: \(settings.lineSpacingMultiplier);
            margin: 0;
            padding: 16px;
            max-width: \(settings.maxContentWidth)px;
            margin-left: auto;
            margin-right: auto;
            -webkit-text-size-adjust: 100%;
        }
        h1, h2, h3, h4, h5, h6 {
            color: \(c.headingColor) !important;
            font-weight: 600;
            margin-top: 1.5em;
            margin-bottom: 0.5em;
        }
        a, a:visited {
            color: \(c.linkColor) !important;
            text-decoration: underline;
        }
        a:hover {
            opacity: 0.85;
        }
        pre, code {
            background-color: \(c.codeBackground) !important;
            color: \(c.codeForeground) !important;
            border-radius: 4px;
            padding: 2px 6px;
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 0.9em;
        }
        pre {
            padding: 12px;
            overflow-x: auto;
        }
        pre code {
            padding: 0;
        }
        blockquote {
            background-color: \(c.blockquoteBackground) !important;
            border-left: 3px solid \(c.blockquoteBorder) !important;
            margin: 1em 0;
            padding: 8px 16px;
            color: \(c.textColor) !important;
        }
        hr {
            border: none;
            border-top: 1px solid \(c.borderColor);
            margin: 1.5em 0;
        }
        table {
            border-collapse: collapse;
            width: 100%;
        }
        th, td {
            border: 1px solid \(c.borderColor) !important;
            padding: 8px;
            color: \(c.textColor) !important;
        }
        th {
            background-color: \(c.codeBackground) !important;
        }
        """

        // Image dimming
        if settings.dimImages && c.imageDimming > 0 {
            let brightness = 1.0 - c.imageDimming
            css += """
            img, video, svg {
                filter: brightness(\(brightness));
                transition: filter 0.2s ease;
            }
            img:hover, video:hover {
                filter: brightness(1.0);
            }
            """
        }

        // Invert light images heuristic
        if settings.invertLightImages {
            css += """
            img[src$='.svg'],
            img[src*='logo'],
            img[src*='icon'] {
                filter: invert(0.85) hue-rotate(180deg);
            }
            """
        }

        // Reduce motion
        if settings.reduceMotion {
            css += """
            *, *::before, *::after {
                animation: none !important;
                transition: none !important;
            }
            """
        }

        return css
    }

    // MARK: - HTML Transformation

    /// Wraps or injects dark mode styles into article HTML.
    /// - Parameters:
    ///   - html: The original article HTML content.
    ///   - settings: Dark mode settings (uses saved settings if nil).
    /// - Returns: HTML string with dark mode CSS injected.
    static func applyDarkMode(to html: String, settings: DarkModeSettings? = nil) -> String {
        let activeSettings = settings ?? loadSettings()

        guard activeSettings.isEnabled else { return html }

        let css = generateCSS(for: activeSettings)
        let styleTag = "<style id=\"feedreader-darkmode\">\(css)</style>"

        // If HTML has a <head>, inject there
        if let headRange = html.range(of: "</head>", options: .caseInsensitive) {
            var modified = html
            modified.insert(contentsOf: styleTag, at: headRange.lowerBound)
            return modified
        }

        // If HTML has a <body>, inject at start of body
        if let bodyRange = html.range(of: "<body", options: .caseInsensitive) {
            // Find the closing > of the body tag
            if let closeRange = html[bodyRange.upperBound...].range(of: ">") {
                var modified = html
                let insertionPoint = html.index(after: closeRange.lowerBound)
                modified.insert(contentsOf: styleTag, at: insertionPoint)
                return modified
            }
        }

        // Fallback: wrap everything
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \(styleTag)
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }

    // MARK: - System Dark Mode Detection

    /// Returns true if the system is currently in dark mode.
    static var systemIsDarkMode: Bool {
        if #available(iOS 13.0, *) {
            return UITraitCollection.current.userInterfaceStyle == .dark
        }
        return false
    }

    /// Returns settings configured to follow the system appearance.
    static func autoSettings() -> DarkModeSettings {
        var settings = loadSettings()
        settings.isEnabled = systemIsDarkMode
        return settings
    }

    // MARK: - Quick Previews

    /// Generates a small HTML preview showing how a theme looks.
    static func themePreviewHTML(for theme: DarkModeTheme) -> String {
        var settings = DarkModeSettings()
        settings.isEnabled = true
        settings.theme = theme

        let sample = """
        <h2>\(theme.displayName)</h2>
        <p>This is how your articles will look with this theme.
        Here's a <a href="#">sample link</a> and some text.</p>
        <blockquote>A blockquote with an important thought.</blockquote>
        <pre><code>let greeting = "Hello, dark mode!"</code></pre>
        """

        return applyDarkMode(to: sample, settings: settings)
    }
}
