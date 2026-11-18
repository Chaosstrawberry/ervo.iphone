import Foundation
import WebKit

/// Compiles the bundled blocklist (Resources/blockerList.json) into a WebKit content rule list.
/// Compilation happens once per list version; afterwards the compiled list is loaded from disk.
@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var ruleList: WKContentRuleList?
    private var loading = false

    func load() async {
        guard ruleList == nil, !loading else { return }
        loading = true
        defer { loading = false }

        guard let store = WKContentRuleListStore.default(),
              let fileURL = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
              let json = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        let identifier = "ervo-\(Self.stableHash(json))"

        if let cached = await lookUp(store, identifier) {
            ruleList = cached
            return
        }
        ruleList = await compile(store, identifier, json)
        await removeStaleLists(store, keeping: identifier)
    }

    private func lookUp(_ store: WKContentRuleListStore, _ identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    private func compile(_ store: WKContentRuleListStore, _ identifier: String, _ json: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let error { print("[ErvoBrowser] Content blocker compile error: \(error)") }
                continuation.resume(returning: list)
            }
        }
    }

    private func removeStaleLists(_ store: WKContentRuleListStore, keeping identifier: String) async {
        let identifiers: [String] = await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { ids in
                continuation.resume(returning: ids ?? [])
            }
        }
        for id in identifiers where id != identifier && id.hasPrefix("ervo-") {
            store.removeContentRuleList(forIdentifier: id) { _ in }
        }
    }

    /// Deterministic hash (djb2) – Swift's hashValue changes between launches.
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
