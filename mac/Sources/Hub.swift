import Foundation
import Network

/// Accepts the paired phone and serves its camera and mic to the Chrome extension on 127.0.0.1:8737.
/// Asks the phone for the camera or mic only while a browser tab is using it.
final class Hub: ObservableObject {
    static let shared = Hub()

    @Published private(set) var phoneName: String?
    @Published private(set) var cameraInUse = false
    @Published private(set) var micInUse = false
    @Published private(set) var problem: String?

    private let queue = DispatchQueue(label: "myna.hub")
    private var phoneListener: NWListener?
    private var browserListener: NWListener?
    private var phone: PhoneLink?
    private var handshaking: [PhoneLink] = [] // keeps new connections alive until they say hello or close

    private final class Viewer {
        let connection: NWConnection
        var waitingForKeyFrame = true
        init(_ connection: NWConnection) { self.connection = connection }
    }
    private var videoViewers: [Viewer] = []
    private var audioViewers: [Viewer] = []
    private var camera = "front"
    private var config: Data?   // last SPS/PPS packet, replayed to each new viewer
    private var session: Data?  // last size and rotation packet

    func start() {
        queue.async { [self] in
            if Pairing.key() == nil { Pairing.newKey() }
            startPhoneListener()
            startBrowserListener()
        }
    }

    // MARK: Phone

    private func startPhoneListener() {
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Pairing.port)!)
            listener.service = NWListener.Service(name: Pairing.macName, type: "_myna._tcp",
                                                  txtRecord: NWTXTRecord(["id": Pairing.macID]))
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state { self?.report("Can't listen for your phone: \(error)") }
            }
            listener.start(queue: queue)
            phoneListener = listener
        } catch {
            report("Can't listen for your phone: \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        guard let key = Pairing.key() else { return connection.cancel() }
        let link = PhoneLink(connection: connection, pairingKey: key, queue: queue)
        link.onHello = { [weak self, weak link] name in
            guard let self, let link else { return }
            self.handshaking.removeAll { $0 === link }
            if self.phone !== link { self.phone?.close() }
            self.phone = link
            self.publish { $0.phoneName = name; $0.problem = nil }
            // A reconnecting phone picks up whatever the browser is already using.
            if !self.videoViewers.isEmpty { link.send(message: ["t": "camera", "on": true, "camera": self.camera]) }
            if !self.audioViewers.isEmpty { link.send(message: ["t": "mic", "on": true]) }
        }
        link.onMessage = { [weak self] m in
            guard let self, m["t"] as? String == "video",
                  let w = m["w"] as? Int, let h = m["h"] as? Int, let rotation = m["rotation"] as? Int else { return }
            let packet = Self.header(UInt64(0x8000_0000 | UInt32(rotation)) << 32 | UInt64(w), size: UInt32(h))
            self.session = packet
            for v in self.videoViewers { v.connection.send(content: packet, completion: .idempotent) }
        }
        link.onMedia = { [weak self] type, flags, pts, data in
            type == 2 ? self?.video(flags: flags, pts: pts, data: data) : self?.audio(pts: pts, data: data)
        }
        link.onClose = { [weak self, weak link] in
            guard let self else { return }
            self.handshaking.removeAll { $0 === link }
            guard self.phone === link else { return }
            self.phone = nil
            self.config = nil
            self.publish { $0.phoneName = nil }
        }
        handshaking.append(link)
        link.start()
    }

    private func video(flags: UInt8, pts: UInt64, data: Data) {
        let isKey = flags & 1 != 0, isConfig = flags & 2 != 0
        let packet = Self.header(pts | (isConfig ? 1 << 62 : 0) | (isKey ? 1 << 61 : 0), size: UInt32(data.count)) + data
        if isConfig { config = packet }
        for v in videoViewers {
            if v.waitingForKeyFrame && !isConfig {
                guard isKey else { continue }
                v.waitingForKeyFrame = false
            }
            v.connection.send(content: packet, completion: .idempotent)
        }
    }

    private func audio(pts: UInt64, data: Data) {
        let packet = Self.header(pts, size: UInt32(data.count)) + data
        for v in audioViewers { v.connection.send(content: packet, completion: .idempotent) }
    }

    /// scrcpy-style 12-byte packet header: [u64][u32], big-endian.
    private static func header(_ word: UInt64, size: UInt32) -> Data {
        var w = word.bigEndian, s = size.bigEndian
        return Data(bytes: &w, count: 8) + Data(bytes: &s, count: 4)
    }

    // MARK: Browser

    private func startBrowserListener() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8737)
        guard let listener = try? NWListener(using: params) else { return report("Port 8737 is busy; quit whatever else uses it.") }
        listener.newConnectionHandler = { [weak self] in self?.serve($0) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.report("Port 8737 is busy; quit whatever else uses it.") }
        }
        listener.start(queue: queue)
        browserListener = listener
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n").first else { return connection.cancel() }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let url = URLComponents(string: String(parts[1])) else { return connection.cancel() }
            if parts[0] == "OPTIONS" { return self.reply(connection, "204 No Content", end: true) }
            switch url.path {
            case "/video": self.addVideoViewer(connection, camera: url.queryItems?.first { $0.name == "camera" }?.value ?? "front")
            case "/audio": self.addAudioViewer(connection)
            default: self.reply(connection, "404 Not Found", end: true)
            }
        }
    }

    private func reply(_ connection: NWConnection, _ status: String, body: String = "", end: Bool) {
        // Meet on https calls this loopback server; Chrome needs CORS and Private Network Access headers.
        let head = "HTTP/1.1 \(status)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Private-Network: true\r\n"
            + "Content-Type: application/octet-stream\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" + body
        connection.send(content: Data(head.utf8), completion: end ? .contentProcessed { _ in connection.cancel() } : .idempotent)
    }

    private func addVideoViewer(_ connection: NWConnection, camera wanted: String) {
        guard let phone else { return reply(connection, "503 Service Unavailable", body: "Phone not connected", end: true) }
        guard wanted == "front" || wanted == "back" else { return reply(connection, "400 Bad Request", end: true) }
        reply(connection, "200 OK", end: false)
        connection.send(content: Data("h264".utf8), completion: .idempotent)
        let viewer = Viewer(connection)
        if wanted != camera || videoViewers.isEmpty {
            camera = wanted
            config = nil
            session = nil
            phone.send(message: ["t": "camera", "on": true, "camera": wanted])
        } else {
            if let session { connection.send(content: session, completion: .idempotent) }
            if let config { connection.send(content: config, completion: .idempotent) }
            phone.send(message: ["t": "keyframe"])
        }
        videoViewers.append(viewer)
        watch(connection) { [weak self] in
            guard let self else { return }
            self.videoViewers.removeAll { $0 === viewer }
            if self.videoViewers.isEmpty { self.phone?.send(message: ["t": "camera", "on": false]) }
            self.publish { $0.cameraInUse = !self.videoViewers.isEmpty }
        }
        publish { $0.cameraInUse = true }
    }

    private func addAudioViewer(_ connection: NWConnection) {
        guard let phone else { return reply(connection, "503 Service Unavailable", body: "Phone not connected", end: true) }
        reply(connection, "200 OK", end: false)
        connection.send(content: Data("opus".utf8), completion: .idempotent)
        let viewer = Viewer(connection)
        if audioViewers.isEmpty { phone.send(message: ["t": "mic", "on": true]) }
        audioViewers.append(viewer)
        watch(connection) { [weak self] in
            guard let self else { return }
            self.audioViewers.removeAll { $0 === viewer }
            if self.audioViewers.isEmpty { self.phone?.send(message: ["t": "mic", "on": false]) }
            self.publish { $0.micInUse = !self.audioViewers.isEmpty }
        }
        publish { $0.micInUse = true }
    }

    /// Calls `gone` once when the browser closes the stream.
    private func watch(_ connection: NWConnection, gone: @escaping () -> Void) {
        var fired = false
        let fire = { if !fired { fired = true; gone() } }
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: fire()
            default: break
            }
        }
        func drain() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, isComplete, error in
                if isComplete || error != nil { connection.cancel(); fire() } else { drain() }
            }
        }
        drain()
    }

    // MARK: UI state

    private func report(_ text: String) { publish { $0.problem = text } }

    private func publish(_ change: @escaping (Hub) -> Void) {
        DispatchQueue.main.async { change(self) }
    }
}
