// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeedReaderCore",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        // The core RSS parsing and feed management library.
        // Contains models, RSS parser, image cache, bookmark management,
        // and network reachability — everything except UIKit view controllers.
        .library(
            name: "FeedReaderCore",
            targets: ["FeedReaderCore"]),
    ],
    targets: [
        .target(
            name: "FeedReaderCore",
            path: "Sources/FeedReaderCore"),
        .testTarget(
            name: "FeedReaderCoreTests",
            dependencies: ["FeedReaderCore"],
            path: "Tests/FeedReaderCoreTests"),
    ]
)
