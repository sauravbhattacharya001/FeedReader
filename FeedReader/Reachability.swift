	//
//  Reachability.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/15/16.
//  Adapted from: http://stackoverflow.com/questions/30743408/check-for-internet-connection-in-swift-2-ios-9
//  Swift 2.2 to 3 migration of unsafe pointers: https://swift.org/migration-guide/se-0107-migrate.html
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import Foundation
import SystemConfiguration

open class Reachability {
    
    class func isConnectedToNetwork() -> Bool {
        
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer($0))
            }
        }) else {
            return false
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) == false {
            return false
        }
        
        // Use .contains() instead of == for bitmask flags.
        // SCNetworkReachabilityFlags is an OptionSet — multiple bits
        // can be set simultaneously (e.g. .reachable + .isWWAN).
        // Exact equality (==) would return false when extra bits are set,
        // incorrectly reporting no connectivity on cellular networks.
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        
        return isReachable && !needsConnection
        
    }
}
