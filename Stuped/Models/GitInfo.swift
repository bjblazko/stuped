import Foundation

struct GitInfo {
    let branchName: String
    let remoteURL: String?
    let repoRoot: URL

    static func fetch(for fileURL: URL) async -> GitInfo? {
        let directoryURL = GitCLI.workingDirectory(for: fileURL)
        guard let repoRoot = GitCLI.repositoryRoot(for: fileURL) else {
            return nil
        }

        let branch = GitCLI.runTrimmed("branch", "--show-current", in: directoryURL)

        let branchName: String
        if let branch, !branch.isEmpty {
            branchName = branch
        } else {
            branchName = GitCLI.runTrimmed("rev-parse", "--short", "HEAD", in: directoryURL) ?? "HEAD"
        }

        let remoteURL = GitCLI.runTrimmed("config", "--get", "remote.origin.url", in: directoryURL)

        return GitInfo(branchName: branchName, remoteURL: remoteURL, repoRoot: repoRoot)
    }
}
