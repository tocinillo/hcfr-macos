// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Raspberry Pi (PGenerator) pattern generator support added in 2026.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Errors of the Raspberry Pi generator, with the same texts as HCFR for Windows where it has one.
enum PGeneratorError: LocalizedError {
    case notFound
    case badAddress(String)
    case connectFailed(String, String)
    case communication(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Raspberry Pi generator not found.\n\nCheck that the Raspberry Pi is on, running PGenerator, "
                + "and on the same network as this Mac, or enter its IP address in Generator → Raspberry Pi address. "
                + "If macOS asked for permission to find devices on the local network, allow it "
                + "(System Settings → Privacy & Security → Local Network)."
        case .badAddress(let a):
            return "\"\(a)\" is not a valid IPv4 address for the Raspberry Pi."
        case .connectFailed(let host, let why):
            return "Error connecting with rPI: \(host)\n\n\(why)"
        case .communication(let why):
            return "Error communicating with rPI\n\n\(why)"
        }
    }
}

/// Client for PGenerator, the Raspberry Pi pattern generator, with the same protocol HCFR for Windows
/// uses through RB8PGenerator.dll:
/// - discovery: UDP broadcast "Who is a PGenerator" to port 1977, the Pi answers "This is a PGenerator";
/// - commands: TCP port 85, each message ends with 0x02 0x0D and the Pi answers (e.g. "OK" or
///   "OK:1920x1080"), also ending with 0x02 0x0D.
///
/// All socket work runs on a private serial queue, so commands keep their order.
final class PGeneratorClient: @unchecked Sendable {
    static let discoveryPort: UInt16 = 1977
    static let commandPort: UInt16 = 85
    static let terminator: [UInt8] = [0x02, 0x0D]

    let host: String
    /// Pi output resolution (CMD:GET_RESOLUTION), 1920×1080 until read (HCFR's default).
    private(set) var width = 1920
    private(set) var height = 1080
    /// GPU memory of the Pi in MB (CMD:GET_GPU_MEMORY), 0 if unknown.
    private(set) var gpuMemoryMB = 0

    private let queue = DispatchQueue(label: "PGeneratorClient")
    private var fd: Int32 = -1

    var isConnected: Bool { queue.sync { fd >= 0 } }

    init(host: String) { self.host = host }
    deinit { if fd >= 0 { _ = Self.closeSocket(fd) } }

    // MARK: - Discovery

    /// Finds a PGenerator on the local network (as RB8PG_discovery): broadcasts on every IPv4
    /// network of this Mac and returns the address of the first Pi that answers.
    static func discover(timeout: TimeInterval = 2) async -> String? {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: discoverBlocking(timeout: timeout)) }
        }
    }

    static func discoverBlocking(timeout: TimeInterval) -> String? {
        let s = socket(AF_INET, sockDgram, 0)
        guard s >= 0 else { return nil }
        defer { _ = closeSocket(s) }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        let query = Array("Who is a PGenerator".utf8)
        var sent = false
        for target in broadcastAddresses() + ["255.255.255.255"] {
            guard var addr = sockaddrIn(target, port: discoveryPort) else { continue }
            let n = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(s, query, query.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if n == query.count { sent = true }
        }
        guard sent else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let left = deadline.timeIntervalSinceNow
            guard left > 0, waitReadable(s, seconds: left) else { return nil }
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(s, &buf, buf.count, 0, $0, &len) }
            }
            guard n > 0 else { continue }
            let reply = String(decoding: buf[0..<n], as: UTF8.self)
            if reply.contains("PGenerator") && !reply.hasPrefix("Who is") { return ipString(from.sin_addr) }
        }
    }

    /// Broadcast address of each active IPv4 network (address | ~netmask), loopback excluded.
    static func broadcastAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [String] = []
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            let flags = ifa.ifa_flags
            guard flags & UInt32(truncatingIfNeeded: IFF_UP) != 0,
                  flags & UInt32(truncatingIfNeeded: IFF_LOOPBACK) == 0,
                  let a = ifa.ifa_addr, let m = ifa.ifa_netmask,
                  a.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let ip = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let mask = m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let s = ipString(in_addr(s_addr: ip | ~mask))
            if !result.contains(s) { result.append(s) }
        }
        return result
    }

    // MARK: - Commands

    /// Connects to the Pi and reads its resolution and GPU memory (as HCFR's CGenerator::Init).
    func connect(timeout: TimeInterval = 5) async throws {
        try await run { try self.connectBlocking(timeout: timeout) }
    }

    /// Sends a command and waits for the Pi's answer (RB8PG_send).
    func send(_ message: String) async throws {
        _ = try await run { try self.exchange(message) }
    }

    /// Sends a command and returns the Pi's answer without the end bytes (RB8PG_get).
    func get(_ message: String) async throws -> String {
        try await run { try self.exchange(message) }
    }

    /// Says goodbye ("QUIT", as RB8PG_close) and closes the connection. Does not wait.
    func close() {
        queue.async {
            guard self.fd >= 0 else { return }
            _ = try? self.exchange("QUIT", timeout: 1)
            _ = Self.closeSocket(self.fd)
            self.fd = -1
        }
    }

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            queue.async { c.resume(with: Result { try body() }) }
        }
    }

    private func connectBlocking(timeout: TimeInterval) throws {
        if fd >= 0 { _ = Self.closeSocket(fd); fd = -1 }
        guard var addr = Self.sockaddrIn(host, port: Self.commandPort) else { throw PGeneratorError.badAddress(host) }
        let s = socket(AF_INET, Self.sockStream, 0)
        guard s >= 0 else { throw PGeneratorError.connectFailed(host, Self.errnoText()) }
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
        // Non-blocking connect, so an absent Pi fails after `timeout` instead of the system's ~75 s
        let fl = fcntl(s, F_GETFL, 0)
        _ = fcntl(s, F_SETFL, fl | O_NONBLOCK)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Self.sysConnect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r != 0 {
            guard errno == EINPROGRESS else {
                let why = Self.errnoText(); _ = Self.closeSocket(s)
                throw PGeneratorError.connectFailed(host, why)
            }
            var p = pollfd(fd: s, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&p, 1, Int32(timeout * 1000))
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &len)
            if ready <= 0 || err != 0 {
                _ = Self.closeSocket(s)
                throw PGeneratorError.connectFailed(host, ready <= 0 ? "No answer from the Raspberry Pi (port 85)."
                                                                     : String(cString: strerror(err)))
            }
        }
        _ = fcntl(s, F_SETFL, fl)
        fd = s

        // Resolution, "OK:1920x1080"
        let res = try exchange("CMD:GET_RESOLUTION")
        let parts = res.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.first == "OK", parts.count == 2 else {
            throw PGeneratorError.communication("Failed to get rPi resolution (answer: \"\(res)\").")
        }
        let wh = parts[1].split(separator: "x").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        if wh.count >= 2, wh[0] > 0, wh[1] > 0 { width = wh[0]; height = wh[1] }
        // GPU memory, "OK:256M" (not essential)
        if let mem = try? exchange("CMD:GET_GPU_MEMORY"), mem.hasPrefix("OK:") {
            gpuMemoryMB = Int(mem.dropFirst(3).prefix { $0.isNumber }) ?? 0
        }
    }

    /// Sends one message (+ 0x02 0x0D) and reads the answer up to its 0x02 0x0D.
    private func exchange(_ message: String, timeout: TimeInterval = 5) throws -> String {
        guard fd >= 0 else { throw PGeneratorError.communication("Not connected to the Raspberry Pi.") }
        let out = Array(message.utf8) + Self.terminator
        var off = 0
        while off < out.count {
            let n = out[off...].withUnsafeBytes { Self.sysSend(fd, $0.baseAddress, $0.count, Self.sendFlags) }
            if n <= 0 { try fail("Send failed (\(Self.errnoText())).") }
            off += n
        }
        var reply: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 1024)
        let deadline = Date().addingTimeInterval(timeout)
        while !reply.ends(with: Self.terminator) {
            // Once part of the answer has arrived, a short pause ends it: some PGenerator
            // versions (PGenerator+) don't send the end bytes, and waiting for them until the
            // timeout made every command take seconds
            let left = reply.isEmpty ? deadline.timeIntervalSinceNow : min(deadline.timeIntervalSinceNow, 0.15)
            guard left > 0, Self.waitReadable(fd, seconds: left) else {
                // Some PGenerator versions may not end every answer: accept what arrived
                if !reply.isEmpty { break }
                try fail("No answer from the Raspberry Pi to \"\(message.prefix(40))\".")
            }
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { try fail("The Raspberry Pi closed the connection.") }
            reply += buf[0..<n]
        }
        if reply.ends(with: Self.terminator) { reply.removeLast(2) }
        return String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops the connection (the next command reconnects) and throws.
    private func fail(_ why: String) throws -> Never {
        if fd >= 0 { _ = Self.closeSocket(fd); fd = -1 }
        throw PGeneratorError.communication(why)
    }

    // MARK: - Pattern messages (as HCFR's CGDIGenerator::DisplayRGBColorrPI)

    /// Patch of `rgb` (8-bit codes) covering `areaPercent` of the screen, centered, on `background`.
    func rectangleMessage(rgb: [Int], background: [Int], areaPercent: Double) -> String {
        let k = sqrt(min(max(areaPercent, 1), 100) / 100)
        let w = Int(k * Double(width)), h = Int(k * Double(height))
        let c = rgb.map { min(max($0, 0), 255) }, b = background.map { min(max($0, 0), 255) }
        return "RGB=RECTANGLE;\(w),\(h);100;\(c[0]),\(c[1]),\(c[2]);\(b[0]),\(b[1]),\(b[2]);-1,-1,0,0"
    }

    /// ANSI contrast checkerboard: the images that PGenerator keeps for HCFR (FullScreenWindow.cpp,
    /// "ansi1.png" black center / "ansi2.png" white center in /var/lib/PGenerator/images-HCFR/).
    func ansiMessage(inverted: Bool) -> String {
        "RGB=IMAGE;\(width),\(height),;100;255,255,255;0,0,0;-1,-1;/var/lib/PGenerator/images-HCFR/"
            + (inverted ? "ansi2.png" : "ansi1.png")
    }

    /// Text line on the Pi screen (HCFR shows "Initializing PGenerator at…" / "End of sequence").
    static func textMessage(_ text: String) -> String {
        "RGB=TEXT;12,0;100;16,128,128;0,0,0;100,300;\(text)"
    }

    /// Back to PGenerator's own black screen (HCFR sends it when a run ends).
    static let idleMessage = "TESTTEMPLATE:PatternDynamic:0,0,0"

    // MARK: - Socket helpers

    #if canImport(Darwin)
    static let sockStream = SOCK_STREAM
    static let sockDgram = SOCK_DGRAM
    static let sendFlags: Int32 = 0
    #else
    static let sockStream = Int32(SOCK_STREAM.rawValue)
    static let sockDgram = Int32(SOCK_DGRAM.rawValue)
    static let sendFlags = Int32(MSG_NOSIGNAL)
    #endif

    static func sockaddrIn(_ ip: String, port: UInt16) -> sockaddr_in? {
        var a = sockaddr_in()
        #if canImport(Darwin)
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &a.sin_addr) == 1 else { return nil }
        return a
    }

    static func isValidIPv4(_ ip: String) -> Bool { sockaddrIn(ip, port: 0) != nil }

    static func ipString(_ a: in_addr) -> String {
        var a = a
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &a, &buf, socklen_t(buf.count))
        return String(cString: buf)
    }

    static func waitReadable(_ s: Int32, seconds: TimeInterval) -> Bool {
        var p = pollfd(fd: s, events: Int16(POLLIN), revents: 0)
        return poll(&p, 1, Int32(max(seconds, 0.001) * 1000)) > 0
    }

    // Qualified, because this class has its own connect / send / close methods
    #if canImport(Darwin)
    static func closeSocket(_ s: Int32) -> Int32 { Darwin.close(s) }
    static func sysConnect(_ s: Int32, _ a: UnsafePointer<sockaddr>, _ l: socklen_t) -> Int32 { Darwin.connect(s, a, l) }
    static func sysSend(_ s: Int32, _ p: UnsafeRawPointer?, _ n: Int, _ f: Int32) -> Int { Darwin.send(s, p, n, f) }
    #else
    static func closeSocket(_ s: Int32) -> Int32 { Glibc.close(s) }
    static func sysConnect(_ s: Int32, _ a: UnsafePointer<sockaddr>, _ l: socklen_t) -> Int32 { Glibc.connect(s, a, l) }
    static func sysSend(_ s: Int32, _ p: UnsafeRawPointer?, _ n: Int, _ f: Int32) -> Int { Glibc.send(s, p, n, f) }
    #endif

    static func errnoText() -> String { String(cString: strerror(errno)) }
}

private extension Array where Element == UInt8 {
    func ends(with suffix: [UInt8]) -> Bool { count >= suffix.count && Array(self[(count - suffix.count)...]) == suffix }
}
