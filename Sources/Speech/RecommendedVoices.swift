import Foundation

/// A voice worth pointing a first-time reader at, named by what it is called in System
/// Settings rather than by identifier: the identifier is Apple's, changes between the
/// enhanced and premium builds of the same voice, and once carried a different name
/// than the label (Jamie's is still "Malcolm"). Name, language and quality together
/// find the installed voice when there is one.
public struct RecommendedVoice: Hashable, Sendable, Identifiable {
    public let name: String
    public let language: String
    public let quality: Quality
    /// What System Settings will fetch, in megabytes, as the badge beside the name.
    /// Read from Apple's own asset catalogue on disk, the same figure Settings shows,
    /// so a reader can weigh the voice against the download before leaving the app.
    public let downloadMB: Int
    public var id: String { "\(language).\(name).\(quality.rawValue)" }
    public var sizeLabel: String { "\(downloadMB) MB" }
    /// The region the recommended voice speaks in, in the reader's own language, so a
    /// voice that is not installed is still placed on the row.
    public var regionName: String? {
        Voice(id: id, name: name, language: language, quality: quality).regionName
    }
    public init(name: String, language: String, quality: Quality, downloadMB: Int) {
        self.name = name
        self.language = language
        self.quality = quality
        self.downloadMB = downloadMB
    }
}

/// A recommendation next to the installed voice it names, or next to nothing when the
/// voice has not been downloaded yet.
public struct RecommendedEntry: Hashable, Sendable, Identifiable {
    public let recommendation: RecommendedVoice
    public let voice: Voice?
    public var id: String { recommendation.id }
    public var isInstalled: Bool { voice != nil }
    public init(recommendation: RecommendedVoice, voice: Voice?) {
        self.recommendation = recommendation
        self.voice = voice
    }
}

/// The handpicked list at the top of the voice picker, and the lookup that matches it
/// against what is installed.
public enum RecommendedVoices {
    /// Picked by ear, best first. The three at the top are the best readers Apple
    /// ships; Kate and Oliver are the best that come in a small download; Matilda and
    /// Stephanie round out the accents. Sizes are the enhanced builds' download sizes
    /// from the TTSAXResourceModelAssets catalogue, September 2026.
    public static let all: [RecommendedVoice] = [
        RecommendedVoice(name: "Jamie", language: "en-GB", quality: .enhanced, downloadMB: 116),
        RecommendedVoice(name: "Zoe", language: "en-US", quality: .enhanced, downloadMB: 283),
        RecommendedVoice(name: "Evan", language: "en-US", quality: .enhanced, downloadMB: 258),
        RecommendedVoice(name: "Kate", language: "en-GB", quality: .enhanced, downloadMB: 50),
        RecommendedVoice(name: "Oliver", language: "en-GB", quality: .enhanced, downloadMB: 48),
        RecommendedVoice(name: "Matilda", language: "en-AU", quality: .enhanced, downloadMB: 94),
        RecommendedVoice(name: "Stephanie", language: "en-GB", quality: .enhanced, downloadMB: 195),
    ]

    /// Every recommendation in its own order, each with the installed voice that
    /// matches it. A match is the same bare name, the same language tag and the same
    /// quality, all compared without regard to case.
    public static func resolve(_ installed: [Voice]) -> [RecommendedEntry] {
        all.map { r in
            RecommendedEntry(
                recommendation: r,
                voice: installed.first { v in
                    v.quality == r.quality
                        && v.language.caseInsensitiveCompare(r.language) == .orderedSame
                        && Voice.bareName(v.name).caseInsensitiveCompare(r.name) == .orderedSame
                })
        }
    }

    /// Whether any recommended voice is installed: the reader who has none is the one
    /// the picker's download note is for.
    public static func anyInstalled(_ installed: [Voice]) -> Bool {
        resolve(installed).contains { $0.isInstalled }
    }
}
