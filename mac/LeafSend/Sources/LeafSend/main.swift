import AppKit
import LeafSendCore

// AppKit, not SwiftUI: SwiftUI's property wrappers need Xcode's macro plugins, absent from Command Line Tools.

/// Dashed drop area: accepts file URLs and hands them to `onDrop`.
final class DropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }
    var label = "" { didSet { needsDisplay = true } }
    private var targeted = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        path.lineWidth = 2; path.setLineDash([8, 6], count: 2, phase: 0)
        (targeted ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke(); path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.secondaryLabelColor]
        let s = NSAttributedString(string: label, attributes: attrs), sz = s.size()
        s.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
    }
    private func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { targeted = !urls(info).isEmpty; return targeted ? .copy : [] }
    override func draggingExited(_ info: NSDraggingInfo?) { targeted = false }
    override func performDragOperation(_ info: NSDraggingInfo) -> Bool { targeted = false; onDrop(urls(info)); return true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow!
    let status = NSTextField(labelWithString: "Not connected")
    let dot = NSTextField(labelWithString: "●")
    let spinner = NSProgressIndicator()
    let drop = DropView()
    let logView = NSTextView()
    let freeLabel = NSTextField(labelWithString: "Connect to see the Kindle's folders.")
    let table = NSTableView()
    var summary: Summary?
    var findButton: NSButton!, keyButton: NSButton!
    var host: String?
    var busy = false { didSet { findButton.isEnabled = !busy; keyButton.isEnabled = !busy; busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil) } }
    let lastKey = "lastKindleHost"

    func applicationDidFinishLaunching(_ n: Notification) {
        findButton = NSButton(title: "Find Kindle", target: self, action: #selector(find))
        keyButton = NSButton(title: "Set up key (USB)", target: self, action: #selector(setupKey))
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dot.textColor = .systemGray
        let top = NSStackView(views: [dot, status, spinner, findButton, keyButton])
        top.spacing = 8
        let note = NSTextField(labelWithString: "Tests go to TOEIC/Part N, IELTS or IELTS/Listening; other books to From Mac.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        logView.isEditable = false; logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scroll = NSScrollView(); scroll.documentView = logView; scroll.hasVerticalScroller = true
        logView.autoresizingMask = [.width]; logView.isVerticallyResizable = true
        drop.onDrop = { [weak self] in self?.send($0) }
        let onKindle = NSTextField(labelWithString: "ON THE KINDLE")
        onKindle.font = .systemFont(ofSize: 11, weight: .semibold); onKindle.textColor = .secondaryLabelColor
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshSummary))
        refresh.controlSize = .small; refresh.bezelStyle = .rounded
        let head = NSStackView(views: [onKindle, refresh])
        let col = NSTableColumn(identifier: .init("folder")); col.title = "Folder"
        table.addTableColumn(col); table.headerView = nil; table.dataSource = self; table.delegate = self
        table.rowHeight = 22; table.style = .plain
        freeLabel.font = .systemFont(ofSize: 11); freeLabel.textColor = .secondaryLabelColor
        let tableScroll = NSScrollView(); tableScroll.documentView = table; tableScroll.hasVerticalScroller = true
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        let sumScroll = NSStackView(views: [freeLabel, tableScroll]); sumScroll.orientation = .vertical; sumScroll.alignment = .leading
        NSLayoutConstraint.activate([tableScroll.widthAnchor.constraint(equalTo: sumScroll.widthAnchor)])
        let drops = NSStackView(views: [drop, sumScroll])
        drops.spacing = 12; drops.alignment = .top
        let stack = NSStackView(views: [top, head, drops, note, scroll])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for v in [top, drop, scroll, drops, sumScroll] { v.translatesAutoresizingMaskIntoConstraints = false }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Leaf Send"; window.contentView = stack; window.minSize = NSSize(width: 680, height: 460)
        NSLayoutConstraint.activate([
            top.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            drops.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            sumScroll.widthAnchor.constraint(equalToConstant: 240),
            drop.heightAnchor.constraint(equalToConstant: 220),
            sumScroll.heightAnchor.constraint(equalTo: drop.heightAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
        setHost(nil)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        find()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func setHost(_ h: String?) {
        host = h
        dot.textColor = h == nil ? .systemGray : .systemGreen
        drop.label = h == nil ? "Find the Kindle, then drop books or tests here" : "Drop books or tests here"
    }
    func log(_ s: String) { logView.string = s + "\n" + logView.string }

    @objc func find() {
        guard !busy else { return }
        busy = true; setHost(nil); status.stringValue = "Looking for the Kindle…"
        let last = UserDefaults.standard.string(forKey: lastKey)
        DispatchQueue.global().async {
            let keyErr = Setup.ensureKey()
            let r = keyErr == nil ? Setup.find(last: last) { m in DispatchQueue.main.async { self.status.stringValue = m } } : nil
            DispatchQueue.main.async {
                self.busy = false
                if let keyErr { self.status.stringValue = "Could not make a key: \(keyErr)"; return }
                guard let r else {
                    self.status.stringValue = "Kindle not found"
                    self.log("Kindle not found. On the Kindle: KOReader → Network (globe) → SSH server → Start, on the same Wi-Fi as this Mac. Then Find Kindle.")
                    return
                }
                if let p = r.problem {
                    self.status.stringValue = "Found \(r.host): \(p)"
                    self.log("Found a KOReader SSH server at \(r.host), but \(p). First time: plug the Kindle in by USB and tap Set up key (USB).")
                    return
                }
                self.setHost(r.host); self.status.stringValue = "Kindle at \(r.host)"
                self.log("Connected to the Kindle at \(r.host).")
                UserDefaults.standard.set(r.host, forKey: self.lastKey)
                self.refreshSummary()
            }
        }
    }

    @objc func refreshSummary() {
        guard let host else { show(nil, "Connect to see the Kindle's folders."); return }
        let k = Kindle(host: host, key: Setup.key, knownHosts: Setup.knownHosts)
        DispatchQueue.global().async {
            let (sum, err) = k.summary()
            DispatchQueue.main.async { self.show(sum, "Could not list: \(err ?? "?")") }
        }
    }

    func show(_ s: Summary?, _ otherwise: String) {
        summary = s
        freeLabel.stringValue = s.map { $0.text.components(separatedBy: "\n")[0] + " · click a folder for its books" } ?? otherwise
        table.reloadData()
    }

    func numberOfRows(in t: NSTableView) -> Int { summary?.folders.count ?? 0 }
    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let f = summary!.folders[row]
        let cell = NSTextField(labelWithString: "\(f.name)  ·  \(f.count)")
        cell.font = .systemFont(ofSize: 13); cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }
    func tableViewSelectionDidChange(_ n: Notification) {
        let row = table.selectedRow
        guard row >= 0, let s = summary else { return }
        table.deselectAll(nil)
        let f = s.folders[row]
        let names = s.files[f.name] ?? []
        showFolder(f.name, names.isEmpty ? "No books here yet." : names.joined(separator: "\n"))
    }

    /// Sheet with one folder's book list.
    func showFolder(_ name: String, _ body: String) {
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380), styleMask: [.titled], backing: .buffered, defer: false)
        let title = NSTextField(labelWithString: name.hasPrefix("(") ? "documents" : "documents/" + name)
        title.font = .boldSystemFont(ofSize: 14)
        let text = NSTextView(); text.isEditable = false; text.font = .systemFont(ofSize: 13); text.string = body
        text.drawsBackground = true; text.backgroundColor = .textBackgroundColor
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true
        let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.drawsBackground = true
        let close = NSButton(title: "Close", target: nil, action: nil); close.keyEquivalent = "\r"
        let box = NSStackView(views: [title, scroll, close]); box.orientation = .vertical; box.alignment = .leading
        box.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo: box.widthAnchor, constant: -32), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)])
        sheet.contentView = box
        sheet.isReleasedWhenClosed = false
        close.target = self; close.action = #selector(endSheet(_:))
        window.beginSheet(sheet)
    }
    @objc func endSheet(_ b: NSButton) { if let s = b.window { window.endSheet(s) } }

    @objc func setupKey() {
        do {
            let files = try Setup.installKey()
            log("Key installed on the Kindle (\(files.count) files). Eject it, start KOReader's SSH server, then Find Kindle.")
        } catch { log("Set up key: \(error.localizedDescription)") }
    }

    func send(_ urls: [URL]) {
        guard let host, !busy else { log(busy ? "Busy, try again in a moment." : "Find the Kindle first."); return }
        var items: [Item] = []
        for u in urls {
            do { items += try Router.plan(u) } catch { log("✗ \(u.lastPathComponent): \(error)") }
        }
        guard !items.isEmpty else { return }
        busy = true; status.stringValue = "Sending \(items.count) file(s)…"
        let k = Kindle(host: host, key: Setup.key, knownHosts: Setup.knownHosts)
        DispatchQueue.global().async {
            let err = k.send(items)
            DispatchQueue.main.async {
                self.busy = false; self.status.stringValue = "Kindle at \(host)"
                if let err { self.log("✗ Send failed: \(err)") }
                else { for it in items { self.log("✓ \(it.local.lastPathComponent) → \(it.folder)") } }
                self.refreshSummary()
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = {
    let m = NSMenu(), item = NSMenuItem(); m.addItem(item)
    let sub = NSMenu(); sub.addItem(withTitle: "Quit Leaf Send", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = sub; return m
}()
app.run()
