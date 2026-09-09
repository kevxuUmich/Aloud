import Foundation

public struct VoiceGroup: Identifiable, Hashable, Sendable {
    public let language: String
    public let name: String
    public let voices: [Voice]
    public var id: String { language }
    public init(language: String, name: String, voices: [Voice]) {
        self.language = language
        self.name = name
        self.voices = voices
    }
}

/// The popover's list: one section per language, the one being read first, and the
/// best voice at the top of each section.
public enum VoiceGroups {
    /// The reader's language as a BCP-47 tag, which is the spelling `group` sorts by.
    /// `Locale.current.identifier` is underscored ("en_US") and the grouping splits a
    /// tag on its dash, so asking for it in that spelling left the whole identifier in
    /// the language slot and the current language never came first. It is written down
    /// once here so the two pickers cannot spell it two ways again.
    public static var currentLanguage: String { Locale.current.identifier(.bcp47) }

    public static func group(_ voices: [Voice], currentLanguage: String) -> [VoiceGroup] {
        let current = code(currentLanguage)
        var buckets: [String: [Voice]] = [:]
        for v in voices { buckets[code(v.language), default: []].append(v) }
        let groups = buckets.map { key, vs in
            VoiceGroup(
                language: key,
                name: Locale.current.localizedString(forLanguageCode: key) ?? key,
                voices: vs.sorted {
                    if $0.quality != $1.quality { return $0.quality > $1.quality }
                    return $0.name < $1.name
                })
        }
        return groups.sorted {
            if $0.language == current { return true }
            if $1.language == current { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The language part of a BCP-47 tag: "en" out of "en-GB".
    static func code(_ tag: String) -> String {
        String(tag.split(separator: "-").first ?? Substring(tag))
    }
}

extension Voice {
    /// The region part of the tag in the reader's own language, or nil when the tag
    /// carries none.
    public var regionName: String? {
        let parts = language.split(separator: "-")
        guard parts.count > 1 else { return nil }
        return Locale.current.localizedString(forRegionCode: String(parts[1]))
    }
}
