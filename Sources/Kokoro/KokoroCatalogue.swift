import Foundation
import Speech

/// One of the shipped Kokoro voices: the id the engine knows it by, the name the
/// picker shows, and the language tag the region and the phonemizer come from.
public struct KokoroVoice: Sendable, Hashable, Identifiable {
    public let kokoroID: String
    public let name: String
    public let language: String

    /// The Aloud id: the engine's id under the prefix, so it never meets an Apple
    /// identifier.
    public var id: String { KokoroCatalogue.prefix + kokoroID }
    /// The voice as the rest of the app sees it. Premium, so it sorts to the top of a
    /// language section.
    public var voice: Voice { Voice(id: id, name: name, language: language, quality: .premium) }
    /// British voices take the British phonemizer; the engine reads it off the id too.
    public var british: Bool { kokoroID.hasPrefix("b") }
}

/// The picker's grouping: one region, its voices in catalogue order.
public struct KokoroRegion: Identifiable, Sendable {
    public let name: String
    public let voices: [KokoroVoice]
    public var id: String { name }
}

public enum KokoroCatalogue {
    public static let prefix = "kokoro."

    /// The seven, American then British, as the spec lists them.
    public static let voices: [KokoroVoice] = [
        KokoroVoice(kokoroID: "af_bella", name: "Bella", language: "en-US"),
        KokoroVoice(kokoroID: "af_sarah", name: "Sarah", language: "en-US"),
        KokoroVoice(kokoroID: "am_michael", name: "Michael", language: "en-US"),
        KokoroVoice(kokoroID: "am_fenrir", name: "Fenrir", language: "en-US"),
        KokoroVoice(kokoroID: "bf_emma", name: "Emma", language: "en-GB"),
        KokoroVoice(kokoroID: "bm_george", name: "George", language: "en-GB"),
        KokoroVoice(kokoroID: "bm_fable", name: "Fable", language: "en-GB"),
    ]

    public static var speechVoices: [Voice] { voices.map(\.voice) }

    public static func isKokoro(_ id: String) -> Bool { id.hasPrefix(prefix) }

    public static func voice(for id: String) -> KokoroVoice? { voices.first { $0.id == id } }

    /// Grouped by region name, in the order the regions first appear.
    public static var regions: [KokoroRegion] {
        var names: [String] = []
        var grouped: [String: [KokoroVoice]] = [:]
        for v in voices {
            let name = v.voice.regionName ?? v.language
            if grouped[name] == nil { names.append(name) }
            grouped[name, default: []].append(v)
        }
        return names.map { KokoroRegion(name: $0, voices: grouped[$0] ?? []) }
    }
}
