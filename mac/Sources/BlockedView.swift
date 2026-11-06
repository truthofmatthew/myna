import SwiftUI

/// The block list: the phone's system list as of the last batch, plus changes waiting for the phone.
struct BlockedView: View {
    @ObservedObject var texts: Texts
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blocked Numbers").font(.title2.weight(.semibold))
            Text("Texts from these numbers stay out of Messages and don't notify. Blocking on the phone itself happens when you apply changes there.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Number or sender name", text: $number)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Block", action: add).disabled(number.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List(selection: $selection) {
                ForEach(texts.blocked, id: \.self) { n in
                    HStack {
                        Text(n).font(.body.monospacedDigit())
                        Spacer()
                        if texts.pending.block.contains(n) { Text("Waiting for phone").font(.caption).foregroundStyle(.secondary) }
                        Button("Unblock") { texts.unblock(n) }.buttonStyle(.link)
                    }
                    .tag(n)
                }
            }
            .frame(minHeight: 240)
            .overlay {
                if texts.blocked.isEmpty {
                    ContentUnavailableView("No blocked numbers", systemImage: "hand.raised",
                                           description: Text("Block a number here, from a conversation, or with Find Ads."))
                }
            }

            HStack {
                Button("Export CSV…") { texts.exportBlocked() }.disabled(texts.blocked.isEmpty)
                if !texts.pending.isEmpty {
                    Button("Apply on Phone") { texts.applyOnPhone() }
                        .help("Your phone asks you to approve: \(texts.pending.summary)")
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func add() {
        texts.block([number])
        number = ""
    }
}
