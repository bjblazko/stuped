import Foundation

struct GitInfo {
    let branchName: String
    let remoteURL: String?
    let repoRoot: URL

    static func fetch(for fileURL: URL) async -> GitInfo? {
        let directoryURL: URL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            directoryURL = fileURL
        } else {
            directoryURL = fileURL.deletingLastPathComponent()
        }

        guard let repoRootPath = run("rev-parse", "--show-toplevel", in: directoryURL) else {
            return nil
        }

        let repoRoot = URL(fileURLWithPath: repoRootPath)

        let branch = run("branch", "--show-current", in: directoryURL)

        let branchName: String
        if let branch, !branch.isEmpty {
            branchName = branch
        } else {
            branchName = run("rev-parse", "--short", "HEAD", in: directoryURL) ?? "HEAD"
        }

        let remoteURL = run("config", "--get", "remote.origin.url", in: directoryURL)

        return GitInfo(branchName: branchName, remoteURL: remoteURL, repoRoot: repoRoot)
    }

    private static func run(_ arguments: String..., in directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = Array(arguments)
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
