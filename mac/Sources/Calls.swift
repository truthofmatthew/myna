import Foundation
import UserNotifications

/// The phone's call state and the buttons that control it. No audio: you talk on the phone.
final class Calls: ObservableObject {
    static let shared = Calls()

    enum State: String { case idle, ringing, dialing, active }

    @Published private(set) var state = State.idle
    @Published private(set) var number: String?
    @Published private(set) var name: String?
    @Published private(set) var problem: String?

    var who: String { name ?? number ?? "Unknown caller" }

    /// Phone → Mac messages whose type starts with "call.". Main thread.
    func receive(_ m: [String: Any]) {
        switch m["t"] as? String {
        case "call.state":
            let new = State(rawValue: m["state"] as? String ?? "") ?? .idle
            number = m["number"] as? String
            name = m["name"] as? String
            if new == .ringing && state != .ringing { notifyRinging() }
            if new != .ringing { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call"]) }
            state = new
            if new != .idle { problem = nil }
        case "call.error":
            problem = m["error"] as? String
        default: break
        }
    }

    func answer() { send(["t": "call.answer"]) }
    func end() { send(["t": "call.end"]) }

    func dial(_ number: String) {
        let n = number.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        send(["t": "call.dial", "number": n])
    }

    private func send(_ m: [String: Any]) {
        if !Hub.shared.sendToPhone(m) { problem = "Your phone isn't connected." }
    }

    private func notifyRinging() {
        let content = UNMutableNotificationContent()
        content.title = "Incoming call"
        content.subtitle = who
        if name != nil, let number { content.body = number }
        content.sound = .default // the ringtone sound is iOS-only
        content.categoryIdentifier = "call"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "call", content: content, trigger: nil))
    }

    static let category = UNNotificationCategory(identifier: "call", actions: [
        UNNotificationAction(identifier: "answer", title: "Answer"),
        UNNotificationAction(identifier: "decline", title: "Decline", options: [.destructive]),
    ], intentIdentifiers: [])
}
