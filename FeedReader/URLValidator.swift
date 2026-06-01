//
//  URLValidator.swift
//  FeedReader
//
//  Centralized URL validation with SSRF (Server-Side Request Forgery)
//  protection.  Guards against feed URLs that target internal/private
//  network addresses, cloud metadata endpoints, or loopback interfaces.
//

import Foundation

/// Provides URL validation and SSRF protection for feed URLs, OPML imports,
/// and any user-supplied links before the app makes outbound network requests.
enum URLValidator {

    /// Allowed URL schemes.  Only HTTP(S) feeds are supported.
    static let allowedSchemes: Set<String> = ["https", "http"]

    // MARK: - Public API

    /// Validate that a URL string is safe for network access.
    /// Checks scheme, host presence, and rejects private/reserved addresses.
    ///
    /// - Parameter urlString: The raw URL string to validate.
    /// - Returns: `true` if the URL is safe for outbound requests.
    static func isSafe(_ urlString: String?) -> Bool {
        guard let urlString = urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host, !host.isEmpty else {
            return false
        }
        return !isPrivateOrReserved(host: host)
    }

    /// Validate a URL string for feed addition — ensures it is a valid,
    /// publicly-routable HTTP(S) URL suitable for RSS/Atom fetching.
    ///
    /// Performs both hostname pattern matching AND DNS resolution to
    /// defend against DNS rebinding attacks (CWE-350) where an attacker-
    /// controlled domain resolves to a private/loopback address.
    ///
    /// - Parameter urlString: The feed URL to validate.
    /// - Returns: The parsed `URL` if valid, or `nil` if it fails validation.
    static func validateFeedURL(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host, !host.isEmpty else {
            return nil
        }
        guard !isPrivateOrReserved(host: host) else {
            return nil
        }
        // DNS rebinding defense: verify resolved IPs are public
        guard dnsResolvesToPublicAddress(host: host) else {
            return nil
        }
        return url
    }

    // MARK: - SSRF Protection

    /// Check if a hostname resolves to a private, loopback, link-local,
    /// or otherwise reserved address range.
    ///
    /// Covers:
    /// - IPv4 loopback:           127.0.0.0/8
    /// - IPv4 private:            10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
    /// - IPv4 link-local:         169.254.0.0/16 (incl. cloud metadata)
    /// - IPv4 shared (CGN):       100.64.0.0/10
    /// - IPv4 documentation:      192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24
    /// - IPv6 loopback:           ::1
    /// - IPv6 link-local:         fe80::/10
    /// - IPv6 unique-local:       fc00::/7 (fd00::/8)
    /// - IPv6 mapped IPv4:        ::ffff:x.x.x.x (delegates to IPv4 checks)
    /// - Special hostnames:       localhost, *.local, *.internal
    /// - Cloud metadata:          169.254.169.254 and aliases
    static func isPrivateOrReserved(host: String) -> Bool {
        let lower = host.lowercased()

        // ── Special hostnames ────────────────────────────────────
        if lower == "localhost"
            || lower.hasSuffix(".localhost")
            || lower.hasSuffix(".local")
            || lower.hasSuffix(".internal")
            || lower == "metadata.google.internal" {
            return true
        }

        // ── Bracket-stripped IPv6 literal ─────────────────────────
        let cleaned: String
        if lower.hasPrefix("[") && lower.hasSuffix("]") {
            cleaned = String(lower.dropFirst().dropLast())
        } else {
            cleaned = lower
        }

        // ── IPv6 checks ──────────────────────────────────────────
        if cleaned == "::1" || cleaned == "0:0:0:0:0:0:0:1" {
            return true  // loopback
        }
        // fe80::/10 link-local covers fe80:: through febf:: (prefixes fe8, fe9, fea, feb)
        if cleaned.hasPrefix("fe8") || cleaned.hasPrefix("fe9")
            || cleaned.hasPrefix("fea") || cleaned.hasPrefix("feb") {
            return true  // link-local (fe80::/10)
        }
        if cleaned.hasPrefix("fd") || cleaned.hasPrefix("fc") {
            return true  // unique-local (fc00::/7)
        }
        // IPv4-mapped IPv6: ::ffff:w.x.y.z
        if cleaned.hasPrefix("::ffff:") {
            let ipv4Part = String(cleaned.dropFirst(7))
            if isPrivateIPv4(ipv4Part) { return true }
        }

        // ── IPv4 checks ──────────────────────────────────────────
        if isPrivateIPv4(cleaned) {
            return true
        }

        return false
    }

    // MARK: - DNS Resolution Check

    /// Resolve a hostname via DNS and verify that none of the resolved
    /// addresses fall into private/reserved ranges (DNS rebinding defense).
    ///
    /// An attacker-controlled domain can return loopback or private IPs,
    /// bypassing hostname-only SSRF filters. This performs a synchronous
    /// DNS lookup and rejects the host if any resolved address is private.
    ///
    /// - Parameter host: The hostname to resolve.
    /// - Returns: `true` if all resolved addresses are publicly routable,
    ///   `false` if any address is private/reserved or resolution fails.
    static func dnsResolvesToPublicAddress(host: String) -> Bool {
        // Skip resolution for IP literals — already checked by isPrivateOrReserved
        if parseIPv4(host) != nil { return !isPrivateIPv4(host) }
        if host.contains(":") { return true } // IPv6 literals handled above

        var hints = addrinfo(
            ai_flags: AI_NUMERICSERV,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, "443", &hints, &result)
        guard status == 0, let firstResult = result else { return false }
        defer { freeaddrinfo(firstResult) }

        var current: UnsafeMutablePointer<addrinfo>? = firstResult
        while let info = current {
            if let addr = info.pointee.ai_addr {
                switch Int32(info.pointee.ai_family) {
                case AF_INET:
                    let ipv4 = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    let ip = ipv4.sin_addr
                    let a = UInt8((ip.s_addr >> 0) & 0xFF)
                    let b = UInt8((ip.s_addr >> 8) & 0xFF)
                    let c = UInt8((ip.s_addr >> 16) & 0xFF)
                    let d = UInt8((ip.s_addr >> 24) & 0xFF)
                    let ipStr = "\(a).\(b).\(c).\(d)"
                    if isPrivateIPv4(ipStr) { return false }
                case AF_INET6:
                    let ipv6 = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                    var sin6Addr = ipv6.sin6_addr
                    let isUnsafe = withUnsafeBytes(of: &sin6Addr) { buf -> Bool in
                        // Loopback ::1
                        if buf[0..<15].allSatisfy({ $0 == 0 }) && buf[15] == 1 { return true }
                        // Link-local fe80::/10
                        if buf[0] == 0xFE && (buf[1] & 0xC0) == 0x80 { return true }
                        // Unique-local fc00::/7
                        if (buf[0] & 0xFE) == 0xFC { return true }
                        // IPv4-mapped ::ffff:x.x.x.x
                        if buf[0..<10].allSatisfy({ $0 == 0 }) && buf[10] == 0xFF && buf[11] == 0xFF {
                            let ipStr = "\(buf[12]).\(buf[13]).\(buf[14]).\(buf[15])"
                            if isPrivateIPv4(ipStr) { return true }
                        }
                        return false
                    }
                    if isUnsafe { return false }
                default:
                    break
                }
            }
            current = info.pointee.ai_next
        }
        return true
    }

    // MARK: - IPv4 Helpers

    /// Parse an IPv4 dotted-decimal string into four octets.
    private static func parseIPv4(_ ip: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0], parts[1], parts[2], parts[3])
    }

    /// Check if an IPv4 address string falls in a private/reserved range.
    private static func isPrivateIPv4(_ ip: String) -> Bool {
        guard let (a, b, c, _) = parseIPv4(ip) else { return false }

        // 127.0.0.0/8 — Loopback
        if a == 127 { return true }
        // 10.0.0.0/8 — Private
        if a == 10 { return true }
        // 172.16.0.0/12 — Private
        if a == 172 && (b >= 16 && b <= 31) { return true }
        // 192.168.0.0/16 — Private
        if a == 192 && b == 168 { return true }
        // 169.254.0.0/16 — Link-local (includes cloud metadata 169.254.169.254)
        if a == 169 && b == 254 { return true }
        // 100.64.0.0/10 — Shared/CGN (Carrier-Grade NAT)
        if a == 100 && (b >= 64 && b <= 127) { return true }
        // 0.0.0.0/8 — "This" network
        if a == 0 { return true }
        // 192.0.2.0/24 — TEST-NET-1
        if a == 192 && b == 0 && c == 2 { return true }
        // 198.51.100.0/24 — TEST-NET-2
        if a == 198 && b == 51 && c == 100 { return true }
        // 203.0.113.0/24 — TEST-NET-3
        if a == 203 && b == 0 && c == 113 { return true }
        // 255.255.255.255 — Broadcast
        if a == 255 { return true }

        return false
    }
}
