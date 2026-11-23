import Foundation

public enum Setup {
    public static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LeafSend")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    public static var key: URL { dir.appendingPathComponent("id_ed25519") }
    public static var knownHosts: URL { dir.appendingPathComponent("known_hosts") }

    /// The app's own SSH key pair, made on first use (no passphrase: it only opens the Kindle).
    public static func ensureKey() -> String? {
        if FileManager.default.fileExists(atPath: key.path) { return nil }
        let r = Shell.run("/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "leafsend", "-f", key.path])
        return r.status == 0 ? nil : r.err
    }

    /// Adds the public key to KOReader's authorized_keys on a USB-mounted Kindle. Returns the files written.
    /// Both candidate folders: the patched dropbear reads settings/SSH/authorized_keys relative to KOReader's folder.
    public static func installKey(volume: URL = URL(fileURLWithPath: "/Volumes/Kindle")) throws -> [String] {
        let fm = FileManager.default
        let ko = volume.appendingPathComponent("koreadercus")
        guard fm.fileExists(atPath: ko.path) else { throw NSError(domain: "LeafSend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kindle not plugged in by USB (no /Volumes/Kindle/koreadercus)"]) }
        if let e = ensureKey() { throw NSError(domain: "LeafSend", code: 2, userInfo: [NSLocalizedDescriptionKey: e]) }
        let pub = try String(contentsOf: key.appendingPathExtension("pub"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        var written: [String] = []
        for sub in ["settings/SSH", "profile/settings/SSH"] {
            let d = ko.appendingPathComponent(sub)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            let f = d.appendingPathComponent("authorized_keys")
            let old = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
            if !old.contains(pub) {
                try (old + (old.isEmpty || old.hasSuffix("\n") ? "" : "\n") + pub + "\n").write(to: f, atomically: false, encoding: .utf8)
            }
            written.append(f.path)
        }
        return written
    }

    /// Finds the Kindle: the last address first, then dropbear on port 2222 anywhere in the subnet.
    /// Returns the host and nil, or the first dropbear host and why it failed the check, or nil.
    public static func find(last: String?, progress: (String) -> Void = { _ in }) -> (host: String, problem: String?)? {
        func check(_ h: String) -> String? { Kindle(host: h, key: key, knownHosts: knownHosts).check() }
        if let last, isDropbear(last, port: Kindle.port), check(last) == nil { return (last, nil) }
        guard let net = localNetwork() else { progress("No Wi-Fi network"); return nil }
        let hosts = subnetHosts(ip: net.ip, mask: net.mask)
        progress("Looking on \(dotted(net.ip & net.mask))… (\(hosts.count) addresses)")
        var found: [String] = []
        let lock = NSLock()
        // 64 probes at once: most addresses never answer, so each costs its full timeout (~5 s for a /23).
        let q = OperationQueue(); q.maxConcurrentOperationCount = 64
        for h in hosts { q.addOperation { if isDropbear(h, port: Kindle.port) { lock.lock(); found.append(h); lock.unlock() } } }
        q.waitUntilAllOperationsAreFinished()
        var firstProblem: (String, String)?
        for h in found {
            guard let p = check(h) else { return (h, nil) }
            if firstProblem == nil { firstProblem = (h, p) }
        }
        return firstProblem.map { ($0.0, $0.1) }
    }
}
