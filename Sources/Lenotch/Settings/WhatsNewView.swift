import AppKit
import SwiftUI

/// The notes of the installed version, from its GitHub release. Shown once after an
/// update, and from Settings → General → Help.
struct WhatsNewView: View {
    let version: String
    let close: () -> Void

    @State private var items: [String]?
    @State private var failed = false

    private var releaseURL: URL {
        URL(string: "https://github.com/lephorx/lenotch/releases/tag/v\(version)")!
    }

    var body: some View {
        VStack(spacing: 18) {
            AppLogo(height: 54, glass: false)
                .padding(.top, 34)
            VStack(spacing: 4) {
                Text("What's New").font(.system(size: 22, weight: .bold))
                Text("Lenotch \(version)").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Group {
                if let items {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                    Text(Self.inline(item)).font(.system(size: 13))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                    }
                } else if failed {
                    Text("The notes couldn't be loaded. You can read them on GitHub.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Button("View on GitHub") { NSWorkspace.shared.open(releaseURL) }
                Spacer()
                Button("Continue", action: close)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 440, height: 460)
        .task { await load() }
    }

    private func load() async {
        let api = URL(string: "https://api.github.com/repos/lephorx/lenotch/releases/tags/v\(version)")!
        do {
            var request = URLRequest(url: api, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["body"] as? String
            else { throw URLError(.badServerResponse) }
            let lines = body.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
                .map { String($0.dropFirst(2)) }
                // GitHub's generated notes end in "by @user in <pull request link>".
                .map { $0.replacingOccurrences(of: #" by @\S+ in https://\S+$"#, with: "", options: .regularExpression) }
            if lines.isEmpty { failed = true } else { items = lines }
        } catch {
            failed = true
        }
    }

    /// Bold, italics, code and links in a note.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
