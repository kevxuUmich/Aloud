import Foundation

public enum Search {
    /// Documents whose title or body contains the query, ignoring case and diacritics.
    /// PDF bodies are not read here; a PDF matches on its title.
    public static func matches(_ query: String, in documents: [Document]) async -> Set<String> {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Set(documents.map(\.id)) }
        return await Task.detached(priority: .userInitiated) {
            var hits = Set<String>()
            for d in documents {
                if d.title.localizedStandardContains(q) {
                    hits.insert(d.id)
                    continue
                }
                guard d.type != .pdf, let body = try? String(contentsOf: d.url, encoding: .utf8)
                else { continue }
                if body.localizedStandardContains(q) { hits.insert(d.id) }
            }
            return hits
        }.value
    }
}
