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

    /// You answered or dialed on the Mac, so you're probably not holding the phone: use its loudspeaker.
    var speakerphone: Bool {
        get { UserDefaults.standard.object(forKey: "callSpeaker") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "callSpeaker"); objectWillChange.send() }
    }

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
        case "call.speaker":
            if m["on"] as? Bool == false { problem = "The phone didn't switch to speaker. Tap Speaker on the phone." }
        case "call.error":
            problem = m["error"] as? String
        default: break
        }
    }

    func answer() { send(["t": "call.answer", "speaker": speakerphone]) }
    func end() { send(["t": "call.end"]) }

    func dial(_ number: String) {
        let n = number.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        send(["t": "call.dial", "number": n, "speaker": speakerphone])
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
