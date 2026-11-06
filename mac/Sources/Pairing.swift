import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import Security

/// This Mac's identity and pairing key, and the QR link a phone scans (see docs/PROTOCOL.md).
enum Pairing {
    static let port: UInt16 = 47123

    static var macID: String {
        if let id = UserDefaults.standard.string(forKey: "macID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "macID")
        return id
    }

    static var macName: String { Host.current().localizedName ?? "Mac" }

    private static let keychainItem: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.truthofmatthew.Myna",
        kSecAttrAccount as String: "pairing-key",
    ]

    /// The current pairing key, or nil before the first pairing.
    static func key() -> Data? {
        var query = keychainItem
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    /// Makes a new key; any phone paired with the old one can no longer connect.
    @discardableResult
    static func newKey() -> Data {
        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        precondition(status == errSecSuccess, "no secure random bytes")
        SecItemDelete(keychainItem as CFDictionary)
        var item = keychainItem
        item[kSecValueData as String] = key
        SecItemAdd(item as CFDictionary, nil)
        return key
    }

    static func link(key: Data) -> URL {
        var c = URLComponents()
        c.scheme = "myna"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "id", value: macID),
            URLQueryItem(name: "n", value: macName),
            URLQueryItem(name: "h", value: localIPv4() ?? "0.0.0.0"),
            URLQueryItem(name: "p", value: String(port)),
            URLQueryItem(name: "k", value: key.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")),
        ]
        return c.url!
    }

    static func qrImage(_ url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage,
              let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: cg, size: image.extent.size)
    }

    /// The Mac's IPv4 address on Wi-Fi or Ethernet, for phones that can't find it over Bonjour.
    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var p = list
        while let a = p?.pointee {
            defer { p = a.ifa_next }
            guard a.ifa_addr.pointee.sa_family == UInt8(AF_INET), String(cString: a.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(a.ifa_addr, socklen_t(a.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
