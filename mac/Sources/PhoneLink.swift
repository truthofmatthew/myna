import CryptoKit
import Foundation
import Network

/// One encrypted connection from the phone (docs/PROTOCOL.md). All callbacks run on `queue`.
final class PhoneLink {
    var onHello: ((String) -> Void)?
    var onMessage: (([String: Any]) -> Void)?
    var onMedia: ((_ type: UInt8, _ flags: UInt8, _ pts: UInt64, _ data: Data) -> Void)?
    var onClose: (() -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let pairingKey: SymmetricKey
    private var sendKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0
    private var greeted = false
    private var closed = false
    private var lastHeard = Date()
    private var pinger: DispatchSourceTimer?

    static let maxFrame = 4 << 20

    init(connection: NWConnection, pairingKey: Data, queue: DispatchQueue) {
        self.connection = connection
        self.pairingKey = SymmetricKey(data: pairingKey)
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        read(32) { [weak self] hello in self?.handshake(hello) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        pinger?.cancel()
        connection.cancel()
        onClose?()
    }

    func send(message: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: message) else { return }
        send(type: 1, body: json)
    }

    private func handshake(_ hello: Data) {
        guard hello.prefix(4) == Data("MYNA".utf8), hello[hello.startIndex + 4] == 1 else { return close() }
        let phoneNonce = hello.subdata(in: hello.startIndex + 5 ..< hello.startIndex + 21)
        var macNonce = Data(count: 16)
        _ = macNonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let salt = phoneNonce + macNonce
        sendKey = derive(salt, "myna1 mac to phone")
        receiveKey = derive(salt, "myna1 phone to mac")
        connection.send(content: macNonce, completion: .contentProcessed { _ in })
        readFrame()
    }

    private func derive(_ salt: Data, _ info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: pairingKey, salt: salt, info: Data(info.utf8), outputByteCount: 32)
    }

    private func readFrame() {
        read(4) { [weak self] head in
            guard let self else { return }
            let length = Int(head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
            guard (17...Self.maxFrame).contains(length) else { return self.close() }
            self.read(length) { sealed in
                guard let plain = self.open(sealed), let type = plain.first else { return self.close() }
                self.lastHeard = Date()
                self.dispatch(type, plain.dropFirst())
                self.readFrame()
            }
        }
    }

    private func dispatch(_ type: UInt8, _ body: Data) {
        if !greeted {
            // The first frame proves the phone holds the pairing key.
            guard type == 1, let m = try? JSONSerialization.jsonObject(with: body) as? [String: Any], m["t"] as? String == "hello"
            else { return close() }
            greeted = true
            startPinging()
            onHello?(m["name"] as? String ?? "Phone")
            return
        }
        switch type {
        case 1:
            if let m = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { onMessage?(m) }
        case 2, 3:
            guard body.count >= 9 else { return }
            let b = Data(body)
            let pts = b.subdata(in: 1..<9).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
            onMedia?(type, b[0], pts, b.subdata(in: 9..<b.count))
        default: break
        }
    }

    private func startPinging() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastHeard) > 30 { return self.close() }
            self.send(message: ["t": "ping"])
        }
        timer.resume()
        pinger = timer
    }

    private func send(type: UInt8, body: Data) {
        guard let key = sendKey, !closed,
              let box = try? AES.GCM.seal(Data([type]) + body, using: key, nonce: nonce(sendCounter)) else { return }
        sendCounter += 1
        let sealed = box.ciphertext + box.tag
        var length = UInt32(sealed.count).bigEndian
        connection.send(content: Data(bytes: &length, count: 4) + sealed, completion: .contentProcessed { _ in })
    }

    private func open(_ sealed: Data) -> Data? {
        guard let key = receiveKey,
              let box = try? AES.GCM.SealedBox(nonce: nonce(receiveCounter), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16)),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        receiveCounter += 1
        return plain
    }

    private func nonce(_ counter: UInt64) -> AES.GCM.Nonce {
        var be = counter.bigEndian
        return try! AES.GCM.Nonce(data: Data(count: 4) + Data(bytes: &be, count: 8))
    }

    private func read(_ count: Int, _ done: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, isComplete, error in
            guard let data, data.count == count, error == nil else { self?.close(); return }
            done(data)
            if isComplete && data.isEmpty { self?.close() }
        }
    }
}
