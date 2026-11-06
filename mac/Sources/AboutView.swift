import SwiftUI

/// Matches Bower's About window, in Myna's colours.
struct AboutView: View {
    private let version: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }()

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

            Text(verbatim: "Myna")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .padding(.top, 6)
            Text(verbatim: version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Your Android phone's texts, calls, camera and mic, on your Mac.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Divider().padding(.vertical, 22)

            Text("Made by")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "Matthew Truth")
                .font(.title3.weight(.semibold))
                .padding(.top, 2)

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/truthofmatthew/myna")!) {
                    Label { Text(verbatim: "GitHub") } icon: { Image("GitHub").resizable().frame(width: 14, height: 14) }
                }
                .help("github.com/truthofmatthew/myna")
                Link(destination: URL(string: "https://truthofmatthew.com/projects/myna/")!) {
                    Label { Text(verbatim: "truthofmatthew.com") } icon: { Image(systemName: "globe") }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, 16)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 30)
        .frame(width: 430)
        .background(alignment: .top) {
            // The icon's indigo sky, faded into the window behind it.
            LinearGradient(colors: [Color(red: 0x4A / 255, green: 0x3B / 255, blue: 0x9C / 255).opacity(0.55),
                                    Color(red: 0x6E / 255, green: 0x5B / 255, blue: 0xC9 / 255).opacity(0.10), .clear],
                           startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
        }
    }
}
