//
//  AppDelegate.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/14/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Flush any debounced offline cache writes before backgrounding
        // to avoid data loss if the OS terminates the app.
        OfflineCacheManager.shared.flushPersist()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        OfflineCacheManager.shared.flushPersist()
    }
}
