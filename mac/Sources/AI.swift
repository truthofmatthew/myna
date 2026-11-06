import Foundation
import Security

/// Where the ad check runs. Same providers and client shape as Bower's AI Recipes.
enum AIProvider: String, CaseIterable, Identifiable {
    case ollama = "Ollama", lmStudio = "LM Studio", openAI = "ChatGPT", claude = "Claude"
    var id: String { rawValue }

    var endpoint: String {
        switch self {
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .openAI: "https://api.openai.com/v1"
        case .claude: "https://api.anthropic.com/v1"
        }
    }

    /// Runs on this Mac, so no texts leave it and no key is needed.
    var isLocal: Bool { self == .ollama || self == .lmStudio }

    var keysPage: URL? {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")
        default: nil
        }
    }

    /// API keys live in the login Keychain, never in settings.
    var key: String {
        get {
            var q = keychain
            q[kSecReturnData as String] = true
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
            return String(decoding: d, as: UTF8.self)
        }
        nonmutating set {
            SecItemDelete(keychain as CFDictionary)
            let k = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { return }
            var q = keychain
            q[kSecValueData as String] = Data(k.utf8)
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    private var keychain: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Myna AI", kSecAttrAccount as String: rawValue]
    }
}

struct AIClient {
    let provider: AIProvider
    let model: String

    enum Failure: LocalizedError {
        case unreachable(String), http(Int, String), unreadable

        var errorDescription: String? {
            switch self {
            case .unreachable(let p): "Couldn't reach \(p). Check that it's running, or pick another provider."
            case .http(let code, _) where code == 401 || code == 403: "\(code) Unauthorized. Check the API key."
            case .http(let code, let msg): "HTTP \(code)\(msg.isEmpty ? "" : ": \(msg)")"
            case .unreadable: "The model's answer wasn't readable. Try again, or pick a larger model."
            }
        }
    }

    private func request(_ path: String, body: [String: Any]? = nil, timeout: TimeInterval) throws -> URLRequest {
        var r = URLRequest(url: URL(string: provider.endpoint + path)!, timeoutInterval: timeout)
        let key = provider.key
        if provider == .claude {
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if !key.isEmpty { r.setValue(key, forHTTPHeaderField: "x-api-key") }
        } else if !key.isEmpty {
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    private func send(_ r: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: r) } catch { throw Failure.unreachable(provider.rawValue) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String ?? $0["error"] as? String } ?? ""
            throw Failure.http(code, String(msg.prefix(80)))
        }
        return data
    }

    func models() async throws -> [String] {
        let data = try await send(request("/models", timeout: 8))
        let ids = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]] ?? [])
            .compactMap { $0["id"] as? String }
        guard provider == .openAI else { return ids.sorted() }
        let skip = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding", "moderation", "whisper", "dall-e", "instruct"]
        return ids.filter { id in id.hasPrefix("gpt") && !skip.contains { id.contains($0) } }.sorted()
    }

    /// A small, cheap model is plenty for sorting texts: the newest Haiku or GPT mini.
    static func suggested(_ models: [String], for p: AIProvider) -> String? {
        switch p {
        case .claude: models.last { $0.contains("haiku") } ?? models.last
        case .openAI: models.last { $0.contains("mini") && !$0.contains("audio") } ?? models.last
        default: models.first
        }
    }

    func chat(system: String, user: String) async throws -> String {
        if provider == .claude {
            let body: [String: Any] = ["model": model, "max_tokens": 4096, "temperature": 0, "system": system,
                                       "messages": [["role": "user", "content": user]]]
            let data = try await send(request("/messages", body: body, timeout: 120))
            return ((((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["content"] as? [[String: Any]]) ?? [])
                .compactMap { $0["text"] as? String }.joined()
        }
        let body: [String: Any] = ["model": model, "stream": false,
                                   "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        let data = try await send(request("/chat/completions", body: body, timeout: 120))
        return (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["choices"] as? [[String: Any]])?
            .first.flatMap { ($0["message"] as? [String: Any])?["content"] as? String } ?? ""
    }
}

/// One sender the model looked at.
struct AdVerdict: Identifiable {
    let address: String
    let title: String
    let sample: String
    let isAd: Bool
    let confidence: Double
    let reason: String
    var id: String { address }
}

enum AdCheck {
    static let system = """
    You sort SMS senders into advertising/marketing or not. Advertising means promotions, discounts, sales, offers, \
    newsletters, campaigns and club or prize marketing. Not advertising: one-time codes, bank and payment alerts, \
    bills, deliveries, appointments, carrier balance notices, and anything personal. Texts may be in Persian or English.
    Reply with one JSON object and nothing else:
    {"results":[{"sender":"<exactly as given>","ad":true,"confidence":0.93,"reason":"<under 8 words, English>"}]}
    Include every sender. confidence is how sure you are of "ad", from 0 to 1.
    """

    /// Asks in batches of 30 senders; `progress` gets the number checked so far.
    static func run(_ senders: [(address: String, title: String, samples: [String])], client: AIClient,
                    progress: @escaping (Int) -> Void) async throws -> [AdVerdict] {
        var out: [AdVerdict] = []
        for start in stride(from: 0, to: senders.count, by: 30) {
            let chunk = senders[start..<min(start + 30, senders.count)]
            let user = chunk.map { s in
                "Sender: \(s.address)\n" + s.samples.map { "- " + $0.prefix(200).replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n")
            }.joined(separator: "\n\n")
            let reply = try await client.chat(system: system, user: user)
            guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"),
                  let json = try? JSONSerialization.jsonObject(with: Data(reply[open...close].utf8)) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { throw AIClient.Failure.unreadable }
            for r in results {
                guard let address = r["sender"] as? String, let s = chunk.first(where: { $0.address == address }) else { continue }
                out.append(AdVerdict(address: address, title: s.title, sample: s.samples.first ?? "",
                                     isAd: r["ad"] as? Bool ?? false, confidence: (r["confidence"] as? NSNumber)?.doubleValue ?? 0,
                                     reason: r["reason"] as? String ?? ""))
            }
            progress(min(start + 30, senders.count))
        }
        return out
    }
}
