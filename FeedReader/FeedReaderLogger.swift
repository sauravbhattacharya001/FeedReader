//
//  FeedReaderLogger.swift
//  FeedReader
//
//  Centralized logging using os_log with privacy-aware formatting.
//  Replaces raw print() calls that leaked feed URLs (which may contain
//  authentication tokens in query parameters) to the device console log
//  readable by any app on the same device.
//
//  os_log marks dynamic strings as private by default, preventing them
//  from appearing in console logs unless the device is in a debug
//  profile.  This protects user data such as feed URLs, article titles,
//  and error details from leaking to other processes.
//

import Foundation
import os.log

/// Subsystem identifier for all FeedReader log messages.
private let subsystem = "com.feedreader.app"

/// Namespace for FeedReader os_log categories.
enum FeedReaderLogger {
    static let parser   = OSLog(subsystem: subsystem, category: "RSSParser")
    static let storage  = OSLog(subsystem: subsystem, category: "Storage")
    static let tts      = OSLog(subsystem: subsystem, category: "TTS")
    static let filter   = OSLog(subsystem: subsystem, category: "ContentFilter")
    static let alerts   = OSLog(subsystem: subsystem, category: "KeywordAlerts")
    static let cache    = OSLog(subsystem: subsystem, category: "OfflineCache")
    static let share    = OSLog(subsystem: subsystem, category: "Share")
    static let smartFeed = OSLog(subsystem: subsystem, category: "SmartFeed")
    static let quotes   = OSLog(subsystem: subsystem, category: "QuoteJournal")
    static let diff     = OSLog(subsystem: subsystem, category: "FeedDiff")
    static let edit     = OSLog(subsystem: subsystem, category: "EditTracker")
    static let general  = OSLog(subsystem: subsystem, category: "General")
}
