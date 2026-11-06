import ServiceManagement
import SwiftUI

@main
struct MynaApp: App {
    @StateObject private var hub = Hub.shared

    init() {
        if Demo.on { Texts.shared.receive(["t": "sms.list", "messages": Demo.texts()]); return }
        Texts.shared.setUp()
        Hub.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(hub: hub)
        } label: {
            MenuIcon(connected: hub.phoneName != nil || Demo.on)
        }
        Window("Messages", id: "messages") {
            MessagesView(texts: .shared)
        }
        .defaultSize(width: 860, height: 600)
        Window("About Myna", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        Window("Pair Phone", id: "pair") {
            PairView()
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuIcon: View {
    let connected: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: connected ? "candybarphone.fill" : "candybarphone")
            .accessibilityLabel("Myna")
            .onAppear {
                MessagesWindow.open = { openWindow(id: "messages") }
                if Demo.on {
                    Texts.shared.selection = [1]
                    openWindow(id: ["about": "about", "pair": "pair"][Demo.scene] ?? "messages")
                    NSApp.activate()
                }
            }
    }
}

private struct MenuContent: View {
    @ObservedObject var hub: Hub
    @ObservedObject var calls = Calls.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let name = hub.phoneName {
            Text("Connected to \(name)")
            if hub.cameraInUse { Text("Camera in use") }
            if hub.micInUse { Text("Mic in use") }
        } else {
            Text("Phone not connected")
        }
        if let problem = hub.problem { Text(problem) }
        switch calls.state {
        case .ringing:
            Divider()
            Text("Incoming call: \(calls.who)")
            Button("Answer") { calls.answer() }
            Button("Decline") { calls.end() }
        case .dialing, .active:
            Divider()
            Text(calls.state == .dialing ? "Calling \(calls.who)…" : "On a call with \(calls.who)")
            Button("Hang Up") { calls.end() }
        case .idle: EmptyView()
        }
        if let problem = calls.problem { Text(problem) }
        Toggle("Speakerphone for Calls from Mac", isOn: Binding(get: { calls.speakerphone }, set: { calls.speakerphone = $0 }))
        Divider()
        Button("Messages…") { MessagesWindow.show() }
            .keyboardShortcut("m")
        Button("Pair Phone…") {
            openWindow(id: "pair")
            NSApp.activate()
        }
        Toggle("Open at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }))
        Divider()
        Button("About Myna") {
            openWindow(id: "about")
            NSApp.activate()
        }
        Button("Quit Myna") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

private struct PairView: View {
    @State private var link = Pairing.link(key: Demo.on ? Demo.pairingKey : Pairing.key() ?? Pairing.newKey())

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan with your phone's camera")
                .font(.title2.weight(.semibold))
            if let image = Pairing.qrImage(link) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    .accessibilityLabel("Pairing code")
            }
            Text("Install Myna on your Android phone first. The camera opens Myna, and the phone connects over your Wi-Fi.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
            Button("Make a new code") { if !Demo.on { link = Pairing.link(key: Pairing.newKey()) } }
                .help("The phone paired with the old code stops connecting.")
        }
        .padding(28)
    }
}
