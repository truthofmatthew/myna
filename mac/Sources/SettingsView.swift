import ServiceManagement
import SwiftUI

/// Myna's settings: how many texts to load, the Find Ads provider and key, and the menu's toggles.
struct SettingsView: View {
    @AppStorage(Texts.limitKey) private var limit = 0
    @ObservedObject private var calls = Calls.shared
    @State private var aiError: String?
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Texts to load", selection: $limit) {
                    Text("Newest 1,000").tag(1000)
                    Text("Newest 5,000").tag(5000)
                    Text("Newest 20,000").tag(20000)
                    Text("All texts").tag(0)
                }
                .onChange(of: limit) { Texts.shared.resync() }
            } header: {
                Text("Texts")
            } footer: {
                Text("Load all of them to find ad senders who haven't texted you in a while. A long history takes a little longer each time the phone connects.")
                    .foregroundStyle(.secondary)
            }

            Section("Find Ads") {
                AIFields(error: $aiError)
                if let aiError {
                    Label(aiError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Section("General") {
                Toggle("Speakerphone for calls from the Mac", isOn: $calls.speakerphone)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) {
                        try? openAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
