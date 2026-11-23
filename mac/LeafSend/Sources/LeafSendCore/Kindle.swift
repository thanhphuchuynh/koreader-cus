import Foundation

/// The Mac's IPv4 address and netmask on Wi-Fi/Ethernet (first private, non-loopback interface).
public func localNetwork() -> (ip: UInt32, mask: UInt32)? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let a = p.pointee
        guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), let m = a.ifa_netmask,
              String(cString: a.ifa_name).hasPrefix("en") else { continue }
        let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
        let mask = m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
        let first = ip >> 24, second = (ip >> 16) & 0xff
        if first == 10 || (first == 172 && (16...31).contains(second)) || (first == 192 && second == 168) { return (ip, mask) }
    }
    return nil
}

public func dotted(_ ip: UInt32) -> String { "\(ip >> 24).\((ip >> 16) & 0xff).\((ip >> 8) & 0xff).\(ip & 0xff)" }

/// Every other host address in the subnet, nearest first. ponytail: capped at /22 (1022 hosts); wider nets scan only that block.
public func subnetHosts(ip: UInt32, mask: UInt32) -> [String] {
    let m = max(mask, 0xffff_fc00)
    let net = ip & m, bcast = net | ~m
    guard bcast > net + 1 else { return [] }
    return (net + 1 ..< bcast).filter { $0 != ip }
        .sorted { abs(Int64($0) - Int64(ip)) < abs(Int64($1) - Int64(ip)) }.map(dotted)
}

/// True when host:port answers with a dropbear SSH banner within `timeout` seconds.
public func isDropbear(_ host: String, port: UInt16, timeout: Double = 0.6) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    let ms = Int32(timeout * 1000)
    let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    if rc != 0 && errno != EINPROGRESS { return false }
    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    guard poll(&pfd, 1, ms) == 1 else { return false }
    var soErr: Int32 = 0; var len = socklen_t(MemoryLayout<Int32>.size)
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
    guard soErr == 0 else { return false }
    pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&pfd, 1, ms * 2) == 1 else { return false }
    var buf = [UInt8](repeating: 0, count: 64)
    let n = read(fd, &buf, buf.count)
    return n > 0 && String(decoding: buf[0..<n], as: UTF8.self).hasPrefix("SSH-2.0-dropbear")
}

/// Quote a path for an sftp batch file: inside double quotes, with \ " and glob characters escaped.
public func sftpQuote(_ s: String) -> String {
    var out = "\""
    for c in s { if "\\\"*?[]".contains(c) { out.append("\\") }; out.append(c) }
    return out + "\""
}

/// The sftp batch for a set of items: make each folder (ignoring "exists"), then put each file.
public func sftpBatch(_ items: [Item]) -> String {
    var lines: [String] = [], made = Set<String>()
    for it in items {
        var path = Router.documents
        for part in it.folder.split(separator: "/") {
            path += "/" + part
            if made.insert(path).inserted { lines.append("-mkdir " + sftpQuote(path)) }
        }
        lines.append("put " + sftpQuote(it.local.path) + " " + sftpQuote(it.remotePath))
    }
    return lines.joined(separator: "\n") + "\n"
}

/// KOReader's SSH server on the Kindle (dropbear, port 2222, user root), reached with the app's own key.
public struct Kindle {
    public static let port: UInt16 = 2222
    public let host: String
    public let key: URL
    public let knownHosts: URL

    public init(host: String, key: URL, knownHosts: URL) { self.host = host; self.key = key; self.knownHosts = knownHosts }

    var options: [String] {
        ["-i", key.path, "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", "-o", "IdentitiesOnly=yes",
         "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=" + knownHosts.path]
    }

    /// nil when this is our Kindle and the key works; otherwise why not.
    public func check() -> String? {
        let r = Shell.run("/usr/bin/ssh", options + ["-p", "\(Kindle.port)", "root@" + host, "test -d /mnt/us/koreadercus && echo leaf"])
        if r.status == 0 && String(decoding: r.out, as: UTF8.self).contains("leaf") { return nil }
        if r.err.contains("Permission denied") { return "key not set up on this Kindle" }
        // Closed before login: KOReader's dropbear could not create its host key, because koreadercus/settings/SSH
        // is missing (this build keeps KOReader's settings under profile/). Set up key (USB) creates it.
        if r.err.contains("Connection closed") { return "its SSH server has no host key folder yet" }
        return r.err.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? "not a Leaf Kindle"
    }

    /// Sends the items; nil on success, else sftp's error.
    public func send(_ items: [Item]) -> String? {
        let r = Shell.run("/usr/bin/sftp", options + ["-P", "\(Kindle.port)", "-b", "-", "root@" + host], input: sftpBatch(items))
        return r.status == 0 ? nil : r.err.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What is on the Kindle: book count per documents/ folder (Leaf folders first, then the rest A–Z) and free space.
public struct Summary: Equatable {
    public var folders: [(name: String, count: Int)]
    public var freeKB: Int?
    public var files: [String: [String]] = [:] // folder → book file names, A–Z
    public static func == (a: Summary, b: Summary) -> Bool { a.freeKB == b.freeKB && a.folders.map { "\($0.name)=\($0.count)" } == b.folders.map { "\($0.name)=\($0.count)" } }

    public static let leaf = ["IELTS", "IELTS/Listening", "IELTS/Reading"] + (1...7).map { "TOEIC/Part \($0)" } + [Router.inbox]

    /// `find documents -maxdepth 3 -type f` output, a "===" line, then the `df -k` line for /mnt/us.
    public static func parse(_ text: String) -> Summary {
        let parts = text.components(separatedBy: "\n===\n")
        var counts: [String: Int] = [:], files: [String: [String]] = [:]
        let prefix = Router.documents + "/"
        for line in parts[0].split(separator: "\n") where line.hasPrefix(prefix) {
            let rel = String(line.dropFirst(prefix.count))
            guard Router.books.contains((rel as NSString).pathExtension.lowercased()), !rel.contains(".sdr/") else { continue }
            let dir = (rel as NSString).deletingLastPathComponent
            let key = dir.isEmpty ? "(documents)" : dir
            counts[key, default: 0] += 1
            files[key, default: []].append((rel as NSString).lastPathComponent)
        }
        for k in files.keys { files[k]!.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
        var folders = leaf.filter { counts[$0] != nil || $0 == Router.inbox || $0 == "IELTS" }.map { ($0, counts[$0] ?? 0) }
        folders += counts.keys.filter { !leaf.contains($0) }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { ($0, counts[$0]!) }
        let df = parts.count > 1 ? parts[1].split(separator: " ").map(String.init) : []
        return Summary(folders: folders, freeKB: df.count >= 4 ? Int(df[3]) : nil, files: files)
    }

    public var text: String {
        var lines = [freeKB.map { String(format: "%.1f GB free", Double($0) / 1_048_576) } ?? "free space unknown"]
        for f in folders { lines.append("\(f.name)  ·  \(f.count)") }
        return lines.joined(separator: "\n")
    }
}

extension Kindle {
    /// Lists the Kindle's documents over SSH; nil and the error on failure.
    public func summary() -> (Summary?, String?) {
        let cmd = "find \(Router.documents) -maxdepth 3 -type f; echo ===; df -k /mnt/us | tail -1"
        let r = Shell.run("/usr/bin/ssh", options + ["-p", "\(Kindle.port)", "root@" + host, cmd])
        guard r.status == 0 else { return (nil, r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return (Summary.parse(String(decoding: r.out, as: UTF8.self)), nil)
    }
}
