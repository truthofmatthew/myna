import SwiftUI

/// Conversation list on the left, the selected conversation (or a new one) on the right.
struct MessagesView: View {
    @ObservedObject var texts: Texts
    static let newMessage: Int64 = -1

    var body: some View {
        NavigationSplitView {
            List(selection: $texts.selected) {
                ForEach(texts.conversations) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.title).font(.headline).lineLimit(1)
                            Spacer()
                            Text(c.last.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(c.last.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.vertical, 3)
                    .tag(c.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if texts.conversations.isEmpty {
                    ContentUnavailableView("No texts yet", systemImage: "message",
                                           description: Text("Texts from your phone show up here once it's connected."))
                }
            }
            .toolbar {
                Button { texts.selected = Self.newMessage } label: { Label("New Message", systemImage: "square.and.pencil") }
                    .help("New message")
            }
        } detail: {
            if texts.selected == Self.newMessage {
                ComposeView(texts: texts, conversation: nil)
            } else if let c = texts.conversations.first(where: { $0.id == texts.selected }) {
                ComposeView(texts: texts, conversation: c)
            } else {
                ContentUnavailableView("Pick a conversation", systemImage: "message")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let problem = texts.problem {
                Text(problem)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.yellow.opacity(0.25))
            }
        }
    }
}

private struct ComposeView: View {
    @ObservedObject var texts: Texts
    let conversation: Conversation?
    @State private var to = ""
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if conversation == nil {
                TextField("To: phone number", text: $to)
                    .textFieldStyle(.roundedBorder)
                    .padding(12)
                Divider()
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(conversation?.messages ?? []) { Bubble(message: $0).id($0.id) }
                    }
                    .padding(12)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: conversation?.last.id) { _, id in if let id { scroll.scrollTo(id, anchor: .bottom) } }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField("Text message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($typing)
                    .onSubmit(send)
                Button("Send", action: send)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || address.isEmpty)
            }
            .padding(12)
        }
        .navigationTitle(conversation?.title ?? "New Message")
        .onAppear { typing = true }
    }

    private var address: String { conversation?.last.address ?? to.trimmingCharacters(in: .whitespaces) }

    private func send() {
        texts.send(to: address, body: draft)
        draft = ""
    }
}

private struct Bubble: View {
    let message: TextMessage

    var body: some View {
        HStack {
            if message.mine { Spacer(minLength: 60) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .textSelection(.enabled)
                    .multilineTextAlignment(rightToLeft ? .trailing : .leading)
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(message.mine ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(message.mine ? .white : .primary)
                Text(message.failed ? "Not sent" : message.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(message.failed ? .red : .secondary)
            }
            if !message.mine { Spacer(minLength: 60) }
        }
    }

    /// Persian and Arabic texts read right to left; the first letter decides.
    private var rightToLeft: Bool {
        message.body.unicodeScalars.first { $0.properties.isAlphabetic }.map { (0x0590...0x08FF).contains($0.value) || (0xFB1D...0xFEFF).contains($0.value) } ?? false
    }
}
