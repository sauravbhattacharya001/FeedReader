//
//  AppDelegate.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

/// The application delegate for FeedReader.
///
/// Handles app lifecycle events and ensures pending offline cache writes
/// are flushed before the app is suspended or terminated.
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    /// Called after the app finishes launching.
    /// - Returns: `true` to indicate successful launch.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    /// Flushes any debounced offline cache writes before backgrounding
    /// to avoid data loss if the OS terminates the app.
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Flush any debounced offline cache writes before backgrounding
        // to avoid data loss if the OS terminates the app.
        OfflineCacheManager.shared.flushPersist()
    }

    /// Flushes pending cache writes before the app is terminated.
    func applicationWillTerminate(_ application: UIApplication) {
        OfflineCacheManager.shared.flushPersist()
    }
}
