import SwiftUI

/// Asks a model which senders are advertising, then lets you review and block them in bulk.
struct AdCheckView: View {
    @ObservedObject var texts: Texts
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiProvider") private var providerName = AIProvider.ollama.rawValue
    @AppStorage("aiModel") private var model = ""
    @State private var running = false
    @State private var checked = 0
    @State private var total = 0
    @State private var error: String?
    @State private var verdicts: [AdVerdict] = []
    @State private var chosen: Set<String> = []

    private var provider: AIProvider { AIProvider(rawValue: providerName) ?? .ollama }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find Ads").font(.title2.weight(.semibold))
            Form {
                AIFields(error: $error)
            }
            .formStyle(.grouped)
            .frame(height: provider.isLocal ? 110 : 150)

            Text(provider.isLocal
                 ? "Runs on this Mac. Your texts don't leave it."
                 : "The last few texts from each sender you never replied to are sent to \(provider == .claude ? "Anthropic" : "OpenAI"). Personal conversations aren't sent.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if running {
                ProgressView(value: Double(checked), total: Double(max(total, 1))) {
                    Text("Checked \(checked) of \(total) senders…")
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
                Button(verdicts.isEmpty ? "Check Texts" : "Check Again", action: check)
                    .disabled(running || model.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Block \(chosen.count) Sender\(chosen.count == 1 ? "" : "s")") {
                    texts.block(Array(chosen))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            if Demo.on { verdicts = Demo.adVerdicts(); chosen = ["MegaMart", "+15550177"] }
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
