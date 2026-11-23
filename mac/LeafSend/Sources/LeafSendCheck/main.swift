import Foundation
import LeafSendCore

// Routing, subnet and sftp-batch checks. Run: swift run LeafSendCheck
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("leafsend-check-\(getpid())")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
func file(_ name: String) -> URL { let u = tmp.appendingPathComponent(name); FileManager.default.createFile(atPath: u.path, contents: Data()); return u }
func key(_ j: String) -> (URL) -> Data? { { _ in Data(j.utf8) } }
let none: (URL) -> Data? = { _ in nil }

// plain books → From Mac; unknown types refused
assert(try! Router.plan(file("Educated.epub"), readKey: none) == [Item(local: tmp.appendingPathComponent("Educated.epub"), folder: "From Mac")])
assert(try! Router.plan(file("Paper.PDF"), readKey: none).first?.folder == "From Mac")
do { _ = try Router.plan(file("notes.docx"), readKey: none); assertionFailure("docx accepted") } catch let e as RouteError { assert(e == .unsupported("docx")) }

// tests by their key
let t5 = file("set.epub")
assert(try! Router.plan(t5, readKey: key(#"{"exam":"toeic","part":5}"#)).map(\.folder) == ["TOEIC/Part 5"])
assert(try! Router.plan(t5, readKey: key(#"{"version":1}"#)).map(\.folder) == ["IELTS"])
do { _ = try Router.plan(t5, readKey: key(#"{"exam":"toeic","part":9}"#)); assertionFailure() } catch let e as RouteError { if case .badTest = e {} else { assertionFailure() } }
do { _ = try Router.plan(t5, readKey: key("{")); assertionFailure() } catch let e as RouteError { if case .badTest = e {} else { assertionFailure() } }

// listening: the audio goes along; missing audio or a path in audio.file is refused
let lis = #"{"skill":"listening","audio":{"file":"talk.pcm"}}"#
do { _ = try Router.plan(t5, readKey: key(lis)); assertionFailure() } catch let e as RouteError { assert(e == .missingAudio("talk.pcm")) }
_ = file("talk.pcm")
let li = try! Router.plan(t5, readKey: key(lis))
assert(li.map(\.folder) == ["IELTS/Listening", "IELTS/Listening"] && li[1].local.lastPathComponent == "talk.pcm")
assert(try! Router.plan(t5, readKey: key(#"{"exam":"toeic","part":2,"skill":"listening","audio":{"file":"talk.pcm"}}"#)).map(\.folder) == ["TOEIC/Part 2", "TOEIC/Part 2"])
do { _ = try Router.plan(t5, readKey: key(#"{"skill":"listening","audio":{"file":"../x.pcm"}}"#)); assertionFailure() } catch {}

// real EPUB key extraction (zip made with macOS zip)
let epub = tmp.appendingPathComponent("real.epub")
try! FileManager.default.createDirectory(at: tmp.appendingPathComponent("z/META-INF"), withIntermediateDirectories: true)
try! #"{"exam":"toeic","part":7}"#.write(to: tmp.appendingPathComponent("z/META-INF/leaf-ielts.json"), atomically: true, encoding: .utf8)
let zr = Process(); zr.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zr.currentDirectoryURL = tmp.appendingPathComponent("z")
zr.arguments = ["-q", "-r", epub.path, "META-INF"]; try! zr.run(); zr.waitUntilExit()
assert(try! Router.plan(epub).map(\.folder) == ["TOEIC/Part 7"], "unzip key")
assert(Zip.leafKey(file("plain.epub")) == nil)

// subnet: /23 around 192.168.1.28, nearest first, self/network/broadcast excluded
let ip: UInt32 = 0xC0A8_011C, mask: UInt32 = 0xFFFF_FE00
let hs = subnetHosts(ip: ip, mask: mask)
assert(hs.count == 509 && (hs[0] == "192.168.1.27" || hs[0] == "192.168.1.29"))
assert(!hs.contains("192.168.1.28") && !hs.contains("192.168.0.0") && !hs.contains("192.168.1.255") && hs.contains("192.168.0.1"))
assert(subnetHosts(ip: 0x0A00_0005, mask: 0xFF00_0000).count == 1021, "wide nets capped to a /22")

// sftp batch: folders once, quoted paths, glob characters escaped
let b = sftpBatch([Item(local: URL(fileURLWithPath: "/a/Set [1]*.epub"), folder: "TOEIC/Part 5"),
                   Item(local: URL(fileURLWithPath: "/a/x\"y.pcm"), folder: "TOEIC/Part 5")])
assert(b == """
-mkdir "/mnt/us/documents/TOEIC"
-mkdir "/mnt/us/documents/TOEIC/Part 5"
put "/a/Set \\[1\\]\\*.epub" "/mnt/us/documents/TOEIC/Part 5/Set \\[1\\]\\*.epub"
put "/a/x\\"y.pcm" "/mnt/us/documents/TOEIC/Part 5/x\\"y.pcm"

""", b)
assert(!isDropbear("127.0.0.1", port: 1, timeout: 0.2), "closed port is not a Kindle")

// Kindle summary: book counts per folder, .sdr metadata and non-books skipped, Leaf folders first
let listing = """
/mnt/us/documents/IELTS/a.epub
/mnt/us/documents/IELTS/b.epub
/mnt/us/documents/IELTS/a.sdr/metadata.epub.lua
/mnt/us/documents/IELTS/Listening/t.epub
/mnt/us/documents/IELTS/Listening/t.pcm
/mnt/us/documents/TOEIC/Part 5/s.epub
/mnt/us/documents/English/Educated.epub
/mnt/us/documents/Anh.prc
/mnt/us/documents/book.pdf
===
/dev/loop0 3000000 1000000 2202009 31% /mnt/us
"""
let sm = Summary.parse(listing)
assert(sm.folders.map { "\($0.name)=\($0.count)" } == ["IELTS=2", "IELTS/Listening=1", "TOEIC/Part 5=1", "From Mac=0", "(documents)=1", "English=1"], "\(sm.folders)")
assert(sm.files["IELTS"] == ["a.epub", "b.epub"] && sm.files["IELTS/Listening"] == ["t.epub"] && sm.files["From Mac"] == nil)
assert(sm.freeKB == 2202009 && sm.text.hasPrefix("2.1 GB free\nIELTS  ·  2"))
print("PASS: LeafSend routing, key extraction, subnet, sftp batch")
