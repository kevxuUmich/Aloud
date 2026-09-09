import Foundation

/// The voice popover's search field, as a pure function over the grouped list.
///
/// A reader looking for a voice knows one of four things about it: its name, the
/// language it speaks, the region that language is spoken in, or how good it is. All
/// four are matched, because the list shows all four and anything on screen is
/// something a search field invites you to type.
public enum VoiceSearch {
    /// The groups with every voice that does not match dropped, and every group left
    /// empty by that dropped with it. An empty or blank query is not a filter that
    /// matches nothing but no filter at all, so the input comes back untouched.
    public static func filter(_ groups: [VoiceGroup], query: String) -> [VoiceGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { g in
            // The group's own name is the language in the reader's words, and it is
            // written nowhere on the row, so a group that matches keeps all its voices.
            if matches(g.name, q) { return g }
            let kept = g.voices.filter {
                matches($0.name, q) || matches($0.regionName, q) || matches($0.quality.label, q)
            }
            return kept.isEmpty ? nil : VoiceGroup(language: g.language, name: g.name, voices: kept)
        }
    }

    /// Case- and diacritic-insensitive, and in the reader's own collation: a search for
    /// "jose" has to find "José".
    private static func matches(_ haystack: String?, _ needle: String) -> Bool {
        haystack?.localizedStandardContains(needle) ?? false
    }
}
