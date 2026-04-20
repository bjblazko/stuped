import Foundation
import UniformTypeIdentifiers
import WebKit

final class PreviewTempStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("com.huepattl.Stuped.preview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func write(html: String) throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let htmlFileURL = directoryURL.appendingPathComponent("index.html")
        try html.write(to: htmlFileURL, atomically: true, encoding: .utf8)
        return htmlFileURL
    }

    func cleanup() {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            print("[Stuped] Failed to remove preview temp directory: \(error.localizedDescription)")
        }
    }
}

final class PreviewURLSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "stuped-preview"
    static let previewURL = URL(string: "\(scheme)://preview/index.html")!
    static let rootURL = URL(string: "\(scheme)://preview/root/")!

    private struct Session {
        let htmlFileURL: URL
        let baseURL: URL?
    }

    private let lock = NSLock()
    private var session: Session?

    func update(htmlFileURL: URL, baseURL: URL?) {
        lock.lock()
        session = Session(htmlFileURL: htmlFileURL, baseURL: baseURL)
        lock.unlock()
    }

    func clearSession() {
        lock.lock()
        session = nil
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(PreviewURLSchemeError.invalidRequest)
            return
        }

        let currentSession: Session?
        lock.lock()
        currentSession = session
        lock.unlock()

        guard let currentSession else {
            urlSchemeTask.didFailWithError(PreviewURLSchemeError.sessionUnavailable)
            return
        }

        do {
            switch requestURL.path {
            case "/index.html":
                try respond(withFileAt: currentSession.htmlFileURL, mimeType: "text/html", textEncodingName: "utf-8", to: urlSchemeTask)
            default:
                guard let assetURL = resolvedAssetURL(for: requestURL, baseURL: currentSession.baseURL) else {
                    throw PreviewURLSchemeError.fileNotFound
                }
                try respond(withFileAt: assetURL, mimeType: mimeType(for: assetURL), textEncodingName: textEncodingName(for: assetURL), to: urlSchemeTask)
            }
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Requests are served synchronously from local disk; nothing to cancel.
    }

    private func resolvedAssetURL(for requestURL: URL, baseURL: URL?) -> URL? {
        guard let baseURL else { return nil }

        let rootPrefix = "/root/"
        let requestPath = requestURL.path
        guard requestPath.hasPrefix(rootPrefix) else { return nil }

        let relativePath = String(requestPath.dropFirst(rootPrefix.count))
        guard !relativePath.isEmpty else { return nil }

        let decodedPath = relativePath.removingPercentEncoding ?? relativePath
        let standardizedBaseURL = baseURL.standardizedFileURL.resolvingSymlinksInPath()

        var candidateURL = standardizedBaseURL
        for component in decodedPath.split(separator: "/", omittingEmptySubsequences: true) {
            candidateURL.appendPathComponent(String(component))
        }
        candidateURL = candidateURL.standardizedFileURL.resolvingSymlinksInPath()

        let basePath = standardizedBaseURL.path
        let candidatePath = candidateURL.path
        guard candidatePath == basePath || candidatePath.hasPrefix(basePath + "/") else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidatePath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }

        return candidateURL
    }

    private func respond(withFileAt fileURL: URL,
                         mimeType: String,
                         textEncodingName: String?,
                         to urlSchemeTask: WKURLSchemeTask) throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let response = URLResponse(url: urlSchemeTask.request.url!,
                                   mimeType: mimeType,
                                   expectedContentLength: data.count,
                                   textEncodingName: textEncodingName)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    private func mimeType(for fileURL: URL) -> String {
        guard let type = UTType(filenameExtension: fileURL.pathExtension),
              let mimeType = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mimeType
    }

    private func textEncodingName(for fileURL: URL) -> String? {
        let mimeType = mimeType(for: fileURL)
        if mimeType.hasPrefix("text/") || mimeType == "application/javascript" || mimeType == "application/json" {
            return "utf-8"
        }
        return nil
    }

    private var fileManager: FileManager {
        .default
    }
}

private enum PreviewURLSchemeError: LocalizedError {
    case invalidRequest
    case sessionUnavailable
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid preview request."
        case .sessionUnavailable:
            return "Preview session is unavailable."
        case .fileNotFound:
            return "Preview asset not found."
        }
    }
}
