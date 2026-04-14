import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Stuped")
                    .font(.title.bold())
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 6) {
                Text("© 2026 Timo Böwing")
                    .font(.footnote)
                Link("Hüpattl! Software  ↗", destination: URL(string: "https://huepattl.de")!)
                    .font(.footnote)
                Link("GitHub  ↗", destination: URL(string: "https://github.com/bjblazko/stuped")!)
                    .font(.footnote)
                Link("Apache License 2.0  ↗", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
                    .font(.footnote)
            }

            Button("Close") {
                NSApplication.shared.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 300)
    }
}
