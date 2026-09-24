import Foundation

/// Port of the Python app's `_is_hallucination` / `_is_near_duplicate`.
///
/// Whisper produces YouTube-subtitle artifacts ("Titulky vytvořil…", "Thank you for watching") and
/// word loops on silence or noise. The structural checks (uniqueness ratio, bigram repetition) are
/// deliberately identical to the Python thresholds so behavior does not regress.
public enum HallucinationFilter {
    /// Known artifact phrases. Add patterns; do not loosen the structural checks below.
    public static let patterns: [String] = [
        #"[Tt]itulky\s+(vytvořil|přiložil|přeložil)\s*\w*"#,
        #"[Jj]ohnn?y\s*X"#,
        #"[Dd]ěkuji?\s+za\s+pozornost"#,
        #"[Oo]debírejte"#,
        #"[Nn]apište\s+do\s+komentářů"#,
        #"[Dd]alší\s+díl\s+příště"#,
        #"[Ss]ubtitles?\s+by"#,
        #"[Ss]ubscribe"#,
        #"[Tt]hank\s+you\s+for\s+watching"#,
        #"[Tt]hanks?\s+for\s+watching"#,
        #"[Pp]řeklad\s*:"#,
        #"[Ss]ponzorováno"#,
        #"[Aa]mara\.org"#,
        #"[Ww]ww\.\w+\.\w+"#,
    ]

    private static let combined: NSRegularExpression = {
        // NSRegularExpression handles Unicode word characters (\w matches "ř") the same way Python's
        // `re` does with str patterns.
        try! NSRegularExpression(pattern: patterns.joined(separator: "|"))
    }()

    /// Remove known artifact phrases from `text`.
    public static func strip(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return combined.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if the whole chunk should be discarded.
    public static func isHallucination(_ text: String) -> Bool {
        let cleaned = strip(text)
        // Short answers ("Jo", "Ne", "OK") are legitimate dictation; only pure punctuation is noise.
        guard cleaned.contains(where: { $0.isLetter || $0.isNumber }) else { return true }

        let words = cleaned.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let unique = Set(words)

        // Ratio-based: "elected elected elected…"
        if words.count >= 6, Double(unique.count) / Double(words.count) < 0.35 { return true }
        // Strict check for very short repetitive text
        if words.count >= 4, unique.count <= 2 { return true }
        // Bigram loops: "I think I think I think"
        if words.count >= 5 {
            let bigrams = zip(words, words.dropFirst()).map { "\($0) \($1)" }
            if bigrams.count >= 4, Double(Set(bigrams).count) / Double(bigrams.count) < 0.5 { return true }
        }
        return false
    }

    /// True if two chunks share more than 80 % of their words (Whisper re-emitting a segment).
    public static func isNearDuplicate(_ a: String, _ b: String) -> Bool {
        let aw = Set(a.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        let bw = Set(b.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        let smaller = min(aw.count, bw.count)
        guard smaller >= 4 else { return false }
        return Double(aw.intersection(bw).count) / Double(smaller) > 0.8
    }
}
