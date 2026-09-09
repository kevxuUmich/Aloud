import Foundation

public enum Search {
    /// Documents whose title or body contains the query, ignoring case and diacritics.
    /// PDF bodies are not read here; a PDF matches on its title.
    ///
    /// Cancellable, and it has to be: the debounce restarts this on every keystroke, and
    /// a superseded query that kept reading files would spend the vault's whole disk
    /// budget on an answer nobody wants. `matches` is nonisolated and async, so it runs
    /// on the cooperative pool rather than the caller's actor, and a plain `await` from
    /// the model carries the model's cancellation into the loop below. A cancelled run
    /// returns what it had; the caller discards it.
    public static func matches(_ query: String, in documents: [Document]) async -> Set<String> {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Set(documents.map(\.id)) }
        var hits = Set<String>()
        for d in documents {
            if Task.isCancelled { return hits }
            if d.title.localizedStandardContains(q) {
                hits.insert(d.id)
                continue
            }
            guard d.type != .pdf, let body = try? String(contentsOf: d.url, encoding: .utf8)
            else { continue }
            if body.localizedStandardContains(q) { hits.insert(d.id) }
        }
        return hits
    }
}
