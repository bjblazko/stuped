import Foundation

enum GitCLI {
    static func workingDirectory(for fileOrDirectoryURL: URL) -> URL {
        let normalizedURL = fileOrDirectoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return normalizedURL
        }
        return normalizedURL.deletingLastPathComponent()
    }

    static func repositoryRoot(for fileOrDirectoryURL: URL) -> URL? {
        let directoryURL = workingDirectory(for: fileOrDirectoryURL)
        guard let repoRootPath = runTrimmed("rev-parse", "--show-toplevel", in: directoryURL) else {
            return nil
        }
        return URL(fileURLWithPath: repoRootPath).standardizedFileURL
    }

    static func run(_ arguments: String..., in directory: URL) -> String? {
        run(arguments, in: directory)
    }

    static func run(_ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
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
        return String(data: data, encoding: .utf8)
    }

    static func runTrimmed(_ arguments: String..., in directory: URL) -> String? {
        runTrimmed(arguments, in: directory)
    }

    static func runTrimmed(_ arguments: [String], in directory: URL) -> String? {
        run(arguments, in: directory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
