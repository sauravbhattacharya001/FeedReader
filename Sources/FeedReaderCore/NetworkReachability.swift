//
//  NetworkReachability.swift
//  FeedReaderCore
//
//  Utility to check network connectivity using SystemConfiguration.
//

import Foundation
import SystemConfiguration

/// Provides a simple check for network reachability.
public enum NetworkReachability {

    /// Returns `true` if the device currently has a network route available.
    ///
    /// Uses `SCNetworkReachability` to check for a default route.
    /// Does not guarantee that a specific host is reachable — only that
    /// the system believes a route exists.
    public static func isConnected() -> Bool {
        var zeroAddress = sockaddr_in(
            sin_len: 0, sin_family: 0, sin_port: 0,
            sin_addr: in_addr(s_addr: 0),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer($0))
            }
        }) else {
            return false
        }

        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else {
            return false
        }

        return flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }
}
