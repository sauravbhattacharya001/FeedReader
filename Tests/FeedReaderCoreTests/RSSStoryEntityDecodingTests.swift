//
//  RSSStoryEntityDecodingTests.swift
//  FeedReaderCoreTests
//
//  Regression tests for the numeric / hexadecimal HTML entity decoding
//  branch of `RSSStory.stripHTML(_:)` and a handful of HTML-sanitization
//  edge cases that aren't covered by the broader RSSStoryTests in
//  FeedReaderCoreTests.swift.
//
//  The base entity table in `RSSStory` only handles a handful of named
//  entities (&amp;, &lt;, &gt;, &quot;, &#39;, &nbsp;) plus a generic
//  `&#NNN;` / `&#xNN;` numeric path. Article bodies from real-world feeds
//  routinely use the numeric form for typographic punctuation
//  (em-dashes, curly quotes, ellipses), so the numeric path is hot code
//  that must remain correct.
//

import XCTest
@testable import FeedReaderCore

final class RSSStoryEntityDecodingTests: XCTestCase {

    // MARK: - Numeric entity decoding

    func testStripHTMLDecodesDecimalNumericEntity() {
        // &#8212; is U+2014 EM DASH — the most common numeric entity in
        // English-language news feeds.
        XCTAssertEqual(
            RSSStory.stripHTML("Headline &#8212; subhead"),
            "Headline \u{2014} subhead"
        )
    }

    func testStripHTMLDecodesHexNumericEntity() {
        // &#x2014; is the hex form of the same EM DASH.
        XCTAssertEqual(
            RSSStory.stripHTML("Headline &#x2014; subhead"),
            "Headline \u{2014} subhead"
        )
    }

    func testStripHTMLDecodesUppercaseHexNumericEntity() {
        // RFC allows &#X...; (capital X). The decoder normalizes by
        // dropping the leading x/X via `dropFirst()`, so this must work.
        XCTAssertEqual(
            RSSStory.stripHTML("price &#X24;5"),
            "price $5"
        )
    }

    func testStripHTMLDecodesBasicAsciiNumericEntity() {
        // &#65; is uppercase 'A'.
        XCTAssertEqual(RSSStory.stripHTML("&#65;BC"), "ABC")
    }

    func testStripHTMLDecodesAstralPlaneCodePoint() {
        // U+1F600 GRINNING FACE — verifies the decoder handles full
        // 21-bit Unicode scalars, not just BMP characters.
        XCTAssertEqual(
            RSSStory.stripHTML("happy &#x1F600; reader"),
            "happy \u{1F600} reader"
        )
    }

    func testStripHTMLDecodesAdjacentNumericEntities() {
        // Two entities back-to-back must each be decoded; the decoder
        // must not get confused about index boundaries between them.
        XCTAssertEqual(
            RSSStory.stripHTML("&#8220;quoted&#8221;"),
            "\u{201C}quoted\u{201D}"
        )
    }

    func testStripHTMLMixesNamedAndNumericEntities() {
        XCTAssertEqual(
            RSSStory.stripHTML("Tom &amp; Jerry &#8211; episode &lt;1&gt;"),
            "Tom & Jerry \u{2013} episode <1>"
        )
    }

    // MARK: - Malformed numeric entities — must not crash, leave literal

    func testStripHTMLLeavesEmptyNumericEntityLiteral() {
        // "&#;" has no digits between &# and ; — invalid, must be passed
        // through unchanged rather than decoded to U+0000.
        XCTAssertEqual(RSSStory.stripHTML("a &#; b"), "a &#; b")
    }

    func testStripHTMLLeavesNonNumericEntityLiteral() {
        // "&#abc;" — letters where digits are required. The hex path
        // requires the FIRST character to be x/X; "abc" doesn't satisfy
        // either decimal or hex parsing, so result must be nil → literal.
        XCTAssertEqual(RSSStory.stripHTML("&#abc;"), "&#abc;")
    }

    func testStripHTMLLeavesUnterminatedNumericEntityLiteral() {
        // No semicolon to close the entity — must be left as-is.
        XCTAssertEqual(RSSStory.stripHTML("&#1234"), "&#1234")
    }

    func testStripHTMLLeavesOverflowingNumericEntityLiteral() {
        // 0x110000 is one above the maximum valid Unicode scalar
        // (U+10FFFF). `Unicode.Scalar(_:)` returns nil, so the decoder
        // must fall through to the literal-passthrough branch.
        XCTAssertEqual(
            RSSStory.stripHTML("x &#x110000; y"),
            "x &#x110000; y"
        )
    }

    func testStripHTMLLeavesSurrogateNumericEntityLiteral() {
        // 0xD800 is the start of the UTF-16 high-surrogate range —
        // invalid as a standalone scalar. Must be left literal.
        XCTAssertEqual(
            RSSStory.stripHTML("bad &#xD800; surrogate"),
            "bad &#xD800; surrogate"
        )
    }

    func testStripHTMLLeavesUnknownNamedEntityLiteral() {
        // Not in the curated entity table → must remain literal so we
        // don't silently mangle text we don't understand.
        XCTAssertEqual(
            RSSStory.stripHTML("copyright &copy; 2026"),
            "copyright &copy; 2026"
        )
    }

    func testStripHTMLLoneAmpersandStaysLiteral() {
        XCTAssertEqual(RSSStory.stripHTML("rock & roll"), "rock & roll")
    }

    // MARK: - Whitespace / nbsp handling

    func testStripHTMLDecodesNonBreakingSpace() {
        // &nbsp; is in the named entity table and maps to a regular
        // space. The trailing trim then collapses leading/trailing
        // whitespace, so this exercises both the entity decode and the
        // final `trimmingCharacters` step.
        XCTAssertEqual(
            RSSStory.stripHTML("hello&nbsp;world"),
            "hello world"
        )
    }

    func testStripHTMLTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(
            RSSStory.stripHTML("\n   <p>padded</p>   \n"),
            "padded"
        )
    }

    // MARK: - Tag stripping

    func testStripHTMLRemovesNestedTags() {
        XCTAssertEqual(
            RSSStory.stripHTML("<div><p>One <strong>two</strong> three</p></div>"),
            "One two three"
        )
    }

    func testStripHTMLRemovesSelfClosingTags() {
        XCTAssertEqual(
            RSSStory.stripHTML("line one<br/>line two<br />line three"),
            "line oneline twoline three"
        )
    }

    func testStripHTMLRemovesTagsWithAttributes() {
        XCTAssertEqual(
            RSSStory.stripHTML(#"<a href="https://example.com" target="_blank">link</a>"#),
            "link"
        )
    }

    func testStripHTMLPreservesTextWithNoTagsUnchanged() {
        XCTAssertEqual(
            RSSStory.stripHTML("simple text with no tags or entities"),
            "simple text with no tags or entities"
        )
    }

    func testStripHTMLHandlesEmptyString() {
        XCTAssertEqual(RSSStory.stripHTML(""), "")
    }

    // MARK: - Integration: stripping survives RSSStory init

    func testInitStripsHTMLFromBody() {
        // RSSStory.init runs stripHTML on the body; numeric entities in
        // the body should be decoded before being stored.
        let story = RSSStory(
            title: "Title",
            body: "<p>Tom &amp; Jerry &#8212; classic</p>",
            link: "https://example.com/article"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.body, "Tom & Jerry \u{2014} classic")
    }

    func testInitRejectsBodyThatStripsToEmpty() {
        // A body of only tags + whitespace strips down to "" → init
        // must fail the empty-body guard and return nil.
        let story = RSSStory(
            title: "Title",
            body: "<p>   </p>\n  <br/>",
            link: "https://example.com/article"
        )
        XCTAssertNil(story)
    }
}
