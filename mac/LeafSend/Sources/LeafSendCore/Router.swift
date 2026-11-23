import Foundation

/// One file to send: where it is on the Mac, and the Kindle folder it goes into.
public struct Item: Equatable {
    public let local: URL
    public let folder: String // relative to documents/, e.g. "TOEIC/Part 5"
    public init(local: URL, folder: String) { self.local = local; self.folder = folder }
    public var remotePath: String { Router.documents + "/" + folder + "/" + local.lastPathComponent }
}

public enum RouteError: Error, CustomStringConvertible, Equatable {
    case unsupported(String)
    case missingAudio(String)
    case badTest(String)
    public var description: String {
        switch self {
        case .unsupported(let ext): return "not a book or test (.\(ext))"
        case .missingAudio(let f): return "listening test, but its audio \(f) is not next to it"
        case .badTest(let why): return "test file problem: \(why)"
        }
    }
}

public enum Router {
    public static let documents = "/mnt/us/documents"
    public static let books: Set<String> = ["epub", "pdf", "mobi", "azw", "azw3", "fb2", "txt", "cbz", "djvu"]
    public static let inbox = "From Mac"

    /// The files to send for one dropped file. `readKey` returns the EPUB's META-INF/leaf-ielts.json, if any.
    public static func plan(_ url: URL, readKey: (URL) -> Data? = Zip.leafKey) throws -> [Item] {
        let ext = url.pathExtension.lowercased()
        guard books.contains(ext) else { throw RouteError.unsupported(ext) }
        guard ext == "epub", let data = readKey(url) else { return [Item(local: url, folder: inbox)] }
        guard let key = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RouteError.badTest("answer key is not JSON") }
        let listening = key["skill"] as? String == "listening"
        let folder: String
        if key["exam"] as? String == "toeic" {
            guard let part = key["part"] as? Int, (1...7).contains(part) else { throw RouteError.badTest("TOEIC part must be 1-7") }
            folder = "TOEIC/Part \(part)"
        } else {
            folder = listening ? "IELTS/Listening" : "IELTS"
        }
        var items = [Item(local: url, folder: folder)]
        if listening {
            guard let file = (key["audio"] as? [String: Any])?["file"] as? String, !file.isEmpty,
                  !file.contains("/"), !file.contains("..") else { throw RouteError.badTest("listening test without audio.file") }
            let audio = url.deletingLastPathComponent().appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: audio.path) else { throw RouteError.missingAudio(file) }
            items.append(Item(local: audio, folder: folder))
        }
        return items
    }
}

public enum Zip {
    /// META-INF/leaf-ielts.json from an EPUB, via macOS unzip; nil when the book is not a Leaf test.
    public static func leafKey(_ url: URL) -> Data? {
        let r = Shell.run("/usr/bin/unzip", ["-p", url.path, "META-INF/leaf-ielts.json"])
        return r.status == 0 && !r.out.isEmpty ? r.out : nil
    }
}

public enum Shell {
    public struct Result { public let status: Int32; public let out: Data; public let err: String }
    /// Runs a tool without a shell (arguments are never parsed), optionally feeding stdin.
    public static func run(_ tool: String, _ args: [String], input: String? = nil) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        do { try p.run() } catch { return Result(status: -1, out: Data(), err: "\(error)") }
        if let input { inp.fileHandleForWriting.write(Data(input.utf8)) }
        try? inp.fileHandleForWriting.close()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, out: o, err: String(decoding: e, as: UTF8.self))
    }
}
