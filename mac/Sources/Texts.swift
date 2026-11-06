import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct TextMessage: Identifiable, Hashable {
    let id: Int64
    let thread: Int64
    let address: String
    let name: String?
    let body: String
    let date: Date
    let type: Int // Android's: 1 received, 2 sent, 4 sending, 5 failed, 6 queued
    var read: Bool
    var mine: Bool { type != 1 }
    var failed: Bool { type == 5 }

    init?(_ m: [String: Any]) {
        guard let id = (m["id"] as? NSNumber)?.int64Value, let thread = (m["thread"] as? NSNumber)?.int64Value,
              let address = m["address"] as? String, let date = (m["date"] as? NSNumber)?.doubleValue else { return nil }
        self.id = id
        self.thread = thread
        self.address = address
        name = m["name"] as? String
        body = m["body"] as? String ?? ""
        self.date = Date(timeIntervalSince1970: date / 1000)
        type = (m["type"] as? NSNumber)?.intValue ?? 1
        read = m["read"] as? Bool ?? true
    }
}

struct Conversation: Identifiable {
    let id: Int64
    let messages: [TextMessage] // oldest first
    var last: TextMessage { messages[messages.count - 1] }
    var address: String { last.address }
    var title: String { messages.lazy.compactMap(\.name).first ?? address }
    var unread: Int { messages.filter { !$0.mine && !$0.read }.count }
}

/// Changes only the phone's SMS app may make; applied together in one approval on the phone.
struct PhoneBatch: Codable, Equatable {
    var delete: Set<Int64> = []
    var read: Set<Int64> = []
    var block: Set<String> = []
    var unblock: Set<String> = []
    var isEmpty: Bool { delete.isEmpty && read.isEmpty && block.isEmpty && unblock.isEmpty }

    var summary: String {
        func n(_ count: Int, _ one: String, _ many: String) -> String? { count == 0 ? nil : "\(count) \(count == 1 ? one : many)" }
        return [n(delete.count, "text to delete", "texts to delete"), n(read.count, "text to mark read", "texts to mark read"),
                n(block.count, "number to block", "numbers to block"), n(unblock.count, "number to unblock", "numbers to unblock")]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// The phone's texts on the Mac. Texts stay in memory and re-sync on every connect (the phone is the source of truth);
/// the block list and pending changes are saved, since the phone only reports its block list after a batch.
final class Texts: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Texts()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var blocked: [String] = []
    @Published private(set) var pending = PhoneBatch()
    @Published private(set) var waitingForPhone = false
    @Published private(set) var problem: String?
    /// Texts the phone has sent so far in this sync, and how many it will send. Equal once loading is done.
    @Published private(set) var loaded = 0
    @Published private(set) var toLoad = 0
    var isLoading: Bool { loaded < toLoad }
    /// Conversation ids selected in the list (⌘-click, ⇧-click or ⌘A for several).
    @Published var selection: Set<Int64> = []
    private var all: [Int64: TextMessage] = [:]
    private var synced = false
    /// True once a load finished; a reconnect then asks only for what changed. A load cut short starts over.
    private var complete = false
    private let store = Demo.on ? Demo.store : UserDefaults.standard

    override init() {
        super.init()
        blocked = store.stringArray(forKey: "blocked") ?? []
        if let d = store.data(forKey: "pendingBatch"), let b = try? JSONDecoder().decode(PhoneBatch.self, from: d) { pending = b }
    }

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Text message")
        let read = UNNotificationAction(identifier: "read", title: "Mark as Read")
        let delete = UNNotificationAction(identifier: "delete", title: "Delete", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: "text", actions: [reply, read, delete], intentIdentifiers: []), Calls.category])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: From the phone

    /// Phone → Mac messages whose type starts with "sms.". Main thread.
    func receive(_ m: [String: Any]) {
        switch m["t"] as? String {
        case "sms.list", "sms.more":
            // Pages of a sync, newest first: no notifications. The list is rebuilt for the first page, so the
            // newest texts show at once, and for the last; rebuilding 40,000 texts after every page froze the app.
            let first = m["t"] as? String == "sms.list"
            let done = m["done"] as? Bool ?? true
            if first { all = [:]; loaded = 0; complete = false }
            loaded += add(m["messages"], rebuild: first || done).count
            toLoad = done ? loaded : max(m["total"] as? Int ?? 0, loaded)
            if done { complete = true }
            synced = true
            if first { problem = nil }
        case "sms.state":
            // A reconnect: drop texts deleted on the phone (or now past the limit) and take its read marks.
            // The newer texts follow as sms.more pages.
            let onPhone = Set(ids(m["ids"])), unread = Set(ids(m["unread"]))
            all = all.filter { onPhone.contains($0.key) }
            for (id, t) in all where !t.mine { all[id]?.read = !unread.contains(id) || pending.read.contains(id) }
            rebuild()
            loaded = 0
            toLoad = m["new"] as? Int ?? 0
            complete = false
            problem = nil
        case "sms.new":
            let fresh = add(m["messages"])
            if synced { fresh.filter { !$0.mine && !isBlocked($0.address) }.forEach(notify) }
        case "sms.sent":
            if m["ok"] as? Bool == false { problem = "A text didn't send. Check the phone's signal and try again." }
        case "sms.read.done":
            // No Samsung notification to press (it was already gone): mark read with the next batch instead.
            if m["ok"] as? Bool == false { update { $0.read.formUnion(ids(m["ids"])) } }
        case "sms.batch.done":
            let deleted = Set(ids(m["deleted"]))
            for id in deleted { all[id] = nil }
            blocked = (m["blocked"] as? [String] ?? []).sorted()
            store.set(blocked, forKey: "blocked")
            update { $0 = PhoneBatch() }
            waitingForPhone = false
            rebuild()
        case "sms.stopped":
            if isLoading { complete = false }  // the phone went away mid-load; the next connect starts over
            toLoad = loaded
        case "sms.error":
            problem = m["error"] as? String
        default: break
        }
    }

    // MARK: Actions

    /// How many of the newest texts to load, set in Settings; 0 loads them all.
    static let limitKey = "textsToLoad"

    /// Asks the phone for its texts: everything the first time, then only what changed since the newest one here.
    func syncWithPhone(full: Bool = false) {
        let since = full || !complete ? 0 : all.keys.max() ?? 0
        _ = Hub.shared.sendToPhone(["t": "sms.sync", "limit": UserDefaults.standard.integer(forKey: Self.limitKey), "since": since])
    }

    func send(to address: String, body: String) {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !body.isEmpty else { return }
        if !Hub.shared.sendToPhone(["t": "sms.send", "to": address, "body": body, "ref": UUID().uuidString]) {
            problem = "Your phone isn't connected, so the text wasn't sent."
        }
    }

    func markRead(_ c: Conversation) {
        let unread = c.messages.filter { !$0.mine && !$0.read }.map(\.id)
        guard !unread.isEmpty else { return }
        for id in unread { all[id]?.read = true }
        rebuild()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: unread.map { "text-\($0)" })
        if !Demo.on, !Hub.shared.sendToPhone(["t": "sms.read", "address": c.address, "name": c.title, "ids": unread]) {
            update { $0.read.formUnion(unread) }
        }
    }

    /// Hidden on the Mac now; deleted on the phone with the next batch.
    func delete(_ ids: [Int64]) {
        for id in ids { all[id] = nil }
        update { $0.delete.formUnion(ids); $0.read.subtract(ids) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids.map { "text-\($0)" })
        rebuild()
    }

    func block(_ addresses: [String]) {
        let fresh = addresses.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !isBlocked($0) }
        guard !fresh.isEmpty else { return }
        blocked = (blocked + fresh).sorted()
        store.set(blocked, forKey: "blocked")
        update { $0.block.formUnion(fresh); $0.unblock.subtract(fresh) }
        rebuild()
    }

    func unblock(_ address: String) {
        blocked.removeAll { $0 == address }
        store.set(blocked, forKey: "blocked")
        update { if $0.block.remove(address) == nil { $0.unblock.insert(address) } }
        rebuild()
    }

    /// Sends the batch; the phone asks you to approve it, since only its SMS app may change texts.
    func applyOnPhone() {
        guard !pending.isEmpty else { return }
        let message: [String: Any] = ["t": "sms.batch", "id": UUID().uuidString,
                                      "delete": Array(pending.delete), "read": Array(pending.read),
                                      "block": Array(pending.block), "unblock": Array(pending.unblock)]
        if Hub.shared.sendToPhone(message) { waitingForPhone = true }
        else { problem = "Your phone isn't connected. The changes are kept until it is." }
    }

    func exportBlocked() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Blocked numbers.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let names = Dictionary(conversations.map { (key($0.address), $0.title) }, uniquingKeysWith: { a, _ in a })
        let rows = blocked.map { n in [n, names[key(n)].flatMap { $0 == n ? nil : $0 } ?? ""].map(csv).joined(separator: ",") }
        do { try (["number,name"] + rows).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { problem = "Couldn't save the file: \(error.localizedDescription)" }
    }

    func dismissProblem() { problem = nil }

    /// Senders worth asking the AI about: they texted you, you never wrote back, and they aren't blocked yet.
    func adCandidates() -> [(address: String, title: String, samples: [String])] {
        conversations.filter { c in !c.messages.contains(where: \.mine) }
            .map { c in (c.address, c.title, c.messages.reversed().filter { !$0.mine }.prefix(3).map(\.body)) }
    }

    // MARK: Helpers

    /// Phone numbers match on their last 10 digits (+98912… and 0912… are the same); sender names match as text.
    func key(_ address: String) -> String {
        let digits = address.filter(\.isNumber)
        return digits.count >= 7 && digits.count >= address.filter { !$0.isWhitespace }.count - 1
            ? String(digits.suffix(10)) : address.lowercased().trimmingCharacters(in: .whitespaces)
    }

    func isBlocked(_ address: String) -> Bool { let k = key(address); return blocked.contains { key($0) == k } }

    private func csv(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }

    private func ids(_ any: Any?) -> [Int64] { (any as? [NSNumber] ?? []).map(\.int64Value) }

    private func update(_ change: (inout PhoneBatch) -> Void) {
        change(&pending)
        if let d = try? JSONEncoder().encode(pending) { store.set(d, forKey: "pendingBatch") }
    }

    @discardableResult
    private func add(_ list: Any?, rebuild: Bool = true) -> [TextMessage] {
        let fresh = (list as? [[String: Any]] ?? []).compactMap(TextMessage.init)
            .filter { !pending.delete.contains($0.id) }
            .map { t in var t = t; if pending.read.contains(t.id) { t.read = true }; return t }
        for t in fresh { all[t.id] = t }
        if rebuild { self.rebuild() }
        return fresh
    }

    /// Blocked senders stay out of the list; they're in Blocked Numbers.
    private func rebuild() {
        let blockedKeys = Set(blocked.map(key))
        var hidden: [String: Bool] = [:]
        let shown = all.values.filter { t in
            if let h = hidden[t.address] { return !h }
            let h = blockedKeys.contains(key(t.address))
            hidden[t.address] = h
            return !h
        }
        conversations = Dictionary(grouping: shown, by: \.thread)
            .map { Conversation(id: $0.key, messages: $0.value.sorted { ($0.date, $0.id) < ($1.date, $1.id) }) }
            .sorted { $0.last.date > $1.last.date }
    }

    // MARK: Notifications

    private func notify(_ t: TextMessage) {
        let content = UNMutableNotificationContent()
        content.title = t.name ?? t.address
        if t.name != nil { content.subtitle = t.address }
        content.body = t.body
        content.sound = .default
        content.categoryIdentifier = "text"
        content.threadIdentifier = String(t.thread)
        content.userInfo = ["id": t.id, "thread": t.thread]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "text-\(t.id)", content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let id = (info["id"] as? NSNumber)?.int64Value ?? -1
        let thread = (info["thread"] as? NSNumber)?.int64Value
        if response.notification.request.content.categoryIdentifier == "call" {
            await MainActor.run {
                switch response.actionIdentifier {
                case "answer": Calls.shared.answer()
                case "decline": Calls.shared.end()
                default: break
                }
            }
            return
        }
        await MainActor.run {
            let c = conversations.first { $0.id == thread }
            switch response.actionIdentifier {
            case "reply":
                if let c, let reply = response as? UNTextInputNotificationResponse {
                    send(to: c.address, body: reply.userText)
                    markRead(c)
                }
            case "read": if let c { markRead(c) }
            case "delete": delete([id])
            default:
                selection = thread.map { [$0] } ?? []
                MessagesWindow.show()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Opens the SwiftUI Messages window from outside a view (notifications). An AppKit-made window
/// let the list scroll under the see-through toolbar with no blur, so the window comes from a Window scene.
enum MessagesWindow {
    /// Set by the menu bar icon, which is always on screen and can reach SwiftUI's openWindow.
    static var open: (() -> Void)?

    static func show() {
        open?()
        NSApp.activate()
    }
}
