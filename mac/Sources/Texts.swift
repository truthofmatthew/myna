import AppKit
import SwiftUI
import UserNotifications

struct TextMessage: Identifiable, Hashable {
    let id: Int64
    let thread: Int64
    let address: String
    let name: String?
    let body: String
    let date: Date
    let type: Int // Android's: 1 received, 2 sent, 4 sending, 5 failed, 6 queued
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
    }
}

struct Conversation: Identifiable {
    let id: Int64
    let messages: [TextMessage] // oldest first
    var last: TextMessage { messages[messages.count - 1] }
    var title: String { messages.lazy.compactMap(\.name).first ?? last.address }
}

/// The phone's texts, kept in memory (the phone is the source of truth; they re-sync on every connect).
final class Texts: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Texts()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var problem: String?
    @Published var selected: Int64?
    private var all: [Int64: TextMessage] = [:]
    private var synced = false

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Text message")
        center.setNotificationCategories([UNNotificationCategory(identifier: "text", actions: [reply], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Phone → Mac messages whose type starts with "sms.". Main thread.
    func receive(_ m: [String: Any]) {
        switch m["t"] as? String {
        case "sms.list":
            all = [:]
            add(m["messages"])
            synced = true
            problem = nil
        case "sms.new":
            let fresh = add(m["messages"])
            if synced { fresh.filter { !$0.mine }.forEach(notify) }
        case "sms.sent":
            if m["ok"] as? Bool == false { problem = "A text didn't send. Check the phone's signal and try again." }
        case "sms.error":
            problem = m["error"] as? String
        default: break
        }
    }

    func send(to address: String, body: String) {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !body.isEmpty else { return }
        if !Hub.shared.sendToPhone(["t": "sms.send", "to": address, "body": body, "ref": UUID().uuidString]) {
            problem = "Your phone isn't connected, so the text wasn't sent."
        }
    }

    @discardableResult
    private func add(_ list: Any?) -> [TextMessage] {
        let fresh = (list as? [[String: Any]] ?? []).compactMap(TextMessage.init)
        for t in fresh { all[t.id] = t }
        conversations = Dictionary(grouping: all.values, by: \.thread)
            .map { Conversation(id: $0.key, messages: $0.value.sorted { ($0.date, $0.id) < ($1.date, $1.id) }) }
            .sorted { $0.last.date > $1.last.date }
        return fresh
    }

    private func notify(_ t: TextMessage) {
        let content = UNMutableNotificationContent()
        content.title = t.name ?? t.address
        content.body = t.body
        content.sound = .default
        content.categoryIdentifier = "text"
        content.threadIdentifier = String(t.thread)
        content.userInfo = ["address": t.address, "thread": t.thread]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "text-\(t.id)", content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let address = info["address"] as? String ?? ""
        let thread = (info["thread"] as? NSNumber)?.int64Value
        await MainActor.run {
            if let reply = response as? UNTextInputNotificationResponse {
                send(to: address, body: reply.userText)
            } else {
                selected = thread
                MessagesWindow.show()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// The Messages window, made with AppKit so a notification can open it too.
enum MessagesWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: MessagesView(texts: .shared)))
            w.title = "Messages"
            w.setContentSize(NSSize(width: 760, height: 540))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
