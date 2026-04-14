import SwiftUI

struct ImagePreviewView: View {
    let fileURL: URL

    @State private var nsImage: NSImage?
    @State private var fileSize: String = ""

    var body: some View {
        Group {
            if let nsImage = nsImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
                .overlay(alignment: .bottomTrailing) {
                    imageInfo(nsImage)
                        .padding(8)
                }
            } else {
                ContentUnavailableView("Unable to Load Image",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text(fileURL.lastPathComponent))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { loadImage() }
        .onChange(of: fileURL) { _, _ in loadImage() }
    }

    private func loadImage() {
        nsImage = NSImage(contentsOf: fileURL)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? UInt64 {
            fileSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } else {
            fileSize = ""
        }
    }

    private func imageInfo(_ image: NSImage) -> some View {
        let rep = image.representations.first
        let w = rep?.pixelsWide ?? Int(image.size.width)
        let h = rep?.pixelsHigh ?? Int(image.size.height)

        return Text("\(w) × \(h)  ·  \(fileSize)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
