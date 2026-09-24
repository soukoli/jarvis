import Foundation

/// Collects chunk results by index and produces the final text in speaking order, dropping
/// hallucinations and near-duplicates. Same semantics as the Python `_transcripts[idx]` map.
public struct TranscriptAssembler: Sendable {
    private var results: [Int: String] = [:]
    private var lastAccepted: String?

    public init() {}

    /// Store a chunk result. Returns the accepted text (after filtering) or nil if dropped.
    @discardableResult
    public mutating func add(index: Int, text rawText: String) -> String? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !HallucinationFilter.isHallucination(text) else {
            results[index] = ""
            return nil
        }
        let cleaned = HallucinationFilter.strip(text)
        guard !cleaned.isEmpty else {
            results[index] = ""
            return nil
        }
        if let last = lastAccepted, HallucinationFilter.isNearDuplicate(last, cleaned) {
            results[index] = ""
            return nil
        }
        results[index] = cleaned
        lastAccepted = cleaned
        return cleaned
    }

    /// Text of everything accepted so far, in index order.
    public var text: String {
        results.keys.sorted()
            .compactMap { results[$0] }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    public var acceptedChunkCount: Int { results.values.filter { !$0.isEmpty }.count }
    public var isEmpty: Bool { results.isEmpty }
}
