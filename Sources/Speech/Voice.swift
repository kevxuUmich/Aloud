import Foundation

public enum Quality: Int, Sendable, Comparable, Hashable {
    case standard, enhanced, premium
    public var label: String {
        switch self {
        case .standard: "Default"
        case .enhanced: "Enhanced"
        case .premium: "Premium"
        }
    }
    public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
}

public struct Voice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: Quality
    public init(id: String, name: String, language: String, quality: Quality) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }
}

extension Voice {
    /// The name without the quality Apple appends in brackets: "Jamie" out of
    /// "Jamie (Enhanced)". The row already prints the quality beside the name, so the
    /// bracket would say it twice, and the recommended list matches on the bare name.
    /// Only a quality is stripped: "Eddy (English (UK))" is a name with brackets of its
    /// own, and stays whole.
    public static func bareName(_ name: String) -> String {
        for q in [Quality.enhanced, .premium] {
            let suffix = " (\(q.label))"
            if name.hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
        }
        return name
    }
}
