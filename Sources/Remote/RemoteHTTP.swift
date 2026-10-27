import Foundation
import Network
import CryptoKit

/// A tiny HTTP + WebSocket server on 127.0.0.1 only. The outside world reaches it through the Cloudflare tunnel,
/// never directly. One port serves both, because the tunnel forwards a single origin.
final class RemoteHTTPServer {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]      // lower-cased names
        let body: Data
    }
    struct Response {
        var status: Int = 200
        var type = "application/json"
        var body = Data()
        static func json(_ obj: Any, status: Int = 200) -> Response {
            Response(status: status, type: "application/json", body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
        }
        static func text(_ s: String, status: Int = 200) -> Response { Response(status: status, type: "text/plain; charset=utf-8", body: Data(s.utf8)) }
    }

    let port: UInt16
    var route: (Request) -> Response = { _ in .text("not found", status: 404) }
    /// Called when a client upgrades to WebSocket. Return false to refuse.
    var acceptSocket: (Request) -> Bool = { _ in false }
    var onSocket: (RemoteSocket) -> Void = { _ in }
    /// Allowed browser origin for the API and sockets (the phone app's home).
    var allowedOrigin = "https://arifinrio95.github.io"

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "id.datasans.celah.remote.http")

    init(port: UInt16) { self.port = port }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { st in if case .failed(let e) = st { Log.write("remote http failed: \(e)") } }
        l.start(queue: queue)
        listener = l
    }

    func stop() { listener?.cancel(); listener = nil }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        readRequest(c, buffer: Data())
    }

    private func readRequest(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if err != nil || (done && data == nil) { c.cancel(); return }
            guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if buf.count > 32 * 1024 { c.cancel() } else { self.readRequest(c, buffer: buf) }
                return
            }
            let head = String(decoding: buf[..<headerEnd.lowerBound], as: UTF8.self)
            var lines = head.components(separatedBy: "\r\n")
            let first = lines.removeFirst().split(separator: " ")
            guard first.count >= 2 else { c.cancel(); return }
            var headers: [String: String] = [:]
            for l in lines { if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let bodyStart = headerEnd.upperBound
            if buf.count - bodyStart < length { self.readRequest(c, buffer: buf); return }
            let req = Request(method: String(first[0]), path: String(first[1]), headers: headers,
                              body: buf.subdata(in: bodyStart..<(bodyStart + min(length, 64 * 1024))))
            if headers["upgrade"]?.lowercased() == "websocket" { self.upgrade(c, req) } else { self.respond(c, req) }
        }
    }

    private func respond(_ c: NWConnection, _ req: Request) {
        var res: Response
        if req.method == "OPTIONS" { res = .text("", status: 204) } else { res = route(req) }
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 429: "Too Many Requests"][res.status] ?? "OK"
        var head = "HTTP/1.1 \(res.status) \(reason)\r\nContent-Type: \(res.type)\r\nContent-Length: \(res.body.count)\r\n"
        head += "Access-Control-Allow-Origin: \(allowedOrigin)\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n"
        head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8); out.append(res.body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    private func upgrade(_ c: NWConnection, _ req: Request) {
        guard let key = req.headers["sec-websocket-key"], acceptSocket(req) else {
            c.send(content: Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in c.cancel() })
            return
        }
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        c.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            let s = RemoteSocket(connection: c, queue: self.queue)
            self.onSocket(s)
            s.readLoop()
        })
    }
}

/// One WebSocket connection (RFC 6455, server side: unmasked frames out, masked frames in).
final class RemoteSocket {
    let connection: NWConnection
    let id = UUID()
    private let queue: DispatchQueue
    private var buffer = Data()
    var onText: (String) -> Void = { _ in }
    var onClose: () -> Void = {}
    private(set) var closed = false
    /// Bytes handed to the network but not yet sent; used for back-pressure on frames.
    private(set) var pending = 0

    init(connection: NWConnection, queue: DispatchQueue) { self.connection = connection; self.queue = queue }

    var remoteDescription: String { "\(connection.endpoint)" }

    func readLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, err in
            guard let self, !self.closed else { return }
            if let data { self.buffer.append(data); self.parse() }
            if err != nil || done { self.close(); return }
            self.readLoop()
        }
    }

    private func parse() {
        while buffer.count >= 2 {
            let b0 = buffer[buffer.startIndex], b1 = buffer[buffer.startIndex + 1]
            let opcode = b0 & 0x0F, masked = b1 & 0x80 != 0
            var len = Int(b1 & 0x7F), idx = 2
            if len == 126 { guard buffer.count >= 4 else { return }; len = Int(buffer[buffer.startIndex + 2]) << 8 | Int(buffer[buffer.startIndex + 3]); idx = 4 }
            else if len == 127 {
                guard buffer.count >= 10 else { return }
                len = 0; for i in 2..<10 { len = len << 8 | Int(buffer[buffer.startIndex + i]) }; idx = 10
            }
            guard len < 1 << 20 else { close(); return }
            let maskLen = masked ? 4 : 0
            guard buffer.count >= idx + maskLen + len else { return }
            let s = buffer.startIndex
            var payload = Data(buffer[(s + idx + maskLen)..<(s + idx + maskLen + len)])
            if masked {
                let mask = [UInt8](buffer[(s + idx)..<(s + idx + 4)])
                payload.withUnsafeMutableBytes { p in for i in 0..<p.count { p[i] ^= mask[i % 4] } }
            }
            buffer.removeFirst(idx + maskLen + len)
            switch opcode {
            case 1: onText(String(decoding: payload, as: UTF8.self))
            case 8: close(); return
            case 9: send(frame: payload, opcode: 10)
            default: break
            }
        }
    }

    func send(text: String) { send(frame: Data(text.utf8), opcode: 1) }
    /// Sends a last message, then closes once it has left (cancel alone can drop it).
    func sendThenClose(text: String) { send(frame: Data(text.utf8), opcode: 1) { [weak self] in self?.close() } }
    func send(binary: Data) { send(frame: binary, opcode: 2) }

    private func send(frame payload: Data, opcode: UInt8, then done: (() -> Void)? = nil) {
        guard !closed else { return }
        var head = Data([0x80 | opcode])
        if payload.count < 126 { head.append(UInt8(payload.count)) }
        else if payload.count < 65536 { head.append(126); head.append(UInt8(payload.count >> 8)); head.append(UInt8(payload.count & 0xFF)) }
        else { head.append(127); for i in (0..<8).reversed() { head.append(UInt8((payload.count >> (i * 8)) & 0xFF)) } }
        head.append(payload)
        let n = head.count
        queue.async { self.pending += n }
        connection.send(content: head, completion: .contentProcessed { [weak self] _ in self?.queue.async { self?.pending -= n; done?() } })
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose()
    }
}
