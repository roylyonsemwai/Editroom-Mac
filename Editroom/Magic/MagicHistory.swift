import Foundation

/// The prompts sent with Magic, newest first: the last 20, each once. Kept in the project file, so each
/// project has its own list.
enum MagicHistory {
    struct Entry: Codable, Equatable, Hashable, Identifiable {
        var text: String
        /// The Magic tab it was sent from (claude, chatgpt, local).
        var tab: String
        var date: Date
        var id: String { text }
    }

    static let limit = 20

#if !EDITROOM_CORE
    /// The list with a just-sent prompt at the top (moved there if it was sent before).
    static func adding(_ text: String, tab: MagicAgent.Tab, to list: [Entry]) -> [Entry]? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var list = list.filter { $0.text != t }
        list.insert(Entry(text: t, tab: tab.rawValue, date: Date()), at: 0)
        return Array(list.prefix(limit))
    }
#endif
}
