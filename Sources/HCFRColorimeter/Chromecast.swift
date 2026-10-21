// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Chromecast pattern generator (HCFR for Windows' "ccast" display mode, from ArgyllCMS's
// libccast) added in 2026.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation
import Network

enum ChromecastError: LocalizedError {
    case notFound
    case connectFailed(String)
    case launchFailed(String)
    case communication(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Chromecast was found on the network.\n\nCheck that the Chromecast (or Google TV) is on and "
                + "on the same network as this Mac. If macOS asked for permission to find devices on the local "
                + "network, allow it (System Settings → Privacy & Security → Local Network)."
        case .connectFailed(let name):
            return "Could not connect to the Chromecast \"\(name)\"."
        case .launchFailed(let name):
            return "The Chromecast \"\(name)\" did not start the pattern receiver."
        case .communication(let why):
            return "Error communicating with the Chromecast\n\n\(why)"
        }
    }
}

/// A Chromecast found on the network (Bonjour _googlecast._tcp).
struct ChromecastDevice: Hashable, Identifiable {
    var name: String
    var model: String
    var endpoint: NWEndpoint
    var id: String { name }

    /// A Chromecast given by its IP address (when Bonjour does not find it).
    static func address(_ ip: String) -> ChromecastDevice {
        ChromecastDevice(name: ip, model: "", endpoint: .hostPort(host: NWEndpoint.Host(ip), port: 8009))
    }
}

/// Chromecast as pattern generator, as ArgyllCMS's libccast (which HCFR for Windows uses):
/// Cast v2 protocol (TLS to port 8009, length-prefixed protobuf CastMessage with JSON payloads).
/// It first launches the pattern generator receiver (app B5C2CBFC, which draws the patch the
/// sender sends as a PNG with its background, position and size); if that receiver is not
/// available it uses Google's Default Media Receiver (CC1AD845), which shows a whole-screen PNG
/// image served by this Mac (slower: it fades between images).
final class ChromecastClient: @unchecked Sendable {
    static let patternReceiver = "B5C2CBFC"
    static let defaultReceiver = "CC1AD845"
    private static let nsConnection = "urn:x-cast:com.google.cast.tp.connection"
    private static let nsHeartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    private static let nsReceiver = "urn:x-cast:com.google.cast.receiver"
    private static let nsMedia = "urn:x-cast:com.google.cast.media"
    private static let nsPattern = "urn:x-cast:net.hoech.cast.patterngenerator"

    let device: ChromecastDevice
    /// The pattern generator receiver (fast, exact patch) or the default receiver (whole image).
    private(set) var usesPatternReceiver = false
    /// Extra wait after each patch (libccast's load delay): the default receiver fades.
    var loadDelay: TimeInterval { usesPatternReceiver ? 0.35 : 1.5 }

    private let queue = DispatchQueue(label: "ChromecastClient")
    private var connection: NWConnection?
    private var buffer = Data()
    private var requestId = 0
    private var transportId: String?
    private var sessionId: String?
    private var heartbeat: DispatchSourceTimer?
    private var waiters: [(id: UUID, match: ([String: Any]) -> Bool, done: (Result<[String: Any], Error>) -> Void)] = []
    private var server: PatchServer?
    private var localIP: String?

    init(device: ChromecastDevice) { self.device = device }
    deinit { connection?.cancel(); heartbeat?.cancel(); server?.stop() }

    // MARK: - Discovery

    /// Chromecasts on the local network (their friendly names), looking for `timeout` seconds.
    static func discover(timeout: TimeInterval = 3) async -> [ChromecastDevice] {
        await withCheckedContinuation { (cont: CheckedContinuation<[ChromecastDevice], Never>) in
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: params)
            let q = DispatchQueue(label: "ChromecastBrowser")
            var found: [String: ChromecastDevice] = [:]
            var finished = false
            func finish() {
                guard !finished else { return }
                finished = true
                browser.cancel()
                cont.resume(returning: found.values.sorted { $0.name < $1.name })
            }
            browser.browseResultsChangedHandler = { results, _ in
                for r in results {
                    var name = "", model = ""
                    if case .service(let n, _, _, _) = r.endpoint { name = n }
                    if case .bonjour(let txt) = r.metadata {
                        let d = txt.dictionary
                        if let fn = d["fn"], !fn.isEmpty { name = fn }
                        model = d["md"] ?? ""
                    }
                    found[name] = ChromecastDevice(name: name, model: model, endpoint: r.endpoint)
                }
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { q.async { finish() } }
            }
            browser.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) { finish() }
        }
    }

    // MARK: - Session

    /// Connects, launches the receiver and connects to it.
    func connect() async throws {
        let tls = NWProtocolTLS.Options()
        // Chromecasts use self-signed certificates (libccast does not check them either)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, done in done(true) }, queue)
        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let c = NWConnection(to: device.endpoint, using: params)
        connection = c
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            let name = device.name
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume() }
                case .failed, .cancelled:
                    if !resumed { resumed = true; cont.resume(throwing: ChromecastError.connectFailed(name)) }
                    else { self.failAll(ChromecastError.communication("The connection was closed")) }
                default: break
                }
            }
            c.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 8) {
                if !resumed { resumed = true; c.cancel(); cont.resume(throwing: ChromecastError.connectFailed(name)) }
            }
        }
        if case .hostPort(let h, _)? = c.currentPath?.localEndpoint {
            localIP = "\(h)".components(separatedBy: "%").first
        }
        receiveLoop()
        send(Self.nsConnection, to: "receiver-0", ["type": "CONNECT"])
        startHeartbeat()

        // The pattern receiver first, else the default receiver
        for app in [Self.patternReceiver, Self.defaultReceiver] {
            let id = nextId()
            send(Self.nsReceiver, to: "receiver-0", ["requestId": id, "type": "LAUNCH", "appId": app])
            let reply: [String: Any]
            do {
                reply = try await wait(timeout: 20) { m in
                    if (m["type"] as? String) == "LAUNCH_ERROR", (m["requestId"] as? Int) == id { return true }
                    return Self.transport(in: m, app: app) != nil
                }
            } catch {
                continue
            }
            if let t = Self.transport(in: reply, app: app) {
                transportId = t.0
                sessionId = t.1
                usesPatternReceiver = app == Self.patternReceiver
                break
            }
        }
        guard let transportId else { close(); throw ChromecastError.launchFailed(device.name) }
        send(Self.nsConnection, to: transportId, ["type": "CONNECT"])
        if !usesPatternReceiver {
            let s = PatchServer()
            try s.start()
            server = s
        }
    }

    /// Shows a patch: `rgb` and `background` 0…1 (8-bit values already chosen by the caller),
    /// `area` share of the screen (1–100 %), `offset` of the center as a share of the screen.
    func show(rgb: [Double], background: Double, areaPercent area: Double, offset: CGPoint = .zero) async throws {
        guard let transportId else { throw ChromecastError.communication("Not connected") }
        let side = min(1, max(0.01, (area / 100).squareRoot()))
        let code = { (v: Double) in UInt8(max(0, min(255, (v * 255).rounded()))) }
        let fg = rgb.map(code), bg = code(background)
        // offset: of the patch center, share of the screen (−0.5…0.5, y down) → share of the free space
        let free = { (c: Double) in side >= 1 ? 0.5 : min(1, max(0, (c - side / 2) / (1 - side))) }
        let ox = free(0.5 + offset.x), oy = free(0.5 + offset.y)
        if usesPatternReceiver {
            let png = PNG.solid(width: 8, height: 8, rgb: fg)
            // libccast: size as a multiple of 10 % of the screen width; height in width units (16:9)
            let id = nextId()
            send(Self.nsPattern, to: transportId, [
                "requestId": id,
                "foreground": ["contentType": "image/png", "encoding": "base64",
                               "data": png.base64EncodedString(), "size": png.base64EncodedString().count],
                "background": "rgb(\(bg), \(bg), \(bg))",
                "offset": [side >= 1 ? 0 : ox, side >= 1 ? 0 : oy],
                "scale": [side / 0.1, side * 9 / 16 / 0.1],
            ])
            _ = try? await wait(timeout: 5) { ($0["requestId"] as? Int) == id }
        } else {
            guard let server, let ip = localIP else { throw ChromecastError.communication("No local web server") }
            // Whole screen image (16:9), patch drawn in it; the receiver scales it to the screen
            let w = 384, h = 216
            let pw = max(1, Int((Double(w) * side).rounded())), ph = max(1, Int((Double(h) * side).rounded()))
            let x0 = Int(Double(w - pw) * ox), y0 = Int(Double(h - ph) * oy)
            let png = PNG.patch(width: w, height: h, background: [bg, bg, bg], rect: (x0, y0, pw, ph), rgb: fg)
            let url = server.publish(png, host: ip)
            let id = nextId()
            send(Self.nsMedia, to: transportId, [
                "requestId": id, "type": "LOAD", "autoplay": true,
                "media": ["contentId": url, "contentType": "image/png", "streamType": "NONE"],
            ])
            let r = try await wait(timeout: 15) { ($0["requestId"] as? Int) == id }
            if let t = r["type"] as? String, t == "LOAD_FAILED" || t == "LOAD_CANCELLED" || t == "INVALID_REQUEST" {
                throw ChromecastError.communication("The Chromecast did not load the pattern (\(t))")
            }
        }
        try await Task.sleep(nanoseconds: UInt64(loadDelay * 1e9))
    }

    func close() {
        queue.async { [self] in
            if let sessionId {
                sendNow(Self.nsReceiver, to: "receiver-0", ["requestId": nextIdNow(), "type": "STOP", "sessionId": sessionId])
            }
            if let transportId { sendNow(Self.nsConnection, to: transportId, ["type": "CLOSE"]) }
            sendNow(Self.nsConnection, to: "receiver-0", ["type": "CLOSE"])
            heartbeat?.cancel(); heartbeat = nil
            server?.stop(); server = nil
            let c = connection
            connection = nil
            queue.asyncAfter(deadline: .now() + 0.3) { c?.cancel() }
            failAllNow(ChromecastError.communication("Closed"))
        }
    }

    // MARK: - Messages

    private static func transport(in m: [String: Any], app: String) -> (String, String)? {
        guard (m["type"] as? String) == "RECEIVER_STATUS",
              let status = m["status"] as? [String: Any],
              let apps = status["applications"] as? [[String: Any]] else { return nil }
        for a in apps where (a["appId"] as? String) == app {
            if let t = a["transportId"] as? String, let s = a["sessionId"] as? String { return (t, s) }
        }
        return nil
    }

    private func nextId() -> Int { queue.sync { nextIdNow() } }
    private func nextIdNow() -> Int { requestId += 1; return requestId }

    private func send(_ ns: String, to dest: String, _ json: [String: Any]) {
        queue.async { self.sendNow(ns, to: dest, json) }
    }

    private func sendNow(_ ns: String, to dest: String, _ json: [String: Any]) {
        guard let connection,
              let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        var m = Data()
        m.append(0x08); m.append(0x00)                       // protocol_version CASTV2_1_0
        Self.field(&m, 2, "sender-0")
        Self.field(&m, 3, dest)
        Self.field(&m, 4, ns)
        m.append(0x28); m.append(0x00)                       // payload_type STRING
        Self.field(&m, 6, text)
        var frame = Data()
        let n = UInt32(m.count)
        frame.append(contentsOf: [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
        frame.append(m)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private static func field(_ d: inout Data, _ number: UInt8, _ s: String) {
        let b = Array(s.utf8)
        d.append((number << 3) | 2)
        var len = b.count
        repeat {
            var byte = UInt8(len & 0x7F)
            len >>= 7
            if len > 0 { byte |= 0x80 }
            d.append(byte)
        } while len > 0
        d.append(contentsOf: b)
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.buffer.append(data); self.parseFrames() }
            if complete || error != nil {
                self.failAllNow(ChromecastError.communication("The connection was closed"))
                return
            }
            self.receiveLoop()
        }
    }

    private func parseFrames() {
        while buffer.count >= 4 {
            let b = [UInt8](buffer.prefix(4))
            let n = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            guard buffer.count >= 4 + n else { return }
            let msg = [UInt8](buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + n))
            buffer.removeFirst(4 + n)
            handle(Self.decode(msg))
        }
    }

    /// Fields 2 (source), 3 (destination), 4 (namespace) and 6 (JSON payload) of a CastMessage.
    private static func decode(_ b: [UInt8]) -> (source: String, ns: String, payload: String) {
        var i = 0, source = "", ns = "", payload = ""
        func varint() -> Int {
            var v = 0, shift = 0
            while i < b.count {
                let x = b[i]; i += 1
                v |= Int(x & 0x7F) << shift
                if x & 0x80 == 0 { break }
                shift += 7
            }
            return v
        }
        while i < b.count {
            let key = varint(), number = key >> 3, wire = key & 7
            if wire == 0 { _ = varint(); continue }
            if wire != 2 { break }
            let len = varint()
            guard i + len <= b.count else { break }
            let s = String(decoding: b[i ..< i + len], as: UTF8.self)
            i += len
            switch number {
            case 2: source = s
            case 4: ns = s
            case 6: payload = s
            default: break
            }
        }
        return (source, ns, payload)
    }

    private func handle(_ m: (source: String, ns: String, payload: String)) {
        guard let data = m.payload.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if m.ns == Self.nsHeartbeat, (json["type"] as? String) == "PING" {
            sendNow(Self.nsHeartbeat, to: m.source, ["type": "PONG"])
            return
        }
        if m.ns == Self.nsConnection, (json["type"] as? String) == "CLOSE" {
            failAllNow(ChromecastError.communication("The Chromecast closed the session"))
            return
        }
        for w in waiters where w.match(json) {
            waiters.removeAll { $0.id == w.id }
            w.done(.success(json))
        }
    }

    private func wait(timeout: TimeInterval, _ match: @escaping ([String: Any]) -> Bool) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
            queue.async { [self] in
                let id = UUID()
                waiters.append((id, match, { cont.resume(with: $0) }))
                queue.asyncAfter(deadline: .now() + timeout) { [self] in
                    if let w = waiters.first(where: { $0.id == id }) {
                        waiters.removeAll { $0.id == id }
                        w.done(.failure(ChromecastError.communication("No answer from the Chromecast")))
                    }
                }
            }
        }
    }

    private func failAll(_ e: Error) { queue.async { self.failAllNow(e) } }
    private func failAllNow(_ e: Error) {
        let w = waiters
        waiters.removeAll()
        w.forEach { $0.done(.failure(e)) }
    }

    private func startHeartbeat() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.sendNow(Self.nsHeartbeat, to: "receiver-0", ["type": "PING"]) }
        t.resume()
        heartbeat = t
    }
}

/// The web server the default receiver loads the patterns from (as libccast's, port 8081 when free).
final class PatchServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "PatchServer")
    private var png = Data()
    private var number = 0

    func start() throws {
        let l = try NWListener(using: .tcp)
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.start(queue: queue)
        listener = l
        // Wait until the port is known
        for _ in 0..<50 where l.port == nil { Thread.sleep(forTimeInterval: 0.02) }
    }

    func stop() { listener?.cancel(); listener = nil }

    /// Makes `png` the current pattern and returns its URL (a new name each time, so the
    /// receiver does not use a cached image).
    func publish(_ data: Data, host: String) -> String {
        queue.sync { png = data; number += 1 }
        let port = listener?.port?.rawValue ?? 0
        return "http://\(host):\(port)/tpatch_\(queue.sync { number }).png"
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, _, _ in
            guard let self else { c.cancel(); return }
            var head = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(self.png.count)\r\n"
            head += "Cache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            var out = Data(head.utf8)
            out.append(self.png)
            c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
        }
    }
}

/// Minimal PNG writer (8-bit RGB, no color profile, so the values reach the display unchanged).
enum PNG {
    static func solid(width: Int, height: Int, rgb: [UInt8]) -> Data {
        patch(width: width, height: height, background: rgb, rect: (0, 0, width, height), rgb: rgb)
    }

    static func patch(width: Int, height: Int, background: [UInt8], rect: (Int, Int, Int, Int), rgb: [UInt8]) -> Data {
        var raw = [UInt8]()
        raw.reserveCapacity((width * 3 + 1) * height)
        for y in 0..<height {
            raw.append(0)   // filter: none
            let inY = y >= rect.1 && y < rect.1 + rect.3
            for x in 0..<width {
                let c = inY && x >= rect.0 && x < rect.0 + rect.2 ? rgb : background
                raw.append(c[0]); raw.append(c[1]); raw.append(c[2])
            }
        }
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var ihdr = [UInt8]()
        ihdr += be(UInt32(width)) + be(UInt32(height)) + [8, 2, 0, 0, 0]
        chunk(&out, "IHDR", ihdr)
        chunk(&out, "IDAT", zlibStored(raw))
        chunk(&out, "IEND", [])
        return out
    }

    private static func be(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func chunk(_ out: inout Data, _ type: String, _ data: [UInt8]) {
        out.append(contentsOf: be(UInt32(data.count)))
        let body = Array(type.utf8) + data
        out.append(contentsOf: body)
        out.append(contentsOf: be(MadVRClient.crc32(body)))
    }

    /// zlib stream with stored (uncompressed) deflate blocks.
    private static func zlibStored(_ d: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var i = 0
        repeat {
            let n = min(65535, d.count - i)
            let last: UInt8 = i + n >= d.count ? 1 : 0
            out.append(last)
            out.append(UInt8(n & 0xFF)); out.append(UInt8(n >> 8))
            out.append(UInt8(~n & 0xFF)); out.append(UInt8((~n >> 8) & 0xFF))
            out.append(contentsOf: d[i ..< i + n])
            i += n
        } while i < d.count
        var a: UInt32 = 1, b: UInt32 = 0
        for x in d { a = (a + UInt32(x)) % 65521; b = (b + a) % 65521 }
        out += be(b << 16 | a)
        return out
    }
}
