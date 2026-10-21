// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// madVR Envy / madTPG pattern generator support added in 2026.
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

/// Errors of the madVR generator.
enum MadVRError: LocalizedError {
    case badAddress(String)
    case connectFailed(String)
    case noTestPattern(String)
    case communication(String)

    var errorDescription: String? {
        switch self {
        case .badAddress(let a):
            return "\"\(a)\" is not a valid IPv4 address for madVR."
        case .connectFailed(let host):
            return "Could not connect to madVR at \(host).\n\nCheck that the madVR Envy is on (or that madTPG "
                + "is running on that PC), that \"enable network access\" is on in madTPG, that it is on the same "
                + "network as this Mac, and the address in Generator → madVR address. If macOS asked for "
                + "permission to find devices on the local network, allow it "
                + "(System Settings → Privacy & Security → Local Network)."
        case .noTestPattern(let host):
            return "madVR at \(host) answered, but did not start its test pattern generator (madTPG)."
        case .communication(let why):
            return "Error communicating with madVR\n\n\(why)"
        }
    }
}

/// Client for the madVR network protocol, which madTPG (madVR's test pattern generator, on a
/// Windows PC) and the madVR Envy video processors understand; it is what calibration programs
/// use through madHcNet on Windows.
///
/// Packets (little endian): "mad." · data length (Int32) · CRC-32 of the first 8 bytes (UInt32) ·
/// data = process id (Int32) · module (Int64) · command number (Int32) · component length (Int32) ·
/// component (ASCII, "madTPG" or empty) · instance (Int64) · command length (Int32) · command
/// (ASCII) · parameters length (Int32) · parameters (text in UTF-16LE, or binary).
///
/// Session: TCP to one of madVR's ports → both sides send "hello" (UTF-16LE "key=value" lines
/// separated by tabs) → the side with the higher IP address (or, on the same computer, the higher
/// process id) sends "confirm" → commands to the madTPG component, each answered by a "reply"
/// with the same command number ("+" = done) → "bye".
final class MadVRClient: @unchecked Sendable {
    /// madVR's TCP ports, tried in this order.
    static let ports: [UInt16] = [60562, 51130, 54184, 41916, 19902]

    let host: String
    /// From madVR's hello: computer name and madVR version (e.g. "ENVY · madVR 1.1.2.3").
    private(set) var peerDescription = ""
    private(set) var port: UInt16 = 0

    private let queue = DispatchQueue(label: "MadVRClient")
    private var fd: Int32 = -1
    private var commandNo: Int32 = 0
    private var instance: Int64 = 0
    private var buffer: [UInt8] = []
    private let pid = Int32(getpid())
    private static let module: Int64 = 0x4843_4652_6D61_6331   // "HCFRmac1", any value works

    var isConnected: Bool { queue.sync { fd >= 0 } }

    init(host: String) { self.host = host }
    deinit { if fd >= 0 { _ = PGeneratorClient.closeSocket(fd) } }

    // MARK: - Public commands

    /// Connects, introduces itself and starts madTPG's test pattern mode.
    func connect(timeout: TimeInterval = 4) async throws {
        try await run { try self.connectBlocking(timeout: timeout) }
    }

    /// Shows `rgb` (0…1 of madVR's own output range) covering `areaPercent` of the screen, on
    /// `background` (0…1).
    func show(rgb: [Double], background: Double, areaPercent: Double) async throws {
        try await run {
            try self.setPatternConfig(areaPercent: areaPercent, backgroundPercent: background * 100)
            let v = rgb.map { Self.number(min(max($0, 0), 1)) }.joined(separator: "|")
            try self.command("ShowRGB", text: v)
        }
    }

    /// madTPG options of HCFR for Windows' generator page: measure without madVR's own calibration
    /// (3D LUT and gamma ramp), madTPG's HDR button and its on-screen display.
    func applyOptions(disable3DLUT: Bool, disableCalibration: Bool, hdr: Bool, osd: Bool) async {
        _ = try? await run {
            if disableCalibration {
                var ramp: [UInt8] = []
                for _ in 0..<3 { for i in 0..<256 { ramp += Self.le(UInt16(i * 257)) } }
                _ = try? self.command("SetDeviceGammaRamp", binary: ramp)
            }
            if disable3DLUT { _ = try? self.command("Disable3dlut") }
            _ = try? self.command("SetDisableOsdButton", text: osd ? "-" : "+")
            _ = try? self.command("SetHdrButton", text: hdr ? "+" : "-")
        }
    }

    /// Text on madTPG's on-screen display.
    func osd(_ text: String) async throws {
        _ = try await run { try self.command("SetOsdText", text: text) }
    }

    /// Ends the test pattern mode and says goodbye. Does not wait.
    func close() {
        queue.async {
            guard self.fd >= 0 else { return }
            _ = try? self.command("StopTestPattern", timeout: 1)
            _ = try? self.sendPacket(command: "bye", params: [], component: "madTPG")
            _ = PGeneratorClient.closeSocket(self.fd)
            self.fd = -1
        }
    }

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            queue.async { c.resume(with: Result { try body() }) }
        }
    }

    // MARK: - Session

    private var lastPatternConfig: (area: Int, background: Int)?

    private func setPatternConfig(areaPercent: Double, backgroundPercent: Double) throws {
        let area = Int(min(max(areaPercent, 1), 100).rounded()), bg = Int(backgroundPercent.rounded())
        if let last = lastPatternConfig, last == (area, bg) { return }
        // Keep madTPG's background mode and black border as they are
        var mode = 0, border = 0
        if let r = try? command("GetPatternConfig"), r.count == 16 {
            mode = Int(Self.int32(r, 8)); border = Int(Self.int32(r, 12))
        }
        try command("SetPatternConfig", text: "\(area)|\(bg)|\(mode)|\(border)")
        lastPatternConfig = (area, bg)
    }

    private func connectBlocking(timeout: TimeInterval) throws {
        if fd >= 0 { _ = PGeneratorClient.closeSocket(fd); fd = -1 }
        guard PGeneratorClient.isValidIPv4(host) else { throw MadVRError.badAddress(host) }
        lastPatternConfig = nil
        buffer = []
        var connected = false
        for p in Self.ports {
            if let s = try? Self.tcpConnect(host, port: p, timeout: 1.5) { fd = s; port = p; connected = true; break }
        }
        guard connected else { throw MadVRError.connectFailed(host) }

        try sendPacket(command: "hello", params: Self.utf16(helloText()), component: "")
        var helloSeen = false, confirmed = false
        let deadline = Date().addingTimeInterval(timeout)
        while !(helloSeen && confirmed) {
            guard let p = try readPacket(until: deadline) else { break }
            switch p.command {
            case "hello":
                guard !p.component.isEmpty else { continue }
                helloSeen = true
                instance = p.instance
                let info = Self.keyValues(p.params)
                let name = info["computerName"] ?? host
                let version = info["mvrVersion"].map { " · madVR \($0)" } ?? ""
                peerDescription = name + version
                if try isMaster(peerProcessId: p.processId) {
                    try sendPacket(command: "confirm", params: [], component: "")
                    confirmed = true
                }
            case "confirm":
                confirmed = true
            case "bye":
                try fail("madVR closed the connection.")
            default:
                continue
            }
        }
        guard helloSeen else { try fail("madVR did not introduce itself (no \"hello\").") }
        do {
            try command("StartTestPattern")
        } catch {
            _ = PGeneratorClient.closeSocket(fd); fd = -1
            throw MadVRError.noTestPattern(host)
        }
    }

    private func helloText() -> String {
        var name = [CChar](repeating: 0, count: 256)
        gethostname(&name, name.count)
        let computer = String(cString: name).uppercased()
        let user = ProcessInfo.processInfo.userName
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return [("computerName", computer), ("userName", user), ("os", "macOS \(os)"),
                ("exeFile", "HCFR Colorimeter"), ("exeVersion", AboutPanel.version), ("exeDescr", "HCFR Colorimeter for macOS"),
                ("exeIcon", "")]
            .map { "\($0.0)=\($0.1)\t" }.joined()
    }

    /// The side with the higher IP address confirms the connection (same computer: higher process id).
    private func isMaster(peerProcessId: Int32) throws -> Bool {
        var local = sockaddr_in(), remote = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &remote) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &len) } }
        let l = UInt32(bigEndian: local.sin_addr.s_addr), r = UInt32(bigEndian: remote.sin_addr.s_addr)
        return l > r || (l == r && peerProcessId < pid)
    }

    /// Sends a command to madTPG and waits for its reply; returns the reply's parameters.
    @discardableResult
    private func command(_ name: String, text: String? = nil, binary: [UInt8]? = nil, timeout: TimeInterval = 4) throws -> [UInt8] {
        let no = try sendPacket(command: name, params: binary ?? text.map(Self.utf16) ?? [], component: "madTPG")
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            guard let p = try readPacket(until: deadline) else { try fail("No answer from madVR to \"\(name)\".") }
            if p.command == "bye" { try fail("madVR closed the connection.") }
            guard p.command == "reply", p.commandNo == no else { continue }
            let text = String(decoding: p.params.filter { $0 != 0 }, as: UTF8.self)
            if text == "-" { throw MadVRError.communication("madVR refused \"\(name)\".") }
            return p.params
        }
    }

    // MARK: - Packets

    private struct Packet {
        var processId: Int32
        var commandNo: Int32
        var component: String
        var instance: Int64
        var command: String
        var params: [UInt8]
    }

    @discardableResult
    private func sendPacket(command: String, params: [UInt8], component: String) throws -> Int32 {
        guard fd >= 0 else { throw MadVRError.communication("Not connected to madVR.") }
        commandNo += 1
        let packet = Self.assemble(processId: pid, module: Self.module, commandNo: commandNo, component: component,
                                   instance: component == "madTPG" ? instance : 0, command: command, params: params)
        var off = 0
        while off < packet.count {
            let n = packet[off...].withUnsafeBytes { PGeneratorClient.sysSend(fd, $0.baseAddress, $0.count, PGeneratorClient.sendFlags) }
            if n <= 0 { try fail("Send failed (\(PGeneratorClient.errnoText())).") }
            off += n
        }
        return commandNo
    }

    static func assemble(processId: Int32, module: Int64, commandNo: Int32, component: String, instance: Int64,
                         command: String, params: [UInt8]) -> [UInt8] {
        var d: [UInt8] = []
        d += le(processId); d += le(module); d += le(commandNo)
        let comp = Array(component.utf8), cmd = Array(command.utf8)
        d += le(Int32(comp.count)); d += comp
        d += le(instance)
        d += le(Int32(cmd.count)); d += cmd
        d += le(Int32(params.count)); d += params
        var head = Array("mad.".utf8) + le(Int32(d.count))
        head += le(crc32(head))
        return head + d
    }

    /// Next packet, or nil when `deadline` passes.
    private func readPacket(until deadline: Date) throws -> Packet? {
        while true {
            if let p = try Self.parse(&buffer) { return p.packet }
            let left = deadline.timeIntervalSinceNow
            guard left > 0, PGeneratorClient.waitReadable(fd, seconds: left) else { return nil }
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { try fail("madVR closed the connection.") }
            buffer += buf[0..<n]
        }
    }

    private static func parse(_ b: inout [UInt8]) throws -> (packet: Packet, Void)? {
        guard b.count >= 12 else { return nil }
        guard b[0] == 0x6D, b[1] == 0x61, b[2] == 0x64, b[3] == 0x2E else {
            b = []
            throw MadVRError.communication("Invalid data from madVR.")
        }
        let len = Int(int32(b, 4))
        guard len >= 0, b.count >= 12 + len else { return nil }
        guard UInt32(bitPattern: int32(b, 8)) == crc32(Array(b[0..<8])) else {
            b = []
            throw MadVRError.communication("Invalid packet from madVR (CRC).")
        }
        let d = Array(b[12..<(12 + len)])
        b.removeFirst(12 + len)
        var i = 0
        func take(_ n: Int) throws -> [UInt8] {
            guard i + n <= d.count else { throw MadVRError.communication("Corrupt packet from madVR.") }
            defer { i += n }
            return Array(d[i..<(i + n)])
        }
        let pid = int32(try take(4), 0)
        _ = try take(8)
        let no = int32(try take(4), 0)
        let comp = String(decoding: try take(Int(int32(try take(4), 0))), as: UTF8.self)
        let inst = int64(try take(8), 0)
        let cmd = String(decoding: try take(Int(int32(try take(4), 0))), as: UTF8.self)
        let params = try take(Int(int32(try take(4), 0)))
        return (Packet(processId: pid, commandNo: no, component: comp, instance: inst, command: cmd, params: params), ())
    }

    private func fail(_ why: String) throws -> Never {
        if fd >= 0 { _ = PGeneratorClient.closeSocket(fd); fd = -1 }
        throw MadVRError.communication(why)
    }

    // MARK: - Helpers

    static func tcpConnect(_ host: String, port: UInt16, timeout: TimeInterval) throws -> Int32 {
        guard var addr = PGeneratorClient.sockaddrIn(host, port: port) else { throw MadVRError.badAddress(host) }
        let s = socket(AF_INET, PGeneratorClient.sockStream, 0)
        guard s >= 0 else { throw MadVRError.connectFailed(host) }
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
        let fl = fcntl(s, F_GETFL, 0)
        _ = fcntl(s, F_SETFL, fl | O_NONBLOCK)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                PGeneratorClient.sysConnect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r != 0 {
            guard errno == EINPROGRESS else { _ = PGeneratorClient.closeSocket(s); throw MadVRError.connectFailed(host) }
            var p = pollfd(fd: s, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&p, 1, Int32(timeout * 1000))
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &len)
            if ready <= 0 || err != 0 { _ = PGeneratorClient.closeSocket(s); throw MadVRError.connectFailed(host) }
        }
        _ = fcntl(s, F_SETFL, fl)
        return s
    }

    /// Numbers for madTPG's text parameters ("0.5", "1"), always with a decimal point.
    static func number(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func utf16(_ s: String) -> [UInt8] { s.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }

    static func keyValues(_ params: [UInt8]) -> [String: String] {
        var units: [UInt16] = []
        var i = 0
        while i + 1 < params.count { units.append(UInt16(params[i]) | UInt16(params[i + 1]) << 8); i += 2 }
        var d: [String: String] = [:]
        for item in String(decoding: units, as: UTF16.self).split(whereSeparator: { $0 == "\t" || $0 == "\n" || $0 == "\r" }) {
            let kv = item.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { d[kv[0]] = kv[1] }
        }
        return d
    }

    static func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
    static func int32(_ b: [UInt8], _ o: Int) -> Int32 {
        Int32(bitPattern: UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24)
    }
    static func int64(_ b: [UInt8], _ o: Int) -> Int64 {
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(b[o + k]) << (8 * k) }
        return Int64(bitPattern: v)
    }

    static func crc32(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data {
            c ^= UInt32(byte)
            for _ in 0..<8 { c = (c >> 1) ^ (0xEDB8_8320 & (0 &- (c & 1))) }
        }
        return ~c
    }
}
