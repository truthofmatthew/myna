import SwiftUI

/// Asks a model which senders are advertising, then lets you review and block them in bulk.
/// The provider, key and model are set in Settings; this sheet only shows which one it will use.
struct AdCheckView: View {
    @ObservedObject var texts: Texts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage("aiProvider") private var providerName = AIProvider.ollama.rawValue
    @AppStorage("aiModel") private var model = ""
    @State private var hasKey = false
    @State private var senders = 0
    @State private var running = false
    @State private var checked = 0
    @State private var total = 0
    @State private var error: String?
    @State private var verdicts: [AdVerdict] = []
    @State private var chosen: Set<String> = []

    private var provider: AIProvider { AIProvider(rawValue: providerName) ?? .ollama }
    private var ready: Bool { !model.isEmpty && (provider.isLocal || hasKey) }
    private var company: String { provider == .claude ? "Anthropic" : "OpenAI" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find Ads").font(.title2.weight(.semibold))
                    Text("An AI reads the latest texts from the \(senders.formatted()) senders you've never replied to and marks the ones that advertise. You choose who to block.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: provider.isLocal ? "desktopcomputer" : "cloud")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ready ? "\(provider.rawValue) · \(model)" : "Choose an AI in Settings first")
                        .font(.body.weight(.medium))
                    Text(provider.isLocal ? "Runs on this Mac. Your texts don't leave it."
                                          : "Sends each sender's last 3 texts to \(company). Conversations you've replied to aren't sent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(ready ? "Change…" : "Open Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate()
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if running {
                ProgressView(value: Double(checked), total: Double(max(total, 1))) {
                    Text("Checked \(checked) of \(total) senders…").monospacedDigit()
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }

            if !verdicts.isEmpty {
                List {
                    ForEach(verdicts) { v in
                        Toggle(isOn: Binding(get: { chosen.contains(v.address) },
                                             set: { if $0 { chosen.insert(v.address) } else { chosen.remove(v.address) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(v.title).font(.body.weight(.semibold))
                                    Spacer()
                                    Text(v.isAd ? "Ad · \(Int(v.confidence * 100))%" : "Not an ad")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(v.isAd && v.confidence >= 0.8 ? .red : .secondary)
                                }
                                Text(v.sample).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: v.sample.isRightToLeft ? .trailing : .leading)
                                if !v.reason.isEmpty { Text(v.reason).font(.caption).foregroundStyle(.tertiary) }
                            }
                        }
                    }
                }
                .frame(minHeight: 280)
            }

            HStack {
                if !verdicts.isEmpty {
                    Button("Check Again", action: check).disabled(running || !ready)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if verdicts.isEmpty {
                    Button("Check \(senders.formatted()) Sender\(senders == 1 ? "" : "s")", action: check)
                        .keyboardShortcut(.defaultAction)
                        .disabled(running || !ready || senders == 0)
                } else {
                    Button("Block \(chosen.count) Sender\(chosen.count == 1 ? "" : "s")") {
                        texts.block(Array(chosen))
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
                }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 560)
        .task {
            senders = texts.adCandidates().count
            if Demo.on { providerName = AIProvider.ollama.rawValue; model = "llama3.2"; verdicts = Demo.adVerdicts(); chosen = ["MegaMart", "+15550177"] }
        }
        // Settings can change the key while this sheet is open; look again when a window comes forward.
        .task(id: providerName) { hasKey = !provider.key.isEmpty }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasKey = !provider.key.isEmpty
        }
    }

    private func check() {
        let senders = texts.adCandidates()
        guard !senders.isEmpty else { error = "No senders to check: everyone who texts you is either blocked or someone you've replied to."; return }
        running = true
        error = nil
        checked = 0
        total = senders.count
        Task {
            do {
                let result = try await AdCheck.run(senders, client: AIClient(provider: provider, model: model)) { n in
                    Task { @MainActor in checked = n }
                }
                verdicts = result.sorted { ($0.isAd ? $0.confidence : -1 + $0.confidence) > ($1.isAd ? $1.confidence : -1 + $1.confidence) }
                chosen = Set(verdicts.filter { $0.isAd && $0.confidence >= 0.8 }.map(\.address))
            } catch {
                self.error = error.localizedDescription
            }
            running = false
        }
    }
}

/// Provider, API key and model for Find Ads, shared by the Find Ads sheet and Settings. The key is saved to the
/// Keychain and the model list loaded once typing stops; Check Texts needs a model from that list.
struct AIFields: View {
    @Binding var error: String?
    @AppStorage("aiProvider") private var providerName = AIProvider.ollama.rawValue
    @AppStorage("aiModel") private var model = ""
    @State private var key = ""
    @State private var models: [String] = []

    private var provider: AIProvider { AIProvider(rawValue: providerName) ?? .ollama }

    var body: some View {
        Picker("Check with", selection: $providerName) {
            ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        .task(id: providerName) {
            if Demo.on { providerName = AIProvider.ollama.rawValue; models = ["llama3.2"]; model = "llama3.2"; return }
            key = provider.key
            await loadModels()
        }
        if !provider.isLocal {
            HStack {
                SecureField("API key", text: $key)
                if let page = provider.keysPage { Link("Get a key", destination: page) }
            }
            .task(id: key) {
                guard key != provider.key else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                provider.key = key
                await loadModels()
            }
        }
        Picker("Model", selection: $model) {
            if models.isEmpty { Text(model.isEmpty ? "None found yet" : model).tag(model) }
            ForEach(models, id: \.self) { Text($0).tag($0) }
        }
    }

    private func loadModels() async {
        models = []
        error = nil
        do {
            models = try await AIClient(provider: provider, model: "").models()
            if !models.contains(model) { model = AIClient.suggested(models, for: provider) ?? "" }
        } catch {
            if provider.isLocal || !key.isEmpty { self.error = error.localizedDescription }
        }
    }
}
