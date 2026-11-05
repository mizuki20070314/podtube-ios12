import UIKit

/// Imports subscriptions from files exported by other apps:
///  - Google Takeout `subscriptions.csv` (Channel Id, Channel Url, Channel Title)
///  - NewPipe / Piped / FreeTube style JSON
///  - OPML (old YouTube subscription export)
/// Anything else that mentions channel ids (UC…) is scanned for ids as a last resort.
enum SubscriptionImporter {
    private static let idPattern = "UC[0-9A-Za-z_-]{22}"

    static func parse(_ data: Data) -> [ChannelItem] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { return [] }
        var found: [String: ChannelItem] = [:]
        var order: [String] = []

        func add(_ id: String, _ name: String) {
            if found[id] == nil {
                var c = ChannelItem(id: id)
                c.name = name
                found[id] = c
                order.append(id)
            } else if let existing = found[id], existing.name.isEmpty, !name.isEmpty {
                found[id]?.name = name
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSON (NewPipe: {"subscriptions":[{"url":".../channel/UC...","name":"..."}]}, Takeout JSON, FreeTube lines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            let root = JSON.parse(data)
            func walk(_ node: JSON) {
                if let d = node.dict {
                    let id = firstId(in: [node["channelId"].stringValue, node["id"].stringValue, node["url"].stringValue,
                                          node["snippet"]["resourceId"]["channelId"].stringValue,
                                          node["xmlUrl"].stringValue])
                    if let id = id {
                        let name = [node["name"].stringValue, node["title"].stringValue, node["snippet"]["title"].stringValue]
                            .first(where: { !$0.isEmpty }) ?? ""
                        add(id, name)
                    }
                    for k in d.keys.sorted() { walk(node[k]) }
                } else if node.isArray {
                    for x in node.array { walk(x) }
                }
            }
            walk(root)
        }

        // CSV
        if found.isEmpty && trimmed.contains(",") {
            for line in trimmed.components(separatedBy: .newlines) {
                guard let id = firstId(in: [line]) else { continue }
                let cols = splitCSV(line)
                let name = cols.count >= 3 ? cols[2] : ""
                add(id, name)
            }
        }

        // OPML
        if found.isEmpty && trimmed.contains("<outline") {
            if let re = try? NSRegularExpression(pattern: "<outline[^>]*>", options: []) {
                let ns = text as NSString
                for m in re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                    let tag = ns.substring(with: m.range)
                    if let id = firstId(in: [tag]) {
                        add(id, attribute("text", in: tag) ?? attribute("title", in: tag) ?? "")
                    }
                }
            }
        }

        // last resort: any channel ids in the file
        if found.isEmpty, let re = try? NSRegularExpression(pattern: idPattern, options: []) {
            let ns = text as NSString
            for m in re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                add(ns.substring(with: m.range), "")
            }
        }
        return order.compactMap { found[$0] }
    }

    private static func firstId(in strings: [String]) -> String? {
        guard let re = try? NSRegularExpression(pattern: idPattern, options: []) else { return nil }
        for s in strings where !s.isEmpty {
            let ns = s as NSString
            if let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range)
            }
        }
        return nil
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: name + "=\"([^\"]*)\"", options: []) else { return nil }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        let v = ns.substring(with: m.range(at: 1))
        return v.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func splitCSV(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quoted = false
        for ch in line {
            if ch == "\"" {
                quoted = !quoted
            } else if ch == "," && !quoted {
                out.append(cur)
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur)
        return out
    }

    /// Adds `channels` to the local subscriptions and fills in avatars / names in the background.
    static func apply(_ channels: [ChannelItem], completion: @escaping (Int) -> Void) {
        var merged = Store.shared.subscriptions
        let known = Set(merged.map { $0.id })
        var added: [ChannelItem] = []
        for c in channels where !known.contains(c.id) {
            merged.append(c)
            added.append(c)
        }
        Store.shared.replaceSubscriptions(merged)
        completion(added.count)

        // Fetch avatar / display name for the new ones (small requests, 3 at a time).
        DispatchQueue.global(qos: .utility).async {
            let sem = DispatchSemaphore(value: 3)
            let group = DispatchGroup()
            for c in added {
                sem.wait()
                group.enter()
                InnerTube.shared.channelBasics(id: c.id) { result in
                    if case .success(let info) = result, !info.name.isEmpty {
                        DispatchQueue.main.async {
                            var list = Store.shared.subscriptions
                            if let i = list.firstIndex(where: { $0.id == c.id }) {
                                list[i] = info.asItem
                                Store.shared.replaceSubscriptions(list)
                            }
                        }
                    }
                    sem.signal()
                    group.leave()
                }
            }
        }
    }
}

/// Presents the document picker and runs the import.
final class SubscriptionImportCoordinator: NSObject, UIDocumentPickerDelegate {
    static let shared = SubscriptionImportCoordinator()

    func present(from host: UIViewController) {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.text", "public.xml"], in: .import)
        picker.delegate = self
        host.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var all: [ChannelItem] = []
        for u in urls {
            if let d = try? Data(contentsOf: u) { all.append(contentsOf: SubscriptionImporter.parse(d)) }
        }
        if all.isEmpty {
            Toast.show(L10n.t("subs.importFailed"))
            return
        }
        SubscriptionImporter.apply(all) { n in
            Toast.show(L10n.t("subs.imported", "\(n)"))
        }
    }
}
