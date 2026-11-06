import SwiftUI

/// Conversation list on the left, the selected conversation (or a new one) on the right.
struct MessagesView: View {
    @ObservedObject var texts: Texts
    @State private var showBlocked = false
    @State private var showAdCheck = false
    @State private var search = ""
    static let newMessage: Int64 = -1

    private var shown: [Conversation] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return texts.conversations }
        return texts.conversations.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.address.contains(q) || $0.last.body.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $texts.selected) {
                ForEach(shown) { c in
                    ConversationRow(conversation: c)
                        .tag(c.id)
                        .contextMenu {
                            if c.unread > 0 { Button("Mark as Read") { texts.markRead(c) } }
                            Button("Block \(c.title)") { texts.block([c.address]) }
                            Divider()
                            Button("Delete Conversation", role: .destructive) { texts.delete(c.messages.map(\.id)) }
                        }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 240, ideal: 290)
            .overlay {
                if texts.conversations.isEmpty {
                    ContentUnavailableView("No texts yet", systemImage: "message",
                                           description: Text("Texts from your phone show up here once it's connected."))
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { showAdCheck = true } label: { Label("Find Ads", systemImage: "sparkles") }
                        .help("Find advertising texts with AI")
                    Button { showBlocked = true } label: { Label("Blocked Numbers", systemImage: "hand.raised") }
                        .help("Blocked numbers")
                    Button { texts.selected = Self.newMessage } label: { Label("New Message", systemImage: "square.and.pencil") }
                        .help("New message")
                }
            }
        } detail: {
            Group {
                if texts.selected == Self.newMessage {
                    ConversationView(texts: texts, conversation: nil)
                } else if let c = texts.conversations.first(where: { $0.id == texts.selected }) {
                    ConversationView(texts: texts, conversation: c).id(c.id)
                } else {
                    ContentUnavailableView("Pick a conversation", systemImage: "message")
                }
            }
            .toolbarBackground(.visible, for: .windowToolbar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBars(texts: texts) }
        .sheet(isPresented: $showBlocked) { BlockedView(texts: texts) }
        .sheet(isPresented: $showAdCheck) { AdCheckView(texts: texts) }
        .onChange(of: texts.selected) { _, id in
            if let c = texts.conversations.first(where: { $0.id == id }) { texts.markRead(c) }
        }
    }
}

/// Pending phone changes and problems, along the bottom of the window.
private struct StatusBars: View {
    @ObservedObject var texts: Texts

    var body: some View {
        VStack(spacing: 0) {
            if !texts.pending.isEmpty {
                Divider()
                HStack {
                    Image(systemName: texts.waitingForPhone ? "iphone.radiowaves.left.and.right" : "clock")
                    Text(texts.waitingForPhone ? "Approve on your phone: tap Myna's notification there."
                                               : "Waiting for your phone: \(texts.pending.summary).")
                    Spacer()
                    Button(texts.waitingForPhone ? "Send Again" : "Apply on Phone") { texts.applyOnPhone() }
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.bar)
            }
            if let problem = texts.problem {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(problem)
                    Spacer()
                    Button("Dismiss") { texts.dismissProblem() }
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.bar)
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(title: conversation.title)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .font(.body.weight(conversation.unread > 0 ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conversation.last.date.messageListStamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text(conversation.last.body.replacingOccurrences(of: "\n", with: " "))
                        .font(.callout)
                        .foregroundStyle(conversation.unread > 0 ? .primary : .secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: conversation.last.body.isRightToLeft ? .trailing : .leading)
                        .multilineTextAlignment(conversation.last.body.isRightToLeft ? .trailing : .leading)
                    if conversation.unread > 0 {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.top, 5)
                            .accessibilityLabel("\(conversation.unread) unread")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Avatar: View {
    let title: String

    var body: some View {
        let letter = title.first(where: \.isLetter).map { String($0).uppercased() }
        ZStack {
            Circle().fill(Color.secondary.opacity(0.25))
            if let letter { Text(letter).font(.headline) } else { Image(systemName: "person.fill").foregroundStyle(.secondary) }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

private struct ConversationView: View {
    @ObservedObject var texts: Texts
    let conversation: Conversation?
    @State private var to = ""
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if conversation == nil {
                HStack {
                    Text("To:").foregroundStyle(.secondary)
                    TextField("Phone number", text: $to).textFieldStyle(.plain)
                }
                .padding(12)
                Divider()
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        let messages = conversation?.messages ?? []
                        ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                            if i == 0 || m.date.timeIntervalSince(messages[i - 1].date) > 30 * 60 {
                                Text(m.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, i == 0 ? 0 : 12)
                                    .padding(.bottom, 4)
                            }
                            Bubble(message: m)
                                .id(m.id)
                                .contextMenu {
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(m.body, forType: .string)
                                    }
                                    Button("Delete", role: .destructive) { texts.delete([m.id]) }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: conversation?.last.id) { _, id in if let id { withAnimation { scroll.scrollTo(id, anchor: .bottom) } } }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Text message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($typing)
                    .onSubmit(send)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
                Button(action: send) { Image(systemName: "arrow.up").font(.body.weight(.semibold)) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || address.isEmpty)
                    .help("Send (⌘↩)")
                    .accessibilityLabel("Send")
            }
            .padding(12)
        }
        .navigationTitle(conversation?.title ?? "New Message")
        .navigationSubtitle(conversation.flatMap { $0.title == $0.address ? nil : $0.address } ?? "")
        .onAppear { typing = true }
    }

    private var address: String { conversation?.address ?? to.trimmingCharacters(in: .whitespaces) }

    private func send() {
        guard !address.isEmpty else { return }
        texts.send(to: address, body: draft)
        draft = ""
    }
}

private struct Bubble: View {
    let message: TextMessage

    var body: some View {
        HStack {
            if message.mine { Spacer(minLength: 80) }
            Text(message.body)
                .textSelection(.enabled)
                .multilineTextAlignment(message.body.isRightToLeft ? .trailing : .leading)
                .environment(\.layoutDirection, message.body.isRightToLeft ? .rightToLeft : .leftToRight)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(message.failed ? Color.red.opacity(0.7) : message.mine ? Color.accentColor : Color.secondary.opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(message.mine ? .white : .primary)
                .help(message.failed ? "Not sent" : message.date.formatted(date: .abbreviated, time: .shortened))
            if !message.mine { Spacer(minLength: 80) }
        }
    }
}

extension String {
    /// Persian and Arabic texts read right to left; the first letter decides.
    var isRightToLeft: Bool {
        unicodeScalars.first { $0.properties.isAlphabetic }
            .map { (0x0590...0x08FF).contains($0.value) || (0xFB1D...0xFEFF).contains($0.value) } ?? false
    }
}

extension Date {
    /// Time today, weekday this week, date before that.
    var messageListStamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if let days = cal.dateComponents([.day], from: self, to: .now).day, days < 7 { return formatted(.dateTime.weekday(.abbreviated)) }
        return formatted(date: .numeric, time: .omitted)
    }
}
