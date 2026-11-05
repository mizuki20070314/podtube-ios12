import UIKit

/// Adds parsed channels to the local subscriptions.
enum SubscriptionImporter {
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
            if let d = try? Data(contentsOf: u) { all.append(contentsOf: SubscriptionParser.parse(d)) }
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
