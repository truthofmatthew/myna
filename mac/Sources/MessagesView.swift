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

    private func picked(_ ids: Set<Int64>) -> [Conversation] { texts.conversations.filter { ids.contains($0.id) } }

    var body: some View {
        NavigationSplitView {
            List(selection: $texts.selection) {
                ForEach(shown) { c in
                    ConversationRow(conversation: c).tag(c.id)
                }
            }
            .contextMenu(forSelectionType: Int64.self) { ids in
                let cs = picked(ids)
                if !cs.isEmpty {
                    BulkActions(texts: texts, conversations: cs)
                    Divider()
                }
                Button("Select All") { texts.selection = Set(shown.map(\.id)) }
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
                    Button { texts.selection = [Self.newMessage] } label: { Label("New Message", systemImage: "square.and.pencil") }
                        .help("New message")
                }
            }
        } detail: {
            let cs = picked(texts.selection)
            Group {
                if texts.selection == [Self.newMessage] {
                    ConversationView(texts: texts, conversation: nil)
                } else if cs.count > 1 {
                    BulkView(texts: texts, conversations: cs, all: shown.map(\.id))
                } else if let c = cs.first {
                    ConversationView(texts: texts, conversation: c).id(c.id)
                } else {
                    ContentUnavailableView("Pick a conversation", systemImage: "message")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBars(texts: texts) }
        .sheet(isPresented: $showBlocked) { BlockedView(texts: texts) }
        .sheet(isPresented: $showAdCheck) { AdCheckView(texts: texts) }
        .onAppear {
            if Demo.on { showAdCheck = Demo.scene == "ads"; showBlocked = Demo.scene == "blocked" }
        }
        .onChange(of: texts.selection) { _, ids in
            // Opening one conversation reads it; selecting several for bulk actions doesn't.
            if ids.count == 1, let c = picked(ids).first { texts.markRead(c) }
        }
    }
}

/// Mark Read, Block and Delete for one or many conversations; used in the context menu and the bulk view.
private struct BulkActions: View {
    @ObservedObject var texts: Texts
    let conversations: [Conversation]

    var body: some View {
        let n = conversations.count
        let what = n == 1 ? conversations[0].title : "\(n) Conversations"
        if conversations.contains(where: { $0.unread > 0 }) {
            Button("Mark \(n == 1 ? "" : "\(n) ")as Read") { conversations.forEach(texts.markRead) }
        }
        Button("Block \(n == 1 ? what : "\(n) Senders")") { texts.block(conversations.map(\.address)) }
        Button("Delete \(n == 1 ? "Conversation" : what)", role: .destructive) {
            texts.delete(conversations.flatMap { $0.messages.map(\.id) })
            texts.selection = []
        }
    }
}

/// Shown when several conversations are selected.
private struct BulkView: View {
    @ObservedObject var texts: Texts
    let conversations: [Conversation]
    let all: [Int64] // everything the list shows, for Select All

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("\(conversations.count) conversations selected").font(.title3.weight(.semibold))
            Text("⌘-click or ⇧-click to change the selection, ⌘A to select all.")
                .foregroundStyle(.secondary)
            HStack {
                BulkActions(texts: texts, conversations: conversations)
            }
            .buttonStyle(.bordered)
            if conversations.count < all.count {
                Button("Select All \(all.count)") { texts.selection = Set(all) }.buttonStyle(.link)
            }
        }
        .padding(32)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Calls.shared.dial(address) } label: { Label("Call", systemImage: "phone") }
                    .help(address.isEmpty ? "Type a number to call" : "Call \(address) from your phone")
                    .disabled(address.isEmpty)
            }
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
