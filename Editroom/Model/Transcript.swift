import Foundation

/// What's said in a file: each word with its time in the file. Made once per file on this Mac (Apple's
/// on-device speech recognition), in the background after import, and kept on disk, so Magic and Media
/// search can use it at once and nothing is sent anywhere.
struct Transcript: Codable, Equatable {
    struct Word: Codable, Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    var words: [Word]
    var language: String

    var isEmpty: Bool { words.isEmpty }
    var text: String { words.map(\.text).joined(separator: " ") }

    /// Stretches of talking: words closer than `gap` seconds run together.
    func speech(gap: Double = 0.45) -> [(start: Double, end: Double)] {
        var out: [(Double, Double)] = []
        for w in words {
            if let last = out.last, w.start - last.1 < gap {
                out[out.count - 1].1 = max(last.1, w.end)
            } else {
                out.append((w.start, w.end))
            }
        }
        return out.map { (start: $0.0, end: $0.1) }
    }

    /// Sentences (or runs of talking, if there's no punctuation), with their times.
    func sentences(gap: Double = 0.8) -> [(start: Double, end: Double, text: String)] {
        var out: [(Double, Double, [String])] = []
        for w in words {
            let ends = out.last?.2.last.map { $0.hasSuffix(".") || $0.hasSuffix("?") || $0.hasSuffix("!") } ?? true
            if let last = out.last, !ends, w.start - last.1 < gap {
                out[out.count - 1].1 = w.end
                out[out.count - 1].2.append(w.text)
            } else {
                out.append((w.start, w.end, [w.text]))
            }
        }
        return out.map { (start: $0.0, end: $0.1, text: $0.2.joined(separator: " ")) }
    }

    /// Whether they say these words, in this order (case and punctuation aside). With `typing`, the last
    /// word can be the start of one ("gu" finds "guys"), for searching as it's typed.
    func says(_ phrase: String, typing: Bool = false) -> Bool {
        let want = Self.tokens(phrase)
        guard !want.isEmpty else { return false }
        let have = Self.tokens(text)
        guard have.count >= want.count else { return false }
        for i in 0...(have.count - want.count) {
            let run = have[i..<(i + want.count)]
            let whole = zip(run.dropLast(), want.dropLast()).allSatisfy { $0 == $1 }
            let last = typing ? run.last!.hasPrefix(want.last!) : run.last! == want.last!
            if whole && last { return true }
        }
        return false
    }

    /// A few words either side of where they say this, for showing why a clip matched:
    /// ("okay", "guys,", "we're on the way…").
    func snippet(_ phrase: String, typing: Bool = false) -> (before: String, match: String, after: String)? {
        let want = Self.tokens(phrase)
        guard !want.isEmpty, words.count >= want.count else { return nil }
        let have = words.map { Self.tokens($0.text).first ?? "" }
        for i in 0...(words.count - want.count) {
            let run = have[i..<(i + want.count)]
            let whole = zip(run.dropLast(), want.dropLast()).allSatisfy { $0 == $1 }
            let last = typing ? run.last!.hasPrefix(want.last!) : run.last! == want.last!
            guard whole && last else { continue }
            let from = max(0, i - 3), to = min(words.count, i + want.count + 4)
            let before = words[from..<i].map(\.text).joined(separator: " ")
            let match = words[i..<(i + want.count)].map(\.text).joined(separator: " ")
            let after = words[(i + want.count)..<to].map(\.text).joined(separator: " ")
            return ((from > 0 ? "…" : "") + before, match, after + (to < words.count ? "…" : ""))
        }
        return nil
    }

    /// Every place they say these words, with their times in the file and a few words around.
    func occurrences(_ phrase: String) -> [(start: Double, end: Double, context: String)] {
        let want = Self.tokens(phrase)
        guard !want.isEmpty, words.count >= want.count else { return [] }
        let have = words.map { Self.tokens($0.text).first ?? "" }
        var out: [(Double, Double, String)] = []
        for i in 0...(words.count - want.count) where Array(have[i..<(i + want.count)]) == want {
            let from = max(0, i - 4), to = min(words.count, i + want.count + 5)
            out.append((words[i].start, words[i + want.count - 1].end, words[from..<to].map(\.text).joined(separator: " ")))
        }
        return out.map { (start: $0.0, end: $0.1, context: $0.2) }
    }

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
    }
}
