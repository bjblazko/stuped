import Foundation

@Observable
final class RecentFoldersStore {
    static let shared = RecentFoldersStore()

    private static let defaultsKey = "recentFolders.paths"
    private static let maxCount = 10

    private let defaults: UserDefaults
    private(set) var storedPaths: [String]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storedPaths = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        pruneMissingFolders()
    }

    var recentFolders: [URL] {
        storedPaths.compactMap { path in
            Self.normalizedFolderURL(fromPath: path)
        }
    }

    func record(_ url: URL) {
        guard let normalized = Self.normalizedFolderURL(from: url) else { return }

        storedPaths.removeAll { $0 == normalized.path }
        storedPaths.insert(normalized.path, at: 0)

        if storedPaths.count > Self.maxCount {
            storedPaths.removeSubrange(Self.maxCount...)
        }

        persist()
    }

    func clear() {
        guard !storedPaths.isEmpty else { return }
        storedPaths.removeAll()
        persist()
    }

    private func pruneMissingFolders() {
        let validPaths = storedPaths.compactMap { path in
            Self.normalizedFolderURL(fromPath: path)?.path
        }

        let trimmedPaths = Array(validPaths.prefix(Self.maxCount))
        guard trimmedPaths != storedPaths else { return }

        storedPaths = trimmedPaths
        persist()
    }

    private static func normalizedFolderURL(from url: URL) -> URL? {
        normalizedFolderURL(fromPath: url.standardizedFileURL.path)
    }

    private static func normalizedFolderURL(fromPath path: String) -> URL? {
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return url
    }

    private func persist() {
        defaults.set(storedPaths, forKey: Self.defaultsKey)
    }
}
