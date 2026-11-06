import ServiceManagement
import SwiftUI

@main
struct MynaApp: App {
    @StateObject private var hub = Hub.shared

    init() { Hub.shared.start() }

    var body: some Scene {
        MenuBarExtra("Myna", systemImage: hub.phoneName == nil ? "candybarphone" : "candybarphone.fill") {
            MenuContent(hub: hub)
        }
        Window("Pair Phone", id: "pair") {
            PairView()
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuContent: View {
    @ObservedObject var hub: Hub
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
        Divider()
        Button("Pair Phone…") {
            openWindow(id: "pair")
            NSApp.activate()
        }
        Toggle("Open at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }))
        Divider()
        Button("Quit Myna") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

private struct PairView: View {
    @State private var link = Pairing.link(key: Pairing.key() ?? Pairing.newKey())

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
            Button("Make a new code") { link = Pairing.link(key: Pairing.newKey()) }
                .help("The phone paired with the old code stops connecting.")
        }
        .padding(28)
    }
}
