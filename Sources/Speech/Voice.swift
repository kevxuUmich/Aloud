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
