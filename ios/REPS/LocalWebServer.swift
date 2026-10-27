import Foundation
import Network

/// 把 App 内置的 `Web/` 目录通过 `http://127.0.0.1:8787` 提供出去。
///
/// 为什么不用 `file://` 直接开：
/// WKWebView 里 `file://` 源的 localStorage 行为不可靠，退到后台再回来数据可能就没了，
/// 而这个 App 的全部训练记录都存在 localStorage 里。走 `http://localhost` 之后，
/// 存储行为和 Safari 完全一致，能稳定持久化。
///
/// 端口必须固定：localStorage 的 origin 包含端口，端口一变数据就「换了个库」。
final class LocalWebServer {

    static let shared = LocalWebServer()

    private let root: URL
    private let queue = DispatchQueue(label: "reps.localwebserver", qos: .userInitiated)
    private var listener: NWListener?

    private(set) var port: UInt16 = 0

    private init() {
        let base = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        root = base.appendingPathComponent("Web", isDirectory: true)
    }

    // MARK: - 生命周期

    @discardableResult
    func start(port preferredPort: UInt16 = 8787) -> Bool {
        stop()

        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) else {
            NSLog("[REPS] web root missing: \(root.path)")
            return false
        }
        guard let nwPort = NWEndpoint.Port(rawValue: preferredPort) else { return false }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let l: NWListener
        do {
            l = try NWListener(using: params, on: nwPort)
        } catch {
            NSLog("[REPS] listener init failed: \(error)")
            return false
        }

        let sem = DispatchSemaphore(value: 0)
        var ready = false

        l.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready = true
                sem.signal()
            case .failed, .cancelled:
                sem.signal()
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        l.start(queue: queue)

        _ = sem.wait(timeout: .now() + 3)

        guard ready else {
            l.cancel()
            NSLog("[REPS] listener not ready on port \(preferredPort)")
            return false
        }

        listener = l
        self.port = preferredPort
        NSLog("[REPS] serving \(root.path) at http://127.0.0.1:\(preferredPort)")
        return true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: - 连接处理

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { state in
            if case .failed = state { conn.cancel() }
        }
        conn.start(queue: queue)
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            guard let self else { conn.cancel(); return }

            var buf = buffer
            if let chunk { buf.append(chunk) }

            if let sep = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<sep.lowerBound], as: UTF8.self)
                self.respond(conn, requestHead: head)
                return
            }
            if isComplete || error != nil || buf.count > 1_048_576 {
                conn.cancel()
                return
            }
            self.readRequest(conn, buffer: buf)
        }
    }

    private func respond(_ conn: NWConnection, requestHead: String) {
        let lines = requestHead.components(separatedBy: "\r\n")
        guard let first = lines.first(where: { !$0.isEmpty }) else {
            send(conn, status: "400 Bad Request", mime: "text/plain; charset=utf-8",
                 body: Data("bad request".utf8), headOnly: false)
            return
        }

        let parts = first.split(separator: " ")
        guard parts.count >= 2 else {
            send(conn, status: "400 Bad Request", mime: "text/plain; charset=utf-8",
                 body: Data("bad request".utf8), headOnly: false)
            return
        }

        let method = String(parts[0])
        let headOnly = (method == "HEAD")

        guard method == "GET" || headOnly else {
            send(conn, status: "405 Method Not Allowed", mime: "text/plain; charset=utf-8",
                 body: Data("method not allowed".utf8), headOnly: false)
            return
        }

        var path = String(parts[1])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        if let h = path.firstIndex(of: "#") { path = String(path[..<h]) }
        path = path.removingPercentEncoding ?? path

        var rel = path
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty || rel.hasSuffix("/") { rel += "index.html" }

        let fileURL = root.appendingPathComponent(rel).standardizedFileURL
        let rootPath = root.standardizedFileURL.path

        guard fileURL.path.hasPrefix(rootPath),   // 防目录穿越
              let data = try? Data(contentsOf: fileURL) else {
            send(conn, status: "404 Not Found", mime: "text/plain; charset=utf-8",
                 body: Data("404 \(rel)".utf8), headOnly: headOnly)
            return
        }

        send(conn, status: "200 OK", mime: mimeType(for: fileURL.pathExtension),
             body: data, headOnly: headOnly)
    }

    private func send(_ conn: NWConnection, status: String, mime: String, body: Data, headOnly: Bool) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        if !headOnly { payload.append(body) }

        conn.send(content: payload, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm":  return "text/html; charset=utf-8"
        case "js", "mjs":    return "application/javascript; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "json":         return "application/json; charset=utf-8"
        case "webmanifest":  return "application/manifest+json; charset=utf-8"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "svg":          return "image/svg+xml"
        case "woff2":        return "font/woff2"
        case "woff":         return "font/woff"
        case "ttf":          return "font/ttf"
        case "ico":          return "image/x-icon"
        case "mp3":          return "audio/mpeg"
        case "m4a":          return "audio/mp4"
        case "wav":          return "audio/wav"
        default:             return "application/octet-stream"
        }
    }
}
